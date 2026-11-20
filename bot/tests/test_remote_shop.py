import pytest
from test_remote_lineup import BAG, PARTY, POOL, bot, select_values
from test_remote_ops import text_of
from test_upload_server import FakeMoves, call

from ypoke.commands import HELP_TEXT
from ypoke.lineup_editor import ITEM_ACTION
from ypoke.remote_buy import BUY, REASONS
from ypoke.remote_lineup import LINEUP
from ypoke.remote_ops import OLD_APP_REFUSAL, RemoteOps
from ypoke.remote_views import BAG_COMMAND, PARTY_COMMAND, SHOP_COMMAND
from ypoke.shop_editor import BACK_ACTION, BUY_ACTION, PICK_ACTION, SHORT
from ypoke.store import Store
from ypoke.trades import PICKER_LIMIT, TradeService
from ypoke.transport import editor_listener, editor_options_listener
from ypoke.upload_server import serve

CANDY = {"key": "rareCandy", "name": "이상한사탕", "price": 100, "category": "growth", "category_name": "육성",
         "single": False}
BAND = {"key": "choiceBand", "name": "구애머리띠", "price": 200, "category": "heldItem", "category_name": "지닌 도구",
        "single": False, "equip": True, "held_item": "choice-band"}
TM = {"key": "tm:87", "name": "기술머신 번개", "price": 300, "category": "machine", "category_name": "기술머신",
      "single": True}
SHOP = [CANDY, BAND, TM]


@pytest.fixture
def server(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    http_server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), trades=TradeService(store))
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}"
    http_server.shutdown()


def post(server, user_id="UA", wallet=500, shop=SHOP, kinds=(BUY, LINEUP), applied=0, bag=BAG):
    store, base = server
    body = {"party": PARTY, "trade_pool": POOL, "remote_ops": 1, "applied_op_id": applied, "wallet": wallet,
            "bag": bag, "shop": shop, "remote_ops_kinds": list(kinds)}
    status, reply = call(f"{base}/v1/party", "POST", store.issue_token(user_id, keep_existing=True), body)
    assert status == 200, reply


def press(store, action_id, value):
    return bot(store).shop.act("UA", action_id, value, [])


def buy(store, line, count=1):
    reply = press(store, BUY_ACTION, f"{count}|{line['price']}|{line['key']}")
    assert reply.replace, reply.screen.text
    return reply


def buttons(blocks):
    return [element["value"] for block in blocks if block["type"] == "actions" for element in block["elements"]]


# The /상점 screens


def test_the_shop_has_a_menu_per_category_with_the_apps_names_and_prices_and_the_balance(server):
    store, _ = server
    post(server)
    blocks = bot(store).handle("UA", "", SHOP_COMMAND).blocks
    assert "쓸 수 있는 토큰 500" in blocks[0]["text"]["text"]
    menus = {block["block_id"]: block for block in blocks if "accessory" in block}
    assert list(menus) == ["growth", "heldItem", "machine"]
    assert menus["heldItem"]["text"]["text"] == "*지닌 도구* 1개"
    assert menus["heldItem"]["accessory"]["action_id"] == PICK_ACTION
    assert menus["heldItem"]["accessory"]["options"] == [
        {"text": {"type": "plain_text", "text": "구애머리띠 · 200"}, "value": "choiceBand"}]


def test_picking_an_item_offers_the_quantities_the_balance_covers(server):
    store, _ = server
    post(server)
    reply = press(store, PICK_ACTION, "rareCandy")
    assert reply.replace
    assert buttons(reply.screen.blocks) == ["1|100|rareCandy", "5|100|rareCandy", "back"]
    assert "가방에 3개 있어요" in reply.screen.blocks[0]["text"]["text"]
    assert buttons(press(store, PICK_ACTION, "tm:87").screen.blocks) == ["1|300|tm:87", "back"]


def test_an_item_the_balance_cannot_cover_has_no_buy_button(server):
    store, _ = server
    post(server, wallet=50)
    reply = press(store, PICK_ACTION, "rareCandy")
    assert buttons(reply.screen.blocks) == ["back"] and SHORT in reply.screen.text + str(reply.screen.blocks)


def test_a_query_naming_one_item_opens_it(server):
    store, _ = server
    post(server)
    blocks = bot(store).handle("UA", "사탕", SHOP_COMMAND).blocks
    assert buttons(blocks)[0] == "1|100|rareCandy"
    assert "에 맞는 물건이 없어요" in bot(store).handle("UA", "없는물건", SHOP_COMMAND).blocks[0]["text"]["text"]


def test_a_category_past_slacks_100_options_is_a_typed_menu(server):
    store, _ = server
    machines = [{**TM, "key": f"tm:{move_id}", "name": f"기술머신 {move_id}"} for move_id in range(1, 250)]
    post(server, shop=[CANDY, BAND, *machines])
    blocks = bot(store).handle("UA", "", SHOP_COMMAND).blocks
    menu = next(block for block in blocks if block.get("block_id") == "machine")["accessory"]
    assert menu["type"] == "external_select" and len(blocks) <= 50
    assert all(len(block["accessory"].get("options", [])) <= PICKER_LIMIT for block in blocks if "accessory" in block)
    answered = []
    editor_options_listener(bot(store).shop)(ack=lambda **reply: answered.append(reply), body={"user": {"id": "UA"}},
                                             payload={"block_id": "machine", "value": "기술머신 12"})
    assert [option["value"] for option in answered[0]["options"]] == [f"tm:{n}" for n in range(1, 250) if "12" in str(n)]


# Buying


def test_a_buy_through_the_action_listener_queues_one_op_and_replaces_the_screen(server):
    store, _ = server
    post(server)
    sent = []
    editor_listener(bot(store).shop)(ack=lambda: None, body={"user": {"id": "UA"}},
                                     action={"action_id": BUY_ACTION, "value": "5|100|rareCandy"},
                                     respond=lambda **message: sent.append(message))
    assert [(message["replace_original"], message["response_type"]) for message in sent] == [(True, "ephemeral")]
    assert "✅ 이상한사탕 ×5" in sent[0]["text"] and "남은 토큰 0" in sent[0]["text"]
    [op] = RemoteOps(store).pending("UA")
    assert (op.kind, op.payload) == (BUY, {"key": "rareCandy", "name": "이상한사탕", "count": 5, "price": 100})


def test_a_buy_past_the_balance_less_pending_buys_is_refused_with_the_balance(server):
    store, _ = server
    post(server)
    buy(store, CANDY, 3)
    reply = press(store, BUY_ACTION, "3|100|rareCandy")
    assert not reply.replace
    assert reply.screen.text == f"{SHORT} 쓸 수 있는 토큰 200, 필요한 토큰 300"
    assert len(RemoteOps(store).pending("UA")) == 1


def test_a_price_changed_since_the_screen_is_refused(server):
    store, _ = server
    post(server)
    reply = press(store, BUY_ACTION, "1|90|rareCandy")
    assert not reply.replace and REASONS["price_changed"] in reply.screen.text
    assert RemoteOps(store).pending("UA") == []


def test_an_item_bought_once_leaves_the_shop_and_lands_in_the_bag(server):
    store, _ = server
    post(server)
    reply = buy(store, TM)
    assert "✅ 기술머신 번개 ×1" in reply.screen.text
    assert "machine" not in {block.get("block_id") for block in reply.screen.blocks}
    assert press(store, BUY_ACTION, "1|300|tm:87").screen.text.startswith("그새 상점이 바뀌었어요")
    assert {line["key"]: line["count"] for line in RemoteOps(store).view("UA").bag}["tm:87"] == 1


def test_a_bought_item_shows_at_once_in_the_bag_the_shop_and_the_held_item_picker(server):
    store, _ = server
    post(server)
    buy(store, BAND)
    bag = text_of(bot(store).handle("UA", "", BAG_COMMAND))
    assert "쓸 수 있는 토큰: 300" in bag and "• 구애머리띠 ×1" in bag
    assert "*대기 중인 슬랙 작업*\n1. 상점에서 사기: 구애머리띠 ×1 (200토큰)" in bag
    assert "쓸 수 있는 토큰 300" in bot(store).handle("UA", "", SHOP_COMMAND).blocks[0]["text"]["text"]
    party = bot(store).editor.handle("UA", PARTY_COMMAND, "").blocks
    assert "p2|choiceBand" in select_values(party, "p2", ITEM_ACTION)


def test_a_lineup_equipping_a_pending_buy_applies_after_it(server):
    store, _ = server
    post(server)
    buy(store, BAND)
    reply = bot(store).editor.act("UA", ITEM_ACTION, "p2|choiceBand", [])
    assert reply.replace, reply.screen.text
    view = RemoteOps(store).view("UA")
    assert [op.kind for op in view.pending] == [BUY, LINEUP]
    assert view.party[1]["item_key"] == "choiceBand" and view.party[1]["held_item"] == "choice-band"
    assert "choiceBand" not in {line["key"] for line in view.bag}


# The app settles


def test_an_upload_that_has_not_applied_the_buy_keeps_it_and_the_ack_clears_it(server):
    store, base = server
    post(server)
    buy(store, CANDY, 2)
    post(server)
    assert wallet(store) == 300
    [op] = RemoteOps(store).pending("UA")
    post(server, wallet=320, applied=op.id, bag=[{**BAG[2], "count": 5}])
    assert wallet(store) == 320
    status, _ = call(f"{base}/v1/ops/ack", "POST", store.issue_token("UA", keep_existing=True),
                     {"applied": [op.id], "cancelled": []})
    assert status == 200 and RemoteOps(store).pending("UA") == []
    assert wallet(store) == 320


def wallet(store):
    return RemoteOps(store).view("UA").wallet


def test_the_result_dm_words_a_cancelled_buy_with_its_reason(server):
    store, _ = server
    post(server)
    buy(store, CANDY)
    [op] = RemoteOps(store).pending("UA")
    message = RemoteOps(store).ack("UA", [], [(op.id, "no_tokens")])
    assert f"❌ 상점에서 사기: 이상한사탕 ×1 (100토큰): {REASONS['no_tokens']}" in message.text


# Old apps


def test_an_app_that_does_not_apply_buy_ops_gets_a_read_only_shop_and_a_refusal(server):
    store, _ = server
    post(server, kinds=(LINEUP,))
    reply = bot(store).handle("UA", "", SHOP_COMMAND)
    assert text_of(reply).split("\n")[1] == OLD_APP_REFUSAL
    assert not [block for block in reply.blocks if "accessory" in block or block["type"] == "actions"]
    assert "• 구애머리띠 · 200토큰" in text_of(reply)
    assert press(store, BUY_ACTION, "1|100|rareCandy").screen.text == OLD_APP_REFUSAL
    assert press(store, BACK_ACTION, "back").screen.text == OLD_APP_REFUSAL
    assert RemoteOps(store).pending("UA") == []


def test_the_help_explains_the_shop_and_the_spendable_balance():
    assert f"`{SHOP_COMMAND} [이름]`" in HELP_TEXT and "대기 중인 구매·트레이닝을 뺀" in HELP_TEXT
