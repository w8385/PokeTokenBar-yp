import json
import urllib.error
import urllib.request

import pytest

from ypoke.store import Store
from ypoke.upload_server import PartyError, serve, validate_party

PIKACHU = {"pokemon_id": 25, "level": 42, "name": "피카츄", "shiny": True, "ivs": {"hp": 31}}


@pytest.fixture
def server(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    uploads = []
    http_server = serve(store, "127.0.0.1", 0, uploads.append)
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
    assert uploads == [[PIKACHU]]
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
