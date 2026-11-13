import json
import re
import urllib.error
import urllib.request

import pytest

from datetime import UTC, datetime, timedelta

from ypoke.names import FAILURE_TTL, SUCCESS_TTL, DisplayNames
from ypoke.store import Store
from ypoke.upload_server import PartyError, serve, validate_party

PIKACHU = {"pokemon_id": 25, "level": 42, "name": "피카츄", "shiny": True, "ivs": {"hp": 31}}
LEARNABLE = [
    {"id": 84, "name": "전기쇼크", "type": "electric", "power": 40, "damage_class": "special", "accuracy": 100, "weather": None, "level": 1},
    {"id": 209, "name": "스파크", "type": "electric", "power": 65, "damage_class": "physical", "accuracy": 100, "weather": None, "level": 20},
    {"id": 85, "name": "10만볼트", "type": "electric", "power": 90, "damage_class": "special", "accuracy": 100, "weather": None, "level": 36},
    {"id": 87, "name": "번개", "type": "electric", "power": 110, "damage_class": "special", "accuracy": 70, "weather": None, "level": 44},
]


NAMES = {"U2": "리자몽 트레이너", "U3": "민수"}


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
    http_server = serve(
        store, "127.0.0.1", 0, lambda user_id, party: uploads.append((user_id, party)), moves_for, NAMES.get
    )
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
    assert (status, body) == (200, {"ok": True, "party_size": 1, "recent_battles": [], "coworkers": []})
    assert uploads == [("U1", [PIKACHU])]
    status, body = call(f"{base}/v1/party", token=token)
    assert status == 200
    assert body["party"] == [PIKACHU]
    assert body["uploaded_at"].endswith("+00:00")


def test_the_dex_summary_is_stored_and_a_broken_one_never_fails_the_upload(server):
    store, base, _ = server
    token = store.issue_token("U1")
    dex = {"owned": 10, "shiny": 1, "regions": {"kanto": 10}, "representative": {"pokemon_id": 25, "shiny": False}}
    assert call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU], "dex": dex})[0] == 200
    assert store.dex("U1") == dex
    assert call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU], "dex": "broken"})[0] == 200
    assert store.dex("U1") == dex


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
    assert call(f"{base}/v1/party", "POST", token, {"party": entry}) == (200, {"ok": True, "party_size": 2, "recent_battles": [], "coworkers": []})
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


def test_a_party_is_accepted_with_and_without_nature(server):
    store, base, _ = server
    token = store.issue_token("U1")
    assert call(f"{base}/v1/party", "POST", token, {"party": [{**PIKACHU, "nature": "adamant"}]})[0] == 200
    assert call(f"{base}/v1/party", token=token)[1]["party"][0]["nature"] == "adamant"
    assert call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU]})[0] == 200
    assert "nature" not in call(f"{base}/v1/party", token=token)[1]["party"][0]


@pytest.mark.parametrize("nature", [None, 5, "", "   ", "x" * 21, ["adamant"]])
def test_a_bad_nature_is_dropped_not_rejected(nature):
    assert "nature" not in validate_party({"party": [{**PIKACHU, "nature": nature}]})[0]


def test_nature_is_lowercased_and_unknown_names_are_kept_for_the_battle_to_ignore():
    assert validate_party({"party": [{**PIKACHU, "nature": " Adamant "}]})[0]["nature"] == "adamant"
    assert validate_party({"party": [{**PIKACHU, "nature": "madeup"}]})[0]["nature"] == "madeup"


def upload_overview(base, token, lead):
    status, body = call(f"{base}/v1/party", "POST", token, {"party": [lead]})
    assert status == 200
    return body


def test_response_lists_the_last_five_battles_newest_first_from_the_uploaders_side(server):
    store, base, _ = server
    token = store.issue_token("U1")
    start = datetime.now(UTC) - timedelta(hours=1)
    for index in range(7):
        store.record_battle("U1", "U2", "U1", index, at=start + timedelta(minutes=index), pokemon=(25, 6), turns=index + 3)
    store.record_battle("U3", "U1", "U3", 99, at=start + timedelta(minutes=30), pokemon=(7, 94), turns=4)
    store.record_battle("U2", "U3", "U2", 100, at=start + timedelta(minutes=40), pokemon=(1, 2), turns=9)
    battles = upload_overview(base, token, PIKACHU)["recent_battles"]
    assert len(battles) == 5
    assert battles[0] == {
        "opponent_name": "민수", "my_pokemon_id": 94, "opponent_pokemon_id": 7, "result": "loss", "turns": 4,
        "at": battles[0]["at"],
    }
    assert [b["turns"] for b in battles[1:]] == [9, 8, 7, 6]
    assert {b["result"] for b in battles[1:]} == {"win"}
    assert battles[1]["my_pokemon_id"] == 25 and battles[1]["opponent_pokemon_id"] == 6


def test_battles_stored_before_species_were_kept_come_back_with_nulls(server):
    store, base, _ = server
    token = store.issue_token("U1")
    store.record_battle("U1", "U2", "U1", 1)
    (battle,) = upload_overview(base, token, PIKACHU)["recent_battles"]
    assert (battle["my_pokemon_id"], battle["opponent_pokemon_id"], battle["turns"]) == (None, None, None)
    assert battle["result"] == "win"


def test_response_lists_the_other_users_current_leads(server):
    store, base, _ = server
    token = store.issue_token("U1")
    store.issue_token("U2")
    store.issue_token("U3")
    store.issue_token("U4")
    store.save_party("U2", [{"pokemon_id": 6, "level": 55, "shiny": True, "ivs": {}}, {"pokemon_id": 1, "level": 5}])
    store.save_party("U3", [{"pokemon_id": 94, "level": 38, "shiny": False, "ivs": {}}])
    coworkers = upload_overview(base, token, PIKACHU)["coworkers"]
    assert sorted(coworkers, key=lambda c: c["pokemon_id"]) == [
        {"name": "리자몽 트레이너", "pokemon_id": 6, "level": 55, "shiny": True},
        {"name": "민수", "pokemon_id": 94, "level": 38, "shiny": False},
    ]


def test_stale_uploads_drop_out_of_the_coworker_list(server):
    store, base, _ = server
    token = store.issue_token("U1")
    store.issue_token("U2")
    store.save_party("U2", [{"pokemon_id": 6, "level": 55, "shiny": False, "ivs": {}}])
    old = (datetime.now(UTC) - timedelta(days=31)).isoformat(timespec="seconds")
    import sqlite3

    with sqlite3.connect(store._path) as connection:
        connection.execute("UPDATE users SET uploaded_at = ? WHERE slack_user_id = 'U2'", (old,))
    assert upload_overview(base, token, PIKACHU)["coworkers"] == []


def test_response_never_carries_slack_ids_or_tokens(server):
    store, base, _ = server
    token = store.issue_token("U1")
    other_token = store.issue_token("U2")
    store.save_party("U2", [{"pokemon_id": 6, "level": 55, "shiny": False, "ivs": {}}])
    store.record_battle("U1", "U2", "U1", 1, pokemon=(25, 6), turns=5)
    _, raw = call_raw(f"{base}/v1/party", token, {"party": [PIKACHU]})
    assert not re.search(r"\bU[0-9A-Z]{1,}\b", raw)
    assert token not in raw and other_token not in raw


def test_an_unresolvable_name_is_null_not_an_id(server):
    store, base, _ = server
    token = store.issue_token("U1")
    store.record_battle("U1", "UX", "U1", 1, pokemon=(25, 6), turns=5)
    assert upload_overview(base, token, PIKACHU)["recent_battles"][0]["opponent_name"] is None


def call_raw(url, token, body):
    request = urllib.request.Request(
        url, data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return response.status, response.read().decode()


class FakeSlack:
    def __init__(self, users):
        self.users = users
        self.calls = 0

    def users_info(self, user):
        self.calls += 1
        if user not in self.users:
            raise RuntimeError("user_not_found")
        return {"user": self.users[user]}


def test_display_name_prefers_display_then_real_name_and_is_cached():
    slack = FakeSlack({
        "U1": {"profile": {"display_name": "민수", "real_name": "김민수"}},
        "U2": {"profile": {"display_name": "", "real_name": "박은정"}},
        "U3": {"profile": {}, "real_name": "이름만"},
    })
    clock = [0.0]
    names = DisplayNames(slack, clock=lambda: clock[0])
    assert [names("U1"), names("U2"), names("U3")] == ["민수", "박은정", "이름만"]
    names("U1")
    assert slack.calls == 3
    clock[0] = SUCCESS_TTL + 1
    names("U1")
    assert slack.calls == 4


def test_a_failed_lookup_returns_none_and_retries_after_the_failure_ttl():
    slack = FakeSlack({})
    clock = [0.0]
    names = DisplayNames(slack, clock=lambda: clock[0])
    assert names("U9") is None and names("U9") is None
    assert slack.calls == 1
    clock[0] = FAILURE_TTL + 1
    names("U9")
    assert slack.calls == 2


def test_a_database_from_before_species_were_kept_is_upgraded_in_place(tmp_path):
    import sqlite3

    path = str(tmp_path / "old.sqlite3")
    with sqlite3.connect(path) as connection:
        connection.execute(
            "CREATE TABLE battles (id INTEGER PRIMARY KEY AUTOINCREMENT, challenger_id TEXT NOT NULL, "
            "opponent_id TEXT NOT NULL, winner_id TEXT NOT NULL, seed INTEGER NOT NULL, created_at TEXT NOT NULL)"
        )
        connection.execute("INSERT INTO battles VALUES (1, 'U1', 'U2', 'U2', 5, '2026-11-01T00:00:00+00:00')")
    store = Store(path)
    store.record_battle("U1", "U2", "U1", 6, pokemon=(25, 7), turns=4)
    newest, oldest = store.recent_battles("U1", 5)
    assert (newest.my_pokemon_id, newest.turns, newest.won) == (25, 4, True)
    assert (oldest.my_pokemon_id, oldest.turns, oldest.won) == (None, None, False)
