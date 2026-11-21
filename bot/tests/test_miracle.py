from types import SimpleNamespace

import pytest

from test_trades import ALICE, BOB, CAROL, EEVEE, HAUNTER, NAMES, PIKACHU, SQUIRTLE, Clock, individual
from test_upload_server import PIKACHU as BATTLER
from test_upload_server import FakeMoves, call
from fixed_clock import fixed_now
from ypoke.miracle import (
    ACCEPT_ACTION_ID,
    CANCEL_ACTION_ID,
    ENDED_TEXT,
    NOT_TRADABLE,
    OWN_OFFER,
    PICK_ACTION_ID,
    POSTER_ONLY,
    MiracleService,
)
from ypoke.store import Store
from ypoke.trades import TradeService, option_labels
from ypoke.transport import miracle_listener
from ypoke.upload_server import serve

CHARMANDER = individual("carol-charmander", 4, "파이리", 30)


class FakeBoard:
    def __init__(self, fail=False):
        self.fail = fail
        self.posts = []
        self.edits = []

    def post(self, text, blocks):
        if self.fail:
            return None
        self.posts.append({"text": text, "blocks": blocks})
        return f"1700000000.{len(self.posts):06d}"

    def update(self, ts, text, blocks):
        self.edits.append({"ts": ts, "text": text, "blocks": blocks})

    @property
    def card(self):
        return self.edits[-1] if self.edits else self.posts[-1]


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def board():
    return FakeBoard()


@pytest.fixture
def trades(tmp_path, clock):
    service = TradeService(Store(str(tmp_path / "bot.sqlite3"), fixed_now), now=clock, name_for=NAMES.get)
    service.save_pool(ALICE, [HAUNTER, EEVEE])
    service.save_pool(BOB, [PIKACHU, SQUIRTLE])
    service.save_pool(CAROL, [CHARMANDER])
    return service


@pytest.fixture
def miracle(trades, board, clock):
    return MiracleService(trades, board, now=clock)


def offer_id(miracle, user_id=ALICE):
    return miracle.status(user_id)["offer_id"]


def buttons(card):
    actions = [block for block in card["blocks"] if block["type"] == "actions"]
    return [element["action_id"] for block in actions for element in block["elements"]]


def completed_trades(trades):
    with trades.connect() as connection:
        return connection.execute("SELECT proposer_id, target_id, give_id, back_id FROM trades "
                                  "WHERE status = 'completed'").fetchall()


def test_posting_puts_a_card_with_the_sprite_and_both_buttons_in_the_channel(miracle, board):
    result = miracle.post(ALICE, HAUNTER["id"])

    assert result.error is None
    assert result.offer["give_id"] == HAUNTER["id"]
    (card,) = board.posts
    assert card["text"] == f"<@{ALICE}>님이 미라클 교환에 고우스트 Lv.100을(를) 올렸어요"
    assert card["blocks"][0]["accessory"]["image_url"].endswith("/93.png")
    assert buttons(card) == [ACCEPT_ACTION_ID, CANCEL_ACTION_ID]
    assert miracle.status(ALICE)["offer_id"] == result.offer["offer_id"]


def test_accept_then_pick_completes_at_once_and_delivers_both_sides(miracle, trades, board):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)

    picker = miracle.open_picker(BOB, offer)
    select = picker.blocks[1]["elements"][0]
    assert select["action_id"] == PICK_ACTION_ID
    assert [option["value"] for option in select["options"]] == [f"{offer}|bob-pikachu", f"{offer}|bob-squirtle"]

    done = miracle.pick(BOB, offer, PIKACHU["id"])

    assert done.ok and done.final
    assert [message.user_id for message in done.direct_messages] == [ALICE, BOB]
    assert completed_trades(trades) == [(ALICE, BOB, HAUNTER["id"], PIKACHU["id"])]
    assert [delivery["receive"]["id"] for delivery in trades.deliveries(ALICE)] == [PIKACHU["id"]]
    assert [delivery["receive"]["id"] for delivery in trades.deliveries(BOB)] == [HAUNTER["id"]]
    assert board.card["text"] == f"미라클 교환 완료: <@{ALICE}>님의 고우스트 Lv.100 ↔ <@{BOB}>님의 피카츄 Lv.80"
    assert buttons(board.card) == []
    assert miracle.status(ALICE) is None


def test_two_acceptors_racing_make_one_trade(miracle, trades, monkeypatch):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)
    stale = miracle._offer(offer)
    monkeypatch.setattr(miracle, "_offer", lambda _offer_id: stale)

    first = miracle.pick(BOB, offer, PIKACHU["id"])
    second = miracle.pick(CAROL, offer, CHARMANDER["id"])

    assert first.ok
    assert not second.ok and second.text == ENDED_TEXT["completed"]
    assert completed_trades(trades) == [(ALICE, BOB, HAUNTER["id"], PIKACHU["id"])]
    assert trades.deliveries(CAROL) == []


def test_a_later_presser_hears_it_was_already_traded(miracle):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)
    miracle.pick(BOB, offer, PIKACHU["id"])

    assert miracle.open_picker(CAROL, offer).text == "이미 교환됐어요."
    assert miracle.pick(CAROL, offer, CHARMANDER["id"]).text == "이미 교환됐어요."


def test_the_poster_cannot_accept_their_own_offer(miracle, trades):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)

    assert miracle.open_picker(ALICE, offer).text == OWN_OFFER
    assert miracle.pick(ALICE, offer, EEVEE["id"]).text == OWN_OFFER
    assert completed_trades(trades) == []


def test_only_the_poster_can_take_the_offer_down(miracle, board):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)

    assert miracle.take_down(BOB, offer).text == POSTER_ONLY
    assert miracle.status(ALICE) is not None
    assert board.edits == []

    assert miracle.take_down(ALICE, offer).ok
    assert miracle.status(ALICE) is None
    assert board.card["text"] == f"<@{ALICE}>님이 미라클 교환에서 고우스트 Lv.100을(를) 내렸어요."
    assert buttons(board.card) == []
    assert miracle.pick(BOB, offer, PIKACHU["id"]).text == ENDED_TEXT["cancelled"]


def test_the_app_takes_down_its_open_offer(miracle, board):
    assert not miracle.cancel_mine(ALICE)
    miracle.post(ALICE, HAUNTER["id"])

    assert miracle.cancel_mine(ALICE)
    assert miracle.status(ALICE) is None
    assert "내렸어요" in board.card["text"]


def test_an_offer_expires_after_a_day_and_its_card_says_so(miracle, board, clock):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)
    clock.advance(hours=23)
    miracle.sweep()
    assert board.edits == []

    clock.advance(hours=2)
    miracle.sweep()

    assert board.card["text"] == f"<@{ALICE}>님의 미라클 교환 고우스트 Lv.100은(는) 24시간이 지나 끝났어요."
    assert miracle.pick(BOB, offer, PIKACHU["id"]).text == ENDED_TEXT["expired"]
    assert miracle.post(ALICE, HAUNTER["id"]).error is None


def test_an_offered_pokemon_that_leaves_the_pool_closes_the_offer(miracle, trades, board):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)

    trades.save_pool(ALICE, [EEVEE])
    miracle.pool_changed(ALICE)

    assert "교환할 수 없어서 미라클 교환이 닫혔어요" in board.card["text"]
    assert buttons(board.card) == []
    assert miracle.pick(BOB, offer, PIKACHU["id"]).text == ENDED_TEXT["closed"]


def test_a_pick_on_an_offer_whose_pokemon_vanished_before_the_upload_is_closed(miracle, trades, board):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)
    trades.save_pool(ALICE, [EEVEE])

    reply = miracle.pick(BOB, offer, PIKACHU["id"])

    assert not reply.ok and reply.text == ENDED_TEXT["closed"]
    assert completed_trades(trades) == []
    assert "닫혔어요" in board.card["text"]


def test_an_untradable_pick_is_refused_privately_and_the_offer_stays_open(miracle, trades, board):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)
    miracle.open_picker(BOB, offer)
    trades.save_pool(BOB, [SQUIRTLE])

    reply = miracle.pick(BOB, offer, PIKACHU["id"])

    assert not reply.ok and not reply.final and reply.text == NOT_TRADABLE
    assert miracle.status(ALICE) is not None
    assert board.edits == []
    assert miracle.pick(BOB, offer, SQUIRTLE["id"]).ok


def test_a_pick_locked_in_another_trade_is_refused(miracle, trades):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)
    trades.propose(BOB, CAROL, PIKACHU["id"])

    assert [option["value"] for option in miracle.open_picker(BOB, offer).blocks[1]["elements"][0]["options"]] == [
        f"{offer}|bob-squirtle"]
    assert miracle.pick(BOB, offer, PIKACHU["id"]).text == NOT_TRADABLE


def test_the_offered_pokemon_is_locked_from_other_trades_and_a_second_offer(miracle, trades):
    miracle.post(ALICE, HAUNTER["id"])

    assert trades.propose(ALICE, BOB, HAUNTER["id"]).error == "locked"
    assert trades.locked_ids(ALICE) == [HAUNTER["id"]]
    assert miracle.post(ALICE, EEVEE["id"]).error == "already_open"
    assert miracle.post(BOB, "nobody").error == "unknown_individual"


def test_a_pokemon_already_in_a_direct_trade_cannot_be_posted(miracle, trades):
    trades.propose(ALICE, BOB, HAUNTER["id"])

    assert miracle.post(ALICE, HAUNTER["id"]).error == "locked"


def test_a_card_that_cannot_be_posted_leaves_no_offer(trades, clock):
    miracle = MiracleService(trades, FakeBoard(fail=True), now=clock)

    assert miracle.post(ALICE, HAUNTER["id"]).error == "post_failed"
    assert miracle.status(ALICE) is None
    assert trades.locked_ids(ALICE) == []


def test_someone_with_nothing_to_give_is_told_privately(miracle, trades):
    miracle.post(ALICE, HAUNTER["id"])

    reply = miracle.open_picker("U0000000D", offer_id(miracle))

    assert not reply.ok and reply.blocks is None


def gendered(individual_id, name, gender=None, nature=None, shiny=False, level=50):
    entry = individual(individual_id, 133, name, level, shiny)
    if gender:
        entry["entry"]["profile"] = {"gender": gender}
    if nature:
        entry["entry"]["nature"] = nature
    return entry


def test_select_labels_tell_same_species_individuals_apart():
    entries = [
        gendered("a", "이브이", "male", "adamant"),
        gendered("b", "이브이", "female", "adamant"),
        gendered("c", "이브이", "male", "timid"),
        gendered("d", "이브이", "male", "adamant"),
        gendered("e", "이브이", shiny=True),
    ]

    labels = option_labels(entries)

    assert labels == ["이브이♂ Lv.50 고집", "이브이♀ Lv.50 고집", "이브이♂ Lv.50 겁쟁이", "이브이♂ Lv.50 고집 #2",
                      "이브이 Lv.50 ✨"]
    assert len(set(labels)) == len(labels)


def test_long_duplicate_labels_keep_their_number_inside_slacks_limit():
    long_name = "가" * 40
    labels = option_labels([gendered("a", long_name, nature="adamant"), gendered("b", long_name, nature="adamant")])

    assert len(set(labels)) == 2
    assert all(len(label) <= 75 for label in labels)


def test_the_direct_trade_picker_uses_the_same_distinct_labels(trades):
    trades.save_pool(BOB, [gendered("bob-1", "이브이", "male", "jolly"), gendered("bob-2", "이브이", "male", "jolly")])

    (message,) = trades.propose(ALICE, BOB, HAUNTER["id"]).direct_messages

    options = message.blocks[1]["elements"][0]["options"]
    assert [option["text"]["text"] for option in options] == ["이브이♂ Lv.50 명랑", "이브이♂ Lv.50 명랑 #2"]


# MARK: HTTP and Slack


@pytest.fixture
def api(tmp_path, board):
    store = Store(str(tmp_path / "bot.sqlite3"), fixed_now)
    trades = TradeService(store, fixed_now, name_for=NAMES.get)
    miracle = MiracleService(trades, board, fixed_now)
    server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), NAMES.get, trades,
                   miracle=miracle, now=fixed_now)
    base = f"http://127.0.0.1:{server.server_address[1]}"
    yield SimpleNamespace(base=base, trades=trades, miracle=miracle, board=board,
                          alice=store.issue_token(ALICE), bob=store.issue_token(BOB))
    server.shutdown()


def upload(api, token, pool):
    return call(f"{api.base}/v1/party", "POST", token, {"party": [BATTLER], "trade_pool": pool})


def test_the_app_posts_reads_and_takes_down_its_offer(api):
    upload(api, api.alice, [HAUNTER, EEVEE])

    assert call(f"{api.base}/v1/miracle", token=api.alice) == (200, {"ok": True, "offer": None})
    status, body = call(f"{api.base}/v1/miracle", "POST", api.alice, {"give": HAUNTER["id"]})
    assert status == 200 and body["offer"]["give_id"] == HAUNTER["id"]
    assert call(f"{api.base}/v1/miracle", token=api.alice)[1]["offer"]["give_id"] == HAUNTER["id"]
    assert upload(api, api.alice, [HAUNTER, EEVEE])[1]["trades"]["locked_ids"] == [HAUNTER["id"]]

    status, body = call(f"{api.base}/v1/miracle", "POST", api.alice, {"give": EEVEE["id"]})
    assert status == 400 and body["error"] == "already_open" and body["message"]

    assert call(f"{api.base}/v1/miracle/cancel", "POST", api.alice, {}) == (200, {"ok": True})
    assert call(f"{api.base}/v1/miracle/cancel", "POST", api.alice, {})[0] == 400
    assert call(f"{api.base}/v1/miracle", token=api.alice)[1]["offer"] is None


def test_an_upload_without_the_offered_pokemon_closes_the_card(api):
    upload(api, api.alice, [HAUNTER, EEVEE])
    call(f"{api.base}/v1/miracle", "POST", api.alice, {"give": HAUNTER["id"]})

    upload(api, api.alice, [EEVEE])

    assert "닫혔어요" in api.board.card["text"]
    assert call(f"{api.base}/v1/miracle", token=api.alice)[1]["offer"] is None


@pytest.mark.parametrize("miracle", [None, MiracleService(SimpleNamespace(), None, fixed_now)])
def test_without_a_battle_channel_the_routes_answer_unavailable(tmp_path, miracle):
    store = Store(str(tmp_path / "bot.sqlite3"), fixed_now)
    trades = TradeService(store, fixed_now)
    server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), trades=trades, miracle=miracle, now=fixed_now)
    base = f"http://127.0.0.1:{server.server_address[1]}"
    token = store.issue_token(ALICE)
    try:
        assert call(f"{base}/v1/miracle", token=token) == (404, {"ok": False, "error": "unavailable"})
        assert call(f"{base}/v1/miracle", "POST", token, {"give": "x"})[1]["error"] == "unavailable"
        assert call(f"{base}/v1/miracle/cancel", "POST", token, {})[1]["error"] == "unavailable"
    finally:
        server.shutdown()


class FakeClient:
    def __init__(self):
        self.messages = []

    def chat_postMessage(self, **message):
        self.messages.append(message)


def test_slack_buttons_answer_privately_and_only_the_finished_pick_replaces_the_picker(miracle):
    miracle.post(ALICE, HAUNTER["id"])
    offer = offer_id(miracle)
    client = FakeClient()

    own = press(miracle_listener(miracle, "accept"), ALICE, offer)
    picker = press(miracle_listener(miracle, "accept"), BOB, offer)
    denied = press(miracle_listener(miracle, "cancel"), BOB, offer)
    done = press(miracle_listener(miracle, "pick"), BOB, f"{offer}|{PIKACHU['id']}", client, selected=True)
    late = press(miracle_listener(miracle, "accept"), CAROL, offer)

    assert own["response_type"] == "ephemeral" and own["text"] == OWN_OFFER
    assert picker["response_type"] == "ephemeral" and not picker["replace_original"]
    assert picker["blocks"][1]["elements"][0]["action_id"] == PICK_ACTION_ID
    assert denied["text"] == POSTER_ONLY and not denied["replace_original"]
    assert done["replace_original"] is True
    assert [message["channel"] for message in client.messages] == [ALICE, BOB]
    assert late["text"] == "이미 교환됐어요." and late["response_type"] == "ephemeral"


def press(listener, user_id, value, client=None, selected=False):
    answers = []
    action = {"selected_option": {"value": value}} if selected else {"value": value}
    listener(lambda: None, {"user": {"id": user_id}}, action, lambda **answer: answers.append(answer),
             client or FakeClient())
    return answers[0]
