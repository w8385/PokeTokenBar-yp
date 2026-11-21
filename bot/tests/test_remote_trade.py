import json
from types import SimpleNamespace

import pytest
from slack_rules import violations
from test_commands import NOW
from test_miracle import FakeBoard, FakeClient
from test_remote_lineup import BAG, POOL, LineupAPI, box_entry, party_member
from test_remote_lineup import PARTY as ALICE_PARTY
from test_trades import ALICE, BOB, BOT, CAROL, NAMES
from test_upload_server import FakeMoves, call

from ypoke.commands import CommandHandler
from ypoke.miracle import POST_ERRORS, MiracleService, ended_card
from ypoke.remote_lineup import LINEUP
from ypoke.remote_ops import OLD_APP_REFUSAL, RemoteOps
from ypoke.remote_train import TRAIN
from ypoke.remote_views import MIRACLE_COMMAND, TRADE_COMMAND
from ypoke.store import Store
from ypoke.trade_editor import (
    BACK_ACTION,
    CANCEL_ACTION,
    GIVE_ACTION,
    MIRACLE_DOWN_ACTION,
    MIRACLE_PICK_ACTION,
    MIRACLE_POST_ACTION,
    MIRACLE_UNAVAILABLE,
    SEND_ACTION,
    TO_ACTION,
)
from ypoke.trades import HOLD_ERRORS, IN_LINEUP, PENDING_CHANGE, PROPOSE_ERRORS, TradeService
from ypoke.transport import editor_listener
from ypoke.upload_server import serve

KINDS = (LINEUP, TRAIN)
MINT = {"key": "mint", "name": "민트", "count": 1}
BOB_PARTY = [party_member("bp", 4, 30)]
BOB_POOL = [box_entry("bob-1", 7, "꼬부기"), box_entry("bob-2", 1, "이상해씨")]


def make_api(path):
    store = Store(str(path / "bot.sqlite3"))
    remote = RemoteOps(store)
    trades = TradeService(store, lambda: NOW, name_for=NAMES.get, bot_user_id=BOT, holds=remote.holds)
    board = FakeBoard()
    miracle = MiracleService(trades, board, lambda: NOW)
    sent = []
    server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), NAMES.get, trades, sent.extend,
                   miracle=miracle, remote=remote)
    return SimpleNamespace(store=store, remote=remote, trades=trades, board=board, miracle=miracle, sent=sent,
                           server=server, base=f"http://127.0.0.1:{server.server_address[1]}")


@pytest.fixture
def api(tmp_path):
    made = make_api(tmp_path)
    yield made
    made.server.shutdown()


@pytest.fixture
def app_api(tmp_path):
    (tmp_path / "app").mkdir()
    made = make_api(tmp_path / "app")
    yield made
    made.server.shutdown()


def token(api, user_id):
    return api.store.issue_token(user_id, keep_existing=True)


def upload(api, user_id=ALICE, party=ALICE_PARTY, pool=POOL, applied=0, remote=True, bag=(*BAG, MINT)):
    body = {"party": party, "trade_pool": pool}
    if remote:
        body |= {"remote_ops": 1, "applied_op_id": applied, "wallet": 500, "bag": list(bag), "shop": [],
                 "remote_ops_kinds": list(KINDS)}
    status, reply = call(f"{api.base}/v1/party", "POST", token(api, user_id), body)
    assert status == 200, reply


def both(api):
    upload(api)
    upload(api, BOB, BOB_PARTY, BOB_POOL)


def bot(api):
    return CommandHandler(api.store, LineupAPI(), bot_user_id=BOT, remote=api.remote, trades=api.trades,
                          miracle=api.miracle)


def press(api, action_id, value, user_id=ALICE, client=None, selected=False):
    answers = []
    action = {"action_id": action_id} | ({"selected_option": {"value": value}} if selected else {"value": value})
    editor_listener(bot(api).trading)(ack=lambda: None, body={"user": {"id": user_id}}, action=action,
                                      respond=lambda **answer: answers.append(answer), client=client or FakeClient())
    return answers[0]


def offer(api, give_id="b1", to=BOB, client=None):
    return press(api, SEND_ACTION, f"to:{api.trades.handle(to)}|{give_id}", client=client)


def elements(blocks):
    found = {}
    for block in blocks:
        for element in block.get("elements", []) if block["type"] == "actions" else [block.get("accessory") or {}]:
            found.setdefault(element.get("action_id"), []).append(element)
    return found


def offered_ids(blocks, action_id):
    [select] = elements(blocks)[action_id]
    return [option["value"].partition("|")[2] for option in select["options"]]


def app_offer(api, give_id, to=BOB, user_id=ALICE):
    return call(f"{api.base}/v1/trades", "POST", token(api, user_id), {"to": api.trades.handle(to), "give": give_id})


def normalized(value, ids):
    text = json.dumps(value, ensure_ascii=False)
    for index, an_id in enumerate(ids):
        text = text.replace(an_id, f"ID{index}")
    return json.loads(text)


def open_trades(api, user_id=ALICE):
    return [trade for trade in api.trades.history(user_id) if trade["status"] in ("offered", "countered")]


# /교환 offers go through TradeService.propose


def test_a_slack_offer_goes_through_propose_and_the_coworker_gets_the_app_offer_dm(api, app_api):
    both(api)
    both(app_api)
    picked = press(api, GIVE_ACTION, "to:|b1", selected=True)
    [select] = elements(picked["blocks"])[TO_ACTION]
    assert [option["text"]["text"] for option in select["options"]] == [NAMES[BOB]]
    confirm = press(api, TO_ACTION, select["options"][0]["value"], selected=True)
    [send] = elements(confirm["blocks"])[SEND_ACTION]
    client = FakeClient()
    done = press(api, SEND_ACTION, send["value"], client=client)

    [trade] = open_trades(api)
    assert (trade["give"]["id"], trade["with_name"], trade["direction"]) == ("b1", NAMES[BOB], "outgoing")
    assert done["replace_original"] and "제안했어요" in done["blocks"][0]["text"]["text"]
    assert app_offer(app_api, "b1")[0] == 200
    [app_trade] = open_trades(app_api)
    [slack_dm] = client.messages
    [app_dm] = app_api.sent
    assert slack_dm["channel"] == app_dm.user_id == BOB
    assert (normalized([slack_dm["text"], slack_dm["blocks"]], [trade["trade_id"]])
            == normalized([app_dm.text, app_dm.blocks], [app_trade["trade_id"]]))


def test_a_coworker_and_a_name_that_matches_one_pokemon_open_the_confirm(api):
    both(api)
    reply = bot(api).handle(ALICE, f"<@{BOB}> 고라파덕", TRADE_COMMAND)
    [send] = elements(reply.blocks)[SEND_ACTION]
    assert send["value"] == f"to:{api.trades.handle(BOB)}|b1"
    assert offered_ids(bot(api).handle(ALICE, "", TRADE_COMMAND).blocks, GIVE_ACTION) == ["b1", "b2", "b3", "b4"]


@pytest.mark.parametrize("case", ["not_in_box", "already_offered", "no_coworker_pool"])
def test_slack_refuses_what_the_app_path_refuses_with_the_same_words(api, case):
    both(api)
    token(api, CAROL)
    give_id, to, code = {"not_in_box": ("graduating", BOB, "unknown_individual"),
                         "already_offered": ("b1", BOB, "locked"),
                         "no_coworker_pool": ("b2", CAROL, "unknown_user")}[case]
    if case == "already_offered":
        assert app_offer(api, "b1")[0] == 200
    refused = offer(api, give_id, to)
    status, reply = app_offer(api, give_id, to)
    assert (status, reply["error"]) == (400, code)
    assert refused["text"] == reply["message"] == PROPOSE_ERRORS[code]
    assert refused["replace_original"] is False


def test_naming_a_coworker_with_nothing_to_trade_says_so_on_the_screen(api):
    upload(api)
    token(api, CAROL)
    reply = bot(api).handle(ALICE, f"<@{CAROL}>", TRADE_COMMAND)
    assert reply.blocks[0]["text"]["text"] == PROPOSE_ERRORS["unknown_user"]
    assert bot(api).handle(ALICE, f"<@{ALICE}>", TRADE_COMMAND).blocks[0]["text"]["text"] == PROPOSE_ERRORS["self"]


def test_open_trades_are_listed_and_cancelling_one_tells_the_coworker(api):
    both(api)
    offer(api)
    screen = bot(api).handle(ALICE, "", TRADE_COMMAND)
    [cancel] = elements(screen.blocks)[CANCEL_ACTION]
    assert cancel["text"]["text"] == "취소"
    assert "b1" not in offered_ids(screen.blocks, GIVE_ACTION)
    client = FakeClient()
    done = press(api, CANCEL_ACTION, cancel["value"], client=client)
    assert open_trades(api) == [] and CANCEL_ACTION not in elements(done["blocks"])
    assert [message["channel"] for message in client.messages] == [BOB]
    incoming = elements(bot(api).handle(BOB, "", TRADE_COMMAND).blocks).get(CANCEL_ACTION)
    assert incoming is None


def test_an_incoming_offer_shows_with_a_decline_button(api):
    both(api)
    offer(api)
    [decline] = elements(bot(api).handle(BOB, "", TRADE_COMMAND).blocks)[CANCEL_ACTION]
    assert decline["text"]["text"] == "거절"


def test_back_returns_to_the_picker_for_the_same_coworker(api):
    both(api)
    reply = press(api, BACK_ACTION, f"to:{api.trades.handle(BOB)}|")
    assert reply["blocks"][0]["text"]["text"].startswith(f"*교환* · {NAMES[BOB]}님에게")


# /미라클 posts through MiracleService.post


def test_a_slack_miracle_post_makes_the_app_card_and_one_offer_at_a_time_holds(api, app_api):
    upload(api)
    upload(app_api)
    confirm = press(api, MIRACLE_PICK_ACTION, "miracle|b1", selected=True)
    [post] = elements(confirm["blocks"])[MIRACLE_POST_ACTION]
    done = press(api, MIRACLE_POST_ACTION, post["value"])
    status, reply = call(f"{app_api.base}/v1/miracle", "POST", token(app_api, ALICE), {"give": "b1"})
    assert status == 200

    slack_offer, app_offer_ = api.miracle.status(ALICE), app_api.miracle.status(ALICE)
    assert normalized(api.board.posts, [slack_offer["offer_id"]]) == normalized(app_api.board.posts, [app_offer_["offer_id"]])
    assert {**slack_offer, "offer_id": None} == {**app_offer_, "offer_id": None}
    assert MIRACLE_PICK_ACTION not in elements(done["blocks"])
    again = press(api, MIRACLE_POST_ACTION, "b2")
    assert again["text"] == POST_ERRORS["already_open"]
    assert "b1" not in offered_ids(bot(api).handle(ALICE, "", TRADE_COMMAND).blocks, GIVE_ACTION)


def test_taking_a_miracle_offer_down_from_slack_ends_the_card_like_the_app(api, app_api):
    upload(api)
    upload(app_api)
    api.miracle.post(ALICE, "b1")
    app_api.miracle.post(ALICE, "b1")
    offer_id = api.miracle.status(ALICE)["offer_id"]
    [down] = elements(bot(api).handle(ALICE, "", MIRACLE_COMMAND).blocks)[MIRACLE_DOWN_ACTION]
    done = press(api, MIRACLE_DOWN_ACTION, down["value"])
    assert call(f"{app_api.base}/v1/miracle/cancel", "POST", token(app_api, ALICE), {})[0] == 200
    assert api.miracle.status(ALICE) is None
    assert api.board.edits[-1]["text"] == ended_card(api.miracle._offer(offer_id), "cancelled")[0]
    assert api.board.edits[-1]["text"] == app_api.board.edits[-1]["text"]
    assert MIRACLE_PICK_ACTION in elements(done["blocks"])


def test_miracle_without_a_battle_channel_says_it_is_unavailable(api):
    upload(api)
    handler = CommandHandler(api.store, LineupAPI(), bot_user_id=BOT, remote=api.remote, trades=api.trades)
    assert MIRACLE_UNAVAILABLE in handler.handle(ALICE, "", MIRACLE_COMMAND).blocks[0]["text"]["text"]


# Pending Slack edits hold what they change until the app syncs


def lineup(api, user_id, members):
    payload = {"members": [{"id": individual_id, "pokemon_id": pokemon_id, "name": str(pokemon_id), "moves": [],
                            "machine": [], "item": item} for individual_id, pokemon_id, item in members]}
    submitted = api.remote.submit(user_id, LINEUP, payload)
    assert submitted.refusal is None
    return submitted.op_id


def test_a_box_pokemon_a_pending_lineup_puts_in_battle_is_not_offered_anywhere(api):
    both(api)
    lineup(api, ALICE, [("p1", 25, "leftovers"), ("b1", 54, None)])
    trading = bot(api).trading
    assert "b1" not in offered_ids(bot(api).handle(ALICE, "", TRADE_COMMAND).blocks, GIVE_ACTION)
    assert "b1" not in offered_ids(bot(api).handle(ALICE, "", MIRACLE_COMMAND).blocks, MIRACLE_PICK_ACTION)
    assert "to:|b1" not in [option["value"] for option in trading.options(ALICE, "to:", "")]
    assert press(api, GIVE_ACTION, "to:|b1", selected=True)["text"] == HOLD_ERRORS[IN_LINEUP]
    assert offer(api, "b1")["text"] == HOLD_ERRORS[IN_LINEUP]
    assert press(api, MIRACLE_POST_ACTION, "b1")["text"] == HOLD_ERRORS[IN_LINEUP]
    assert app_offer(api, "b1")[1]["error"] == IN_LINEUP
    status, reply = call(f"{api.base}/v1/miracle", "POST", token(api, ALICE), {"give": "b1"})
    assert (status, reply["error"], reply["message"]) == (400, IN_LINEUP, HOLD_ERRORS[IN_LINEUP])
    assert api.miracle.status(ALICE) is None and open_trades(api) == []


def test_a_new_lineup_without_the_box_pokemon_frees_it_again(api):
    both(api)
    lineup(api, ALICE, [("p1", 25, "leftovers"), ("b1", 54, None)])
    lineup(api, ALICE, [("p1", 25, "leftovers")])
    assert offer(api, "b1")["replace_original"] is True
    assert [trade["give"]["id"] for trade in open_trades(api)] == ["b1"]


def test_a_pokemon_with_pending_training_is_offered_only_after_the_app_applies_it(api):
    both(api)
    submitted = api.remote.submit(ALICE, TRAIN, {"action": "nature", "id": "b1", "pokemon_id": 54, "name": "고라파덕",
                                                 "nature": "modest", "price": None})
    assert submitted.refusal is None
    assert "b1" not in offered_ids(bot(api).handle(ALICE, "", TRADE_COMMAND).blocks, GIVE_ACTION)
    assert offer(api, "b1")["text"] == HOLD_ERRORS[PENDING_CHANGE]
    assert press(api, MIRACLE_POST_ACTION, "b1")["text"] == HOLD_ERRORS[PENDING_CHANGE]

    trained = [{**entry, "entry": {**entry["entry"], "nature": "modest"}} if entry["id"] == "b1" else entry
               for entry in POOL]
    upload(api, pool=trained, applied=submitted.op_id)
    assert offer(api, "b1")["replace_original"] is True
    [trade] = api.trades.history(ALICE)
    assert api.trades._get(trade["trade_id"]).give["entry"]["nature"] == "modest"


def test_the_coworker_cannot_give_back_what_their_own_pending_lineup_holds(api):
    both(api)
    lineup(api, BOB, [("bp", 4, None), ("bob-1", 7, None)])
    client = FakeClient()
    offer(api, client=client)
    [dm] = client.messages
    picker = next(block for block in dm["blocks"] if block["type"] == "actions" and block.get("block_id"))
    assert [option["value"].partition("|")[2] for option in picker["elements"][0]["options"]] == ["bob-2"]
    [trade] = open_trades(api)
    assert api.trades.pick(BOB, trade["trade_id"], "bob-1").text == HOLD_ERRORS[IN_LINEUP]
    api.miracle.post(ALICE, "b2")
    picked = api.miracle.pick(BOB, api.miracle.status(ALICE)["offer_id"], "bob-1")
    assert (picked.ok, picked.text) == (False, HOLD_ERRORS[IN_LINEUP])


# A Slack-made trade is an ordinary bot record for both apps


def test_a_slack_made_trade_reaches_both_apps_and_the_ack_clears_it(api):
    both(api)
    offer(api)
    [trade] = open_trades(api)
    assert api.trades.pick(BOB, trade["trade_id"], "bob-2").ok
    assert api.trades.accept(BOB, trade["trade_id"]).ok
    assert api.trades.accept(ALICE, trade["trade_id"]).ok
    for user_id, gave, got in ((ALICE, "b1", "bob-2"), (BOB, "bob-2", "b1")):
        status, reply = call(f"{api.base}/v1/trades", token=token(api, user_id))
        [delivery] = reply["trades"]["deliveries"]
        assert (delivery["give_id"], delivery["receive"]["id"]) == (gave, got)
        assert call(f"{api.base}/v1/trades/ack", "POST", token(api, user_id), {"trade_ids": [delivery["trade_id"]]})[0] == 200
        assert call(f"{api.base}/v1/trades", token=token(api, user_id))[1]["trades"]["deliveries"] == []


def test_an_app_without_remote_ops_can_still_offer_from_slack(api):
    upload(api, remote=False)
    upload(api, BOB, BOB_PARTY, BOB_POOL, remote=False)
    screen = bot(api).handle(ALICE, "", TRADE_COMMAND)
    assert OLD_APP_REFUSAL not in screen.text
    assert offer(api, "b1")["replace_original"] is True
    assert [trade["give"]["id"] for trade in open_trades(api)] == ["b1"]


def test_every_trade_and_miracle_screen_follows_slacks_block_rules(api):
    both(api)
    editor = bot(api).trading
    to = f"to:{api.trades.handle(BOB)}"
    screens = [editor.handle(ALICE, TRADE_COMMAND, ""), editor.handle(ALICE, TRADE_COMMAND, f"<@{BOB}>"),
               editor.handle(ALICE, TRADE_COMMAND, f"<@{BOB}> 고라파덕"), editor.handle(ALICE, MIRACLE_COMMAND, ""),
               editor.handle(BOB, TRADE_COMMAND, "")]
    blocks = [screen.blocks for screen in screens]
    blocks.append(press(api, GIVE_ACTION, f"{to}|b1", selected=True)["blocks"])
    assert [violations(block_list) for block_list in blocks] == [[]] * len(blocks)
