from datetime import timedelta

import pytest

from fixed_clock import NOW, fixed_now
from test_gym_api import FOE_IDS, Clock, FakePokeAPI, Spy, call
from ypoke.gym_battle import GHOST_LINE, GymBattles
from ypoke.store import Store
from ypoke.trades import TradeService
from ypoke.upload_server import COWORKER_WINDOW, serve

NAMES = {"UB": "Coworker Bee", "UC": "Coworker Cee"}
WEAK = sorted(FOE_IDS)[:2]


@pytest.fixture
def ghost_server(tmp_path):
    path = str(tmp_path / "bot.sqlite3")
    store = Store(path, fixed_now)
    trades = TradeService(store, fixed_now, name_for=NAMES.get)
    uploads, notices = Spy(), Spy()
    pokeapi = FakePokeAPI()
    clock = Clock()
    http_server = serve(
        store, "127.0.0.1", 0, uploads, pokeapi.attacking_moves, name_for=NAMES.get, trades=trades,
        notify=notices, gyms=GymBattles(pokeapi, new_seed=lambda: 7), clock=clock, now=fixed_now,
    )
    yield store, trades, f"http://127.0.0.1:{http_server.server_address[1]}", uploads, notices, path
    http_server.shutdown()


def ghost(base, token, coworker_id, team=None):
    team = [{"pokemon_id": 900, "level": 50}] if team is None else team
    return call(f"{base}/v1/gym/battle", "POST", token, {"coworker_id": coworker_id, "team": team})


def upload(store, user_id, party):
    store.issue_token(user_id)
    store.save_party(user_id, party)


def weak_party():
    return [{"pokemon_id": WEAK[0], "level": 12, "shiny": False, "ivs": {}},
            {"pokemon_id": WEAK[1], "level": 60, "shiny": True, "ivs": {}}]


def test_the_coworker_list_in_the_upload_reply_carries_an_opaque_id_per_coworker(ghost_server):
    store, trades, base, *_ = ghost_server
    upload(store, "UB", weak_party())
    status, body, _ = call(f"{base}/v1/party", "POST", store.issue_token("UA"), {"party": [{"pokemon_id": 900, "level": 50}]})
    assert status == 200
    [coworker] = body["coworkers"]
    assert coworker["id"] == trades.handle("UB") and coworker["name"] == "Coworker Bee"
    assert "UB" not in coworker["id"]


def test_a_coworkers_last_party_fights_at_lv50_and_the_reply_has_the_gym_shape(ghost_server):
    store, trades, base, *_ = ghost_server
    upload(store, "UB", weak_party())
    status, body, _ = ghost(base, store.issue_token("UA"), trades.handle("UB"))
    assert status == 200 and body["ok"] is True
    assert (body["gym_id"], body["kind"], body["won"], body["seed"]) == ("ghost", "ghost", True, 7)
    assert body["trainer"] == {"name": dict.fromkeys(GHOST_LINE, "Coworker Bee"), "line": GHOST_LINE}
    assert [(member["pokemon_id"], member["level"], member["shiny"]) for member in body["foe_team"]] == [
        (WEAK[0], 50, False), (WEAK[1], 50, True)]
    assert all(member["hp"] == 0 for member in body["foe_team"])
    assert (body["run"], body["carry"]) == (None, None)
    assert [turn["turn"] for turn in body["log"]] == list(range(1, body["turns"] + 1))
    assert {event["type"] for event in body["events"]} >= {"switch", "move", "damage", "faint"}


def test_the_coworkers_side_follows_the_lineup_rules(ghost_server):
    store, trades, base, *_ = ghost_server
    upload(store, "UB", [{"pokemon_id": 25, "level": 50, "shiny": False, "ivs": {}},
                            {"pokemon_id": 25, "level": 40, "shiny": False, "ivs": {}},
                            {"pokemon_id": 7, "level": 30, "shiny": False, "ivs": {}}])
    body = ghost(base, store.issue_token("UA"), trades.handle("UB"))[1]
    assert [member["pokemon_id"] for member in body["foe_team"]] == [25, 7]


def test_a_rematch_has_no_limit_but_the_gym_rate_limit(ghost_server):
    store, trades, base, *_ = ghost_server
    upload(store, "UB", weak_party())
    token = store.issue_token("UA")
    assert ghost(base, token, trades.handle("UB"))[0] == 200
    status, body, _ = ghost(base, token, trades.handle("UB"))
    assert status == 429 and body["error"] == "rate_limited"


def test_a_ghost_battle_stores_nothing_posts_nothing_and_keeps_both_parties(ghost_server):
    store, trades, base, uploads, notices, _ = ghost_server
    upload(store, "UA", [{"pokemon_id": 900, "level": 50, "shiny": False, "ivs": {}}])
    upload(store, "UB", weak_party())
    before = (store.party("UA"), store.party("UB"))
    assert ghost(base, store.issue_token("UA"), trades.handle("UB"))[0] == 200
    assert (store.party("UA"), store.party("UB")) == before
    for user_id in ("UA", "UB"):
        assert store.recent_battles(user_id, 10) == []
        assert (store.record(user_id).wins, store.record(user_id).losses) == (0, 0)
    assert uploads.calls == [] and notices.calls == []


def test_the_reply_names_no_slack_id(ghost_server):
    store, trades, base, *_ = ghost_server
    upload(store, "UB", weak_party())
    body = ghost(base, store.issue_token("UA"), trades.handle("UB"))[1]
    assert "UB" not in repr(body) and "UA" not in repr(body)


@pytest.mark.parametrize("coworker_id", ["UB", "nobody", ""])
def test_a_slack_id_or_an_unknown_id_is_not_a_coworker(ghost_server, coworker_id):
    store, _, base, *_ = ghost_server
    upload(store, "UB", weak_party())
    status, body, _ = ghost(base, store.issue_token("UA"), coworker_id)
    assert (status, body["error"]) == (404, "unknown_coworker")


def test_a_coworker_without_a_party_or_off_the_list_is_refused(ghost_server):
    store, trades, base, _, _, path = ghost_server
    upload(Store(path, lambda: NOW - COWORKER_WINDOW - timedelta(days=1)), "UC", weak_party())
    for caller, user_id in (("UA", "UB"), ("UD", "UC")):
        status, body, _ = ghost(base, store.issue_token(caller), trades.handle(user_id))
        assert (status, body["error"]) == (404, "unknown_coworker")


def test_a_player_cannot_fight_their_own_party(ghost_server):
    store, trades, base, *_ = ghost_server
    upload(store, "UA", weak_party())
    status, body, _ = ghost(base, store.issue_token("UA"), trades.handle("UA"))
    assert (status, body["error"]) == (400, "coworker_id is your own")


def test_a_malformed_coworker_id_or_team_is_a_400(ghost_server):
    store, trades, base, *_ = ghost_server
    upload(store, "UB", weak_party())
    token = store.issue_token("UA")
    assert ghost(base, token, 5)[1]["error"] == "coworker_id must be a string"
    status, body, _ = ghost(base, store.issue_token("UD"), trades.handle("UB"), team=[])
    assert status == 400 and body["error"].startswith("team")


def test_a_bot_without_trades_knows_no_coworker(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"), fixed_now)
    pokeapi = FakePokeAPI()
    http_server = serve(store, "127.0.0.1", 0, Spy(), pokeapi.attacking_moves, gyms=GymBattles(pokeapi),
                        clock=Clock(), now=fixed_now)
    base = f"http://127.0.0.1:{http_server.server_address[1]}"
    upload(store, "UB", weak_party())
    try:
        status, body, _ = ghost(base, store.issue_token("UA"), "anything")
        assert (status, body["error"]) == (404, "unknown_coworker")
        reply = call(f"{base}/v1/party", "POST", store.issue_token("UA"), {"party": [{"pokemon_id": 900, "level": 50}]})[1]
        assert "id" not in reply["coworkers"][0]
    finally:
        http_server.shutdown()
