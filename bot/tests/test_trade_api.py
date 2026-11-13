from types import SimpleNamespace

import pytest

from test_trades import ALICE, BOB, EEVEE, HAUNTER, NAMES, PIKACHU
from test_upload_server import PIKACHU as BATTLER
from test_upload_server import FakeMoves, call
from ypoke.store import Store
from ypoke.trades import ACCEPT_ACTION_ID, TradeService
from ypoke.transport import trade_listener
from ypoke.upload_server import serve


@pytest.fixture
def api(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    service = TradeService(store, name_for=NAMES.get)
    sent = []
    server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), NAMES.get, service, sent.append)
    base = f"http://127.0.0.1:{server.server_address[1]}"
    yield SimpleNamespace(base=base, service=service, sent=sent, alice=store.issue_token(ALICE), bob=store.issue_token(BOB))
    server.shutdown()


def upload(api, token, pool=None):
    body = {"party": [BATTLER]}
    if pool is not None:
        body["trade_pool"] = pool
    return call(f"{api.base}/v1/party", "POST", token, body)


def test_the_upload_stores_the_pool_and_replies_with_deliveries(api):
    status, body = upload(api, api.alice, [HAUNTER, EEVEE])

    assert status == 200
    assert body["trades"] == {"deliveries": []}
    assert [entry["id"] for entry in api.service._pool(ALICE)] == ["alice-haunter", "alice-eevee"]


def test_an_old_app_upload_without_a_pool_keeps_the_stored_pool(api):
    upload(api, api.alice, [HAUNTER])

    assert upload(api, api.alice)[0] == 200
    assert [entry["id"] for entry in api.service._pool(ALICE)] == ["alice-haunter"]


def test_a_broken_pool_never_fails_the_battle_upload(api):
    status, _ = upload(api, api.alice, "garbage")

    assert status == 200


def test_coworkers_lists_users_with_a_pool_only(api):
    upload(api, api.bob, [PIKACHU])
    upload(api, api.alice)

    status, body = call(f"{api.base}/v1/coworkers", token=api.alice)

    assert status == 200
    assert [coworker["name"] for coworker in body["coworkers"]] == ["밥"]
    assert BOB not in str(body)
    assert call(f"{api.base}/v1/coworkers", token=api.bob)[1]["coworkers"] == []


def test_the_whole_trade_over_http_applies_on_the_next_upload_and_stops_after_the_ack(api):
    upload(api, api.alice, [HAUNTER])
    upload(api, api.bob, [PIKACHU])

    status, body = call(f"{api.base}/v1/trades", "POST", api.alice, {"to": BOB, "give": "alice-haunter"})
    assert status == 200
    trade_id = body["trade_id"]
    assert [message.user_id for message in api.sent[0]] == [BOB]
    assert api.service.pick(BOB, trade_id, "bob-pikachu").ok
    api.service.accept(BOB, trade_id)
    api.service.accept(ALICE, trade_id)

    status, body = upload(api, api.alice, [])
    assert body["trades"]["deliveries"] == [
        {"trade_id": trade_id, "give_id": "alice-haunter", "from_name": "밥", "receive": PIKACHU}]
    assert call(f"{api.base}/v1/trades", token=api.alice)[1]["trades"]["deliveries"] == body["trades"]["deliveries"]
    assert call(f"{api.base}/v1/trades/ack", "POST", api.alice, {"trade_ids": [trade_id]}) == (200, {"ok": True})
    assert upload(api, api.alice)[1]["trades"]["deliveries"] == []
    assert len(upload(api, api.bob)[1]["trades"]["deliveries"]) == 1


def test_a_refused_offer_says_why(api):
    upload(api, api.alice, [HAUNTER])

    status, body = call(f"{api.base}/v1/trades", "POST", api.alice, {"to": BOB, "give": "alice-haunter"})

    assert status == 400 and body["error"] == "unknown_user" and body["message"]
    assert api.sent == []


@pytest.mark.parametrize("path, body", [
    ("/v1/trades", {"to": BOB}),
    ("/v1/trades", [1]),
    ("/v1/trades/ack", {"trade_ids": "x"}),
])
def test_trade_posts_validate_their_body(api, path, body):
    assert call(f"{api.base}{path}", "POST", api.alice, body)[0] == 400


def test_trade_endpoints_need_a_token(api):
    assert call(f"{api.base}/v1/coworkers")[0] == 401
    assert call(f"{api.base}/v1/trades", "POST", None, {})[0] == 401


def test_without_a_trade_service_the_upload_reply_is_unchanged(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves())
    try:
        base = f"http://127.0.0.1:{server.server_address[1]}"
        token = store.issue_token(ALICE)
        reply = call(f"{base}/v1/party", "POST", token, {"party": [BATTLER], "trade_pool": [HAUNTER]})
        assert "trades" not in reply[1]
        assert reply[1]["party_size"] == 1
        assert call(f"{base}/v1/coworkers", token=token)[0] == 404
    finally:
        server.shutdown()


class FakeClient:
    def __init__(self):
        self.messages = []

    def chat_postMessage(self, **message):
        self.messages.append(message)


def press(listener, user_id, value, client=None, selected=False):
    answers = []
    action = {"selected_option": {"value": value}} if selected else {"value": value}
    listener(lambda: None, {"user": {"id": user_id}}, action, lambda **answer: answers.append(answer), client or FakeClient())
    return answers[0]


def test_buttons_answer_in_place_only_when_the_step_is_final(api):
    upload(api, api.alice, [HAUNTER])
    upload(api, api.bob, [PIKACHU])
    trade_id = api.service.propose(ALICE, BOB, "alice-haunter").trade_id
    client = FakeClient()

    picked = press(trade_listener(api.service, "pick"), BOB, f"{trade_id}|bob-pikachu", selected=True)
    early = press(trade_listener(api.service, "accept"), ALICE, trade_id)
    accepted = press(trade_listener(api.service, "accept"), BOB, trade_id, client)

    assert picked["response_type"] == "ephemeral" and not picked["replace_original"]
    assert early["response_type"] == "ephemeral"
    assert accepted["replace_original"] is True
    assert [message["channel"] for message in client.messages] == [ALICE]
    assert client.messages[0]["blocks"][1]["elements"][0]["action_id"] == ACCEPT_ACTION_ID


def test_a_decline_button_replaces_the_offer_and_tells_the_proposer(api):
    upload(api, api.alice, [HAUNTER])
    upload(api, api.bob, [PIKACHU])
    trade_id = api.service.propose(ALICE, BOB, "alice-haunter").trade_id
    client = FakeClient()

    answer = press(trade_listener(api.service, "decline"), BOB, trade_id, client)

    assert answer["replace_original"] is True
    assert [message["channel"] for message in client.messages] == [ALICE]
