import json
import urllib.error
import urllib.request

import pytest

from ypoke.store import Store
from ypoke.upload_server import PartyError, serve, validate_party

PIKACHU = {"pokemon_id": 25, "level": 42, "name": "피카츄", "shiny": True, "ivs": {"hp": 31}}
LEARNABLE = [
    {"id": 84, "name": "전기쇼크", "type": "electric", "power": 40, "damage_class": "special", "accuracy": 100, "level": 1},
    {"id": 209, "name": "스파크", "type": "electric", "power": 65, "damage_class": "physical", "accuracy": 100, "level": 20},
    {"id": 85, "name": "10만볼트", "type": "electric", "power": 90, "damage_class": "special", "accuracy": 100, "level": 36},
    {"id": 87, "name": "번개", "type": "electric", "power": 110, "damage_class": "special", "accuracy": 70, "level": 44},
]


class FakeMoves:
    offline = False

    def __call__(self, pokemon_id, level):
        if self.offline:
            raise OSError("offline")
        return [move for move in LEARNABLE if move["level"] <= level]


@pytest.fixture
def moves_for():
    return FakeMoves()


@pytest.fixture
def server(tmp_path, moves_for):
    store = Store(str(tmp_path / "bot.sqlite3"))
    uploads = []
    http_server = serve(store, "127.0.0.1", 0, lambda user_id, party: uploads.append((user_id, party)), moves_for)
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}", uploads
    http_server.shutdown()


def call(url, method="GET", token=None, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = body if isinstance(body, bytes) else (json.dumps(body).encode() if body is not None else None)
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def test_health_needs_no_token(server):
    _, base, _ = server
    assert call(f"{base}/v1/health") == (200, {"ok": True})


def test_upload_then_read_back(server):
    store, base, uploads = server
    token = store.issue_token("U1")
    status, body = call(f"{base}/v1/party", "POST", token, {"app_version": "2.5.7", "party": [PIKACHU], "extra": 1})
    assert (status, body) == (200, {"ok": True, "party_size": 1})
    assert uploads == [("U1", [PIKACHU])]
    status, body = call(f"{base}/v1/party", token=token)
    assert status == 200
    assert body["party"] == [PIKACHU]
    assert body["uploaded_at"].endswith("+00:00")


def test_reregistering_revokes_the_old_token(server):
    store, base, _ = server
    old = store.issue_token("U1")
    new = store.issue_token("U1")
    assert call(f"{base}/v1/party", "POST", old, {"party": [PIKACHU]})[0] == 401
    assert call(f"{base}/v1/party", "POST", new, {"party": [PIKACHU]})[0] == 200


def test_a_prompt_token_works_beside_the_old_one_until_relinking(server):
    store, base, _ = server
    old = store.issue_token("U1")
    prompt = store.issue_token("U1", keep_existing=True)
    assert call(f"{base}/v1/party", "POST", old, {"party": [PIKACHU]})[0] == 200
    assert call(f"{base}/v1/party", "POST", prompt, {"party": [PIKACHU]})[0] == 200
    relinked = store.issue_token("U1")
    assert call(f"{base}/v1/party", "POST", prompt, {"party": [PIKACHU]})[0] == 401
    assert call(f"{base}/v1/party", "POST", relinked, {"party": [PIKACHU]})[0] == 200


def test_a_prompt_token_links_an_unlinked_user(server):
    store, base, _ = server
    token = store.issue_token("U1", keep_existing=True)
    assert call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU]})[0] == 200


def test_rental_is_kept_only_when_true(server):
    store, base, _ = server
    token = store.issue_token("U1")
    rental = {"pokemon_id": 1, "level": 5, "rental": True}
    assert call(f"{base}/v1/party", "POST", token, {"party": [rental]})[0] == 200
    assert call(f"{base}/v1/party", token=token)[1]["party"][0]["rental"] is True
    assert "rental" not in validate_party({"party": [{"pokemon_id": 1, "level": 5, "rental": False}]})[0]
    with pytest.raises(PartyError, match="rental must be a boolean"):
        validate_party({"party": [{"pokemon_id": 1, "level": 5, "rental": "yes"}]})


@pytest.mark.parametrize("token", [None, "wrong"])
def test_missing_or_unknown_token_is_unauthorized(server, token):
    _, base, _ = server
    assert call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU]}) == (401, {"ok": False, "error": "unauthorized"})


def test_read_before_upload_is_no_party(server):
    store, base, _ = server
    token = store.issue_token("U1")
    assert call(f"{base}/v1/party", token=token) == (404, {"ok": False, "error": "no_party"})


def test_bad_json_and_oversized_body(server):
    store, base, _ = server
    token = store.issue_token("U1")
    assert call(f"{base}/v1/party", "POST", token, b"{nope")[0] == 400
    assert call(f"{base}/v1/party", "POST", token, b"x" * (64 * 1024 + 1)) == (413, {"ok": False, "error": "too_large"})


def test_validate_fills_defaults():
    assert validate_party({"party": [{"pokemon_id": 10034, "level": 1}]}) == [
        {"pokemon_id": 10034, "level": 1, "shiny": False, "ivs": {}}
    ]


@pytest.mark.parametrize("payload, message", [
    ([], "JSON object"),
    ({"party": []}, "1 to 6"),
    ({"party": [PIKACHU] * 7}, "1 to 6"),
    ({"party": [{"pokemon_id": 1026, "level": 5}]}, "pokemon_id"),
    ({"party": [{"pokemon_id": True, "level": 5}]}, "pokemon_id"),
    ({"party": [{"pokemon_id": 25, "level": 0}]}, "level"),
    ({"party": [{"pokemon_id": 25, "level": 5, "ivs": {"speed": 32}}]}, "ivs.speed"),
    ({"party": [{"pokemon_id": 25, "level": 5, "shiny": "yes"}]}, "shiny"),
    ({"party": [{"pokemon_id": 25, "level": 5, "name": ""}]}, "name"),
    ({"app_version": 3, "party": [PIKACHU]}, "app_version"),
])
def test_validate_rejects(payload, message):
    with pytest.raises(PartyError, match=message):
        validate_party(payload)


def test_entry_with_chosen_moves_is_stored(server):
    store, base, _ = server
    token = store.issue_token("U1")
    entry = [{**PIKACHU, "moves": [85, 84]}, {"pokemon_id": 7, "level": 20, "moves": []}]
    assert call(f"{base}/v1/party", "POST", token, {"party": entry}) == (200, {"ok": True, "party_size": 2})
    stored = store.party("U1").party
    assert stored[0]["moves"] == [85, 84]
    assert "moves" not in stored[1]


@pytest.mark.parametrize("moves, message", [
    ([87], "87 is not an attacking move learnable at level 42"),
    ([999], "999 is not"),
])
def test_moves_must_be_learnable_attacking_moves_at_the_level(server, moves, message):
    store, base, uploads = server
    token = store.issue_token("U1")
    status, body = call(f"{base}/v1/party", "POST", token, {"party": [{**PIKACHU, "moves": moves}]})
    assert status == 400
    assert message in body["error"]
    assert store.party("U1") is None
    assert uploads == []


def test_moves_check_needs_pokeapi(server, moves_for):
    store, base, _ = server
    token = store.issue_token("U1")
    moves_for.offline = True
    assert call(f"{base}/v1/party", "POST", token, {"party": [{**PIKACHU, "moves": [85]}]}) == (
        503, {"ok": False, "error": "pokeapi_unavailable"})
    assert call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU]})[0] == 200


def test_learnable_moves_with_defaults(server):
    store, base, _ = server
    token = store.issue_token("U1")
    status, body = call(f"{base}/v1/moves?pokemon_id=25&level=42", token=token)
    assert status == 200
    assert [move["id"] for move in body["moves"]] == [84, 209, 85]
    assert body["moves"][2] == LEARNABLE[2]
    assert body["default"] == [84, 209, 85]


def test_learnable_moves_needs_auth_and_valid_query(server, moves_for):
    store, base, _ = server
    token = store.issue_token("U1")
    assert call(f"{base}/v1/moves?pokemon_id=25&level=42")[0] == 401
    assert call(f"{base}/v1/moves?pokemon_id=25", token=token)[0] == 400
    assert call(f"{base}/v1/moves?pokemon_id=25&level=101", token=token)[0] == 400
    assert call(f"{base}/v1/moves?pokemon_id=x&level=5", token=token)[0] == 400
    moves_for.offline = True
    assert call(f"{base}/v1/moves?pokemon_id=25&level=5", token=token)[0] == 503


@pytest.mark.parametrize("moves", [[1, 2, 3, 4, 5], [85, 85], ["85"], [0], 85, [True]])
def test_validate_rejects_bad_move_lists(moves):
    with pytest.raises(PartyError, match="moves must be a list of up to 4 distinct move ids"):
        validate_party({"party": [{**PIKACHU, "moves": moves}]})
