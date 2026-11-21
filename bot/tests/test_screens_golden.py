"""Every Slack message the bot sends, pinned as the calls the listeners make from synthetic fixtures, and checked
against Slack's block rules. `YPOKE_UPDATE_GOLDEN=1 uv run pytest tests/test_screens_golden.py` rewrites them."""

import itertools
import json
import os
import secrets
import uuid
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest
from fixed_clock import fixed_now
from slack_rules import violations
from test_remote_lineup import BAG as LINEUP_BAG
from test_remote_lineup import PARTY as LINEUP_PARTY
from test_remote_lineup import POOL as LINEUP_POOL
from test_remote_lineup import box_entry, party_member
from test_remote_shop import SHOP
from test_remote_shop import TM as SHOP_TM
from test_remote_training import BAG as TRAINING_BAG
from test_remote_training import (
    BOLDORE,
    CORD,
    ONIX,
    PIKACHU,
    PSYDUCK,
    THUNDURUS,
    TrainingAPI,
)
from test_remote_training import SHOP as TRAINING_SHOP
from test_trades import ALICE, BOB, BOT, CAROL, NAMES
from test_upload_server import FakeMoves, call

import ypoke.transport
from ypoke.battle_render import image_block
from ypoke.commands import CommandHandler, Delivery, Reply, Where
from ypoke.dex import normalize_dex, sprite_url
from ypoke.lineup_editor import (
    BOX_ADD_ACTION,
    ITEM_ACTION,
    MOVES_ACTION,
    ORDER_ACTION,
    SET_MOVES_ACTION,
    SWAP_ACTION,
    TRAINING_OPEN_ACTION,
)
from ypoke.miracle import MiracleService, ended_card
from ypoke.narration import Card, Matchup, Portrait
from ypoke.remote_buy import BUY
from ypoke.remote_lineup import LINEUP
from ypoke.remote_ops import RemoteOps
from ypoke.remote_train import TRAIN
from ypoke.shop_editor import BACK_ACTION as SHOP_BACK_ACTION
from ypoke.shop_editor import BUY_ACTION
from ypoke.shop_editor import PICK_ACTION as SHOP_PICK_ACTION
from ypoke.store import Store
from ypoke.trade_editor import (
    BACK_ACTION as OFFER_BACK_ACTION,
)
from ypoke.trade_editor import (
    CANCEL_ACTION,
    GIVE_ACTION,
    MIRACLE_BACK_ACTION,
    MIRACLE_DOWN_ACTION,
    MIRACLE_PICK_ACTION,
    MIRACLE_POST_ACTION,
    SEND_ACTION,
    TO_ACTION,
)
from ypoke.trades import TradeService
from ypoke.training_editor import (
    BACK_ACTION as TRAINING_BACK_ACTION,
)
from ypoke.training_editor import (
    DEFAULT_MOVES_ACTION as TRAINING_DEFAULT_MOVES_ACTION,
)
from ypoke.training_editor import (
    MOVES_ACTION as TRAINING_MOVES_ACTION,
)
from ypoke.training_editor import (
    NATURE_ACTION,
)
from ypoke.training_editor import (
    PICK_ACTION as TRAINING_PICK_ACTION,
)
from ypoke.training_editor import (
    SET_MOVES_ACTION as TRAINING_SET_MOVES_ACTION,
)
from ypoke.transport import (
    SlackBoard,
    deliver,
    editor_listener,
    editor_options_listener,
    mention_listener,
    miracle_listener,
    options_listener,
    post_direct_messages,
    post_result,
    rematch_listener,
    slash_listener,
    trade_listener,
)
from ypoke.upload_server import serve

GOLDEN = Path(__file__).parent / "golden" / "screens"
UPDATE = os.environ.get("YPOKE_UPDATE_GOLDEN") == "1"
CHANNEL = "CBATTLE"
HOME = "CHOME"
RESPONSE_URL = "https://hooks.example/respond"
KINDS = (LINEUP, BUY, TRAIN)
PIKA = Portrait(25, False, "피카츄")
SQUIRT = Portrait(7, False, "꼬부기")
RAICHU = Portrait(26, True, "라이츄")
CARD = Card(
    columns=(f"*<@{ALICE}>*\n피카츄 Lv.50\n라이츄 Lv.50", f"*<@{BOB}>*\n꼬부기 Lv.50"),
    title=f"<@{ALICE}> 승리",
    detail="3턴 만에 끝났어요",
    highlights=("결정타: 라이츄의 10만볼트",),
    log=("*1턴*\n피카츄의 10만볼트!\n꼬부기의 물대포!", "*2턴*\n피카츄는 쓰러졌다!", "*3턴*\n라이츄의 10만볼트!"),
    sprite=(sprite_url(26, True), "라이츄"),
    log_matchups=(Matchup(PIKA, SQUIRT), None, Matchup(RAICHU, SQUIRT)),
    rules=(f"<@{BOB}>: 같은 종은 한 마리만 나가요",),
)
DEX = {"owned": 120, "shiny": 3, "regions": {"kanto": 151, "johto": 40, "paldea": 0},
       "representative": {"pokemon_id": 25, "shiny": True}}
MANY_BENCH = [box_entry(f"m{species}", species, f"몬{species}") for species in range(300, 410)]
MANY_MACHINES = [{**SHOP_TM, "key": f"tm:{move_id}", "name": f"기술머신 {move_id}"} for move_id in range(1, 121)]


def pin(name, calls):
    """Compare the recorded calls with the golden `name`; every message in them must follow Slack's block rules."""
    for _, message in calls:
        assert violations(message.get("blocks") or []) == [], name
        options = message.get("options")
        if options:
            menu = {"type": "static_select", "action_id": "menu", "options": options}
            assert violations([{"type": "actions", "elements": [menu]}]) == [], name
    text = json.dumps(calls, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    path = GOLDEN / f"{name}.json"
    if UPDATE:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    assert path.read_text() == text, f"{name} changed"


class Slack:
    """A WebClient, a response URL and a webhook that record every call in order. A client call that `refuse`
    returns True for raises, the way the SDK raises on Slack's refusal."""

    def __init__(self, refuse=lambda method, message: False, status=200):
        self.calls = []
        self.refuse = refuse
        self.status = status

    def chat_postMessage(self, **message):
        self._record("chat.postMessage", message)
        return {"ok": True, "ts": f"9.{len(self.calls)}"}

    def chat_postEphemeral(self, **message):
        self._record("chat.postEphemeral", message)
        return {"ok": True}

    def chat_update(self, **message):
        self._record("chat.update", message)
        return {"ok": True}

    def respond(self, **message):
        self.calls.append(["respond", message])
        return SimpleNamespace(status_code=self.status, body="ok" if self.status == 200 else "invalid_blocks")

    def ack(self, **message):
        self.calls.append(["ack", message])

    def _record(self, method, message):
        if self.refuse(method, message):
            self.calls.append([f"{method} refused", message])
            raise RuntimeError("refused")
        self.calls.append([method, message])


class Pictures:
    """Draws every matchup as an uploaded picture."""

    def __init__(self):
        self.forgotten = []

    def image_blocks(self, client, matchups):
        return {matchup: image_block(f"F{index}", matchup) for index, matchup in enumerate(matchups)}

    def settle(self):
        pass

    def forget(self, drawn):
        self.forgotten.extend(drawn)


class Scripted:
    """A command handler that answers every command, mention and rematch with `reply`, or raises."""

    bot_user_id = BOT

    def __init__(self, reply=None):
        self.reply = reply

    def handle(self, user_id, text, command, where, echo=False):
        return self._answer()

    def handle_mention(self, user_id, text, where):
        return self._answer()

    def rematch(self, user_id, value, where, card_ts):
        return self._answer()

    def _answer(self):
        if self.reply is None:
            raise RuntimeError("broken")
        return self.reply


@pytest.fixture(autouse=True)
def fixed_ids(monkeypatch):
    ids = itertools.count(1)
    tokens = itertools.count(1)
    monkeypatch.setattr(uuid, "uuid4", lambda: uuid.UUID(int=next(ids) * (2**64 + 1)))
    monkeypatch.setattr(secrets, "token_urlsafe", lambda size=None: f"token-{next(tokens)}")
    monkeypatch.setattr(secrets, "randbits", lambda bits: 7)


@pytest.fixture
def world(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"), fixed_now)
    remote = RemoteOps(store, fixed_now)
    trades = TradeService(store, fixed_now, name_for=NAMES.get, bot_user_id=BOT, holds=remote.holds)
    slack = Slack()
    miracle = MiracleService(trades, SlackBoard(slack, HOME), fixed_now)
    server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), NAMES.get, trades,
                   lambda messages: None, miracle=miracle, remote=remote, now=fixed_now)
    made = SimpleNamespace(store=store, remote=remote, trades=trades, miracle=miracle, slack=slack,
                           base=f"http://127.0.0.1:{server.server_address[1]}")
    made.handler = handler(made)
    yield made
    server.shutdown()


def handler(world, miracle=None):
    return CommandHandler(world.store, TrainingAPI(), now=fixed_now, bot_user_id=BOT, remote=world.remote,
                          trades=world.trades, miracle=miracle or world.miracle)


def upload(world, user_id=ALICE, party=LINEUP_PARTY, pool=LINEUP_POOL, bag=LINEUP_BAG, shop=SHOP, kinds=KINDS,
           wallet=500):
    body = {"party": party, "trade_pool": pool, "remote_ops": 1, "applied_op_id": 0, "wallet": wallet,
            "bag": list(bag), "shop": shop, "remote_ops_kinds": list(kinds)}
    status, reply = call(f"{world.base}/v1/party", "POST", world.store.issue_token(user_id, keep_existing=True), body)
    assert status == 200, reply


def slash(world, command, text="", user_id=ALICE, handler=None, pictures=None):
    world.slack.calls.clear()
    body = {"user_id": user_id, "command": command, "text": text, "channel_id": CHANNEL, "response_url": RESPONSE_URL}
    slash_listener(handler or world.handler, pictures)(ack=lambda: None, body=body, respond=world.slack.respond,
                                                       client=world.slack)
    return world.slack.calls


def press(world, editor, action_id, value=None, user_id=ALICE, selected=None, block_id=None, options=None):
    world.slack.calls.clear()
    action = {"action_id": action_id}
    if value is not None:
        action["value"] = value
    if selected is not None:
        action["selected_option"] = {"value": selected}
    if block_id is not None:
        action["block_id"] = block_id
    if options is not None:
        action["selected_options"] = [{"value": option} for option in options]
    editor_listener(editor)(ack=lambda: None, body={"user": {"id": user_id}}, action=action,
                            respond=world.slack.respond, client=world.slack)
    return world.slack.calls


def ask(world, editor, action_id, block_id, query="", options_for=None, user_id=ALICE):
    world.slack.calls.clear()
    payload = {"action_id": action_id, "block_id": block_id, "value": query}
    editor_options_listener(editor, options_for)(ack=world.slack.ack, body={"user": {"id": user_id}}, payload=payload)
    return world.slack.calls


def picker_options(world, action_id, block_id, query="", user_id=BOB):
    world.slack.calls.clear()
    payload = {"action_id": action_id, "block_id": block_id, "value": query}
    options_listener(world.trades)(ack=world.slack.ack, body={"user": {"id": user_id}}, payload=payload)
    return world.slack.calls


def button(world, listener, value=None, user_id=BOB, selected=None):
    world.slack.calls.clear()
    action = {"value": value} if value is not None else {"selected_option": {"value": selected}}
    listener(ack=lambda: None, body={"user": {"id": user_id}}, action=action, respond=world.slack.respond,
             client=world.slack)
    return world.slack.calls


def result(echo=f"<@{ALICE}>님이 `/대결 <@{BOB}>`을 썼어요", **changes):
    summary = f"<@{ALICE}> 승리 · 3턴"
    return Reply(summary, in_channel=True, summary=summary, card=replace(CARD, **changes),
                 rematch=f"{ALICE}:{BOB}:1:{BOB}", echo=echo)


# /파티 and /박스


def test_party_screens(world):
    upload(world)
    editor = world.handler.editor
    pin("party", slash(world, "/파티"))
    pin("party_box_page", slash(world, "/박스"))
    pin("party_box_search", slash(world, "/박스", "고라"))
    pin("party_bag", slash(world, "/가방"))
    pin("party_swap", press(world, editor, SWAP_ACTION, block_id="p1", selected="p1|b1"))
    pin("party_order", press(world, editor, ORDER_ACTION, selected="down|b1"))
    pin("party_item", press(world, editor, ITEM_ACTION, block_id="b1", selected="b1|choiceScarf"))
    pin("party_moves", press(world, editor, MOVES_ACTION, "p2"))
    pin("party_set_moves", press(world, editor, SET_MOVES_ACTION, block_id="p2", options=["33", "89"]))
    pin("party_stale", press(world, editor, MOVES_ACTION, "gone"))
    pin("party_swap_options", ask(world, editor, SWAP_ACTION, "p2"))
    pin("party_swap_options_typed", ask(world, editor, SWAP_ACTION, "+", "콘치"))
    pin("party_item_options", ask(world, editor, ITEM_ACTION, "p2", options_for=editor.item_options))
    pin("party_move_options", ask(world, editor, SET_MOVES_ACTION, "p2", options_for=editor.move_options))


def test_party_screens_for_a_full_party_and_a_long_bench(world):
    six = [party_member(f"p{index}", species, 20) for index, species in enumerate((25, 7, 8, 9, 26, 172), 1)]
    upload(world, party=six, pool=[*LINEUP_POOL, *MANY_BENCH])
    editor = world.handler.editor
    pin("party_full", slash(world, "/파티"))
    pin("party_full_box_add", press(world, editor, BOX_ADD_ACTION, "b1"))
    pin("party_full_box_search", slash(world, "/박스", "몬30"))


def test_party_screens_for_an_app_without_slack_edits(world):
    upload(world, kinds=())
    pin("party_read_only", slash(world, "/파티"))
    pin("party_not_linked", slash(world, "/파티", user_id=CAROL))


# /상점


def test_shop_screens(world):
    upload(world, shop=[*SHOP, *MANY_MACHINES])
    shop = world.handler.shop
    pin("shop", slash(world, "/상점"))
    pin("shop_search_one", slash(world, "/상점", "구애머리띠"))
    pin("shop_pick", press(world, shop, SHOP_PICK_ACTION, selected="rareCandy", block_id="growth"))
    pin("shop_buy", press(world, shop, f"{BUY_ACTION}_1", "1|100|rareCandy"))
    pin("shop_buy_single", press(world, shop, f"{BUY_ACTION}_1", "1|300|tm:87"))
    pin("shop_back", press(world, shop, SHOP_BACK_ACTION, "back"))
    pin("shop_stale", press(world, shop, BUY_ACTION, "1|100|gone"))
    pin("shop_options", ask(world, shop, SHOP_PICK_ACTION, "machine", "11"))


def test_shop_screens_when_the_balance_is_short_or_the_app_is_old(world):
    upload(world, wallet=150)
    shop = world.handler.shop
    pin("shop_short_item", press(world, shop, SHOP_PICK_ACTION, selected="choiceBand"))
    pin("shop_short_buy", press(world, shop, f"{BUY_ACTION}_1", "1|200|choiceBand"))
    upload(world, user_id=BOB, kinds=(LINEUP,))
    pin("shop_read_only", slash(world, "/상점", user_id=BOB))


# /트레이닝


def test_training_screens(world):
    upload(world, party=[THUNDURUS, PIKACHU], pool=[PSYDUCK], bag=TRAINING_BAG, shop=TRAINING_SHOP)
    training = world.handler.training
    pin("training", slash(world, "/트레이닝"))
    pin("training_search_one", slash(world, "/트레이닝", "고라파덕"))
    pin("training_member", press(world, training, TRAINING_PICK_ACTION, selected="p1"))
    pin("training_member_egg_moves", press(world, training, TRAINING_OPEN_ACTION, "p2"))
    pin("training_nature", press(world, training, NATURE_ACTION, selected="p2|adamant"))
    pin("training_moves", press(world, training, TRAINING_MOVES_ACTION, "p2"))
    pin("training_set_moves", press(world, training, TRAINING_SET_MOVES_ACTION, block_id="p2", options=["33"]))
    pin("training_default_moves", press(world, training, TRAINING_DEFAULT_MOVES_ACTION, "p2"))
    pin("training_back", press(world, training, TRAINING_BACK_ACTION, "p2"))
    pin("training_stale", press(world, training, NATURE_ACTION, selected="gone|adamant"))
    pin("training_options", ask(world, training, TRAINING_PICK_ACTION, "picker", "파"))
    pin("training_move_options", ask(world, training, TRAINING_SET_MOVES_ACTION, "p2",
                                     options_for=training.move_options))


def test_training_screens_for_evolutions_a_long_box_and_an_old_app(world):
    upload(world, party=[BOLDORE, ONIX], pool=MANY_BENCH, bag=[*TRAINING_BAG, CORD], shop=TRAINING_SHOP)
    pin("training_long", slash(world, "/트레이닝"))
    pin("training_evolve", press(world, world.handler.training, TRAINING_PICK_ACTION, selected="p3"))
    upload(world, user_id=BOB, kinds=(LINEUP,))
    pin("training_read_only", slash(world, "/트레이닝", user_id=BOB))


# /교환 and /미라클


def test_trade_screens(world):
    upload(world)
    upload(world, user_id=BOB, party=[party_member("bp", 4, 30)],
           pool=[box_entry("bob-1", 7, "꼬부기"), box_entry("bob-2", 1, "이상해씨")])
    trading = world.handler.trading
    bob = world.trades.handle(BOB)
    pin("trade", slash(world, "/교환"))
    pin("trade_to_coworker", slash(world, "/교환", f"<@{BOB}|bob> 고라"))
    pin("trade_unknown_coworker", slash(world, "/교환", f"<@{CAROL}>"))
    pin("trade_give", press(world, trading, GIVE_ACTION, block_id="to:", selected="to:|b1"))
    pin("trade_to", press(world, trading, TO_ACTION, selected=f"to:{bob}|b1"))
    pin("trade_send", press(world, trading, SEND_ACTION, f"to:{bob}|b1"))
    pin("trade_open", slash(world, "/교환"))
    trade_id = world.trades.history(ALICE)[0]["trade_id"]
    pin("trade_back", press(world, trading, OFFER_BACK_ACTION, f"to:{bob}|"))
    pin("trade_not_tradable", press(world, trading, TO_ACTION, selected=f"to:{bob}|b1"))
    pin("trade_options", ask(world, trading, GIVE_ACTION, "to:", "발"))
    pin("trade_dm_pick", button(world, trade_listener(world.trades, "pick"), selected=f"{trade_id}|bob-1"))
    pin("trade_dm_accept", button(world, trade_listener(world.trades, "accept"), trade_id))
    pin("trade_dm_confirm", button(world, trade_listener(world.trades, "accept"), trade_id, user_id=ALICE))
    pin("trade_dm_declined_after", button(world, trade_listener(world.trades, "decline"), trade_id))
    pin("trade_dm_options", picker_options(world, "trade_pick", trade_id))


def test_trade_cancel_and_decline(world):
    upload(world)
    upload(world, user_id=BOB, party=[party_member("bp", 4, 30)], pool=[box_entry("bob-1", 7, "꼬부기")])
    bob = world.trades.handle(BOB)
    press(world, world.handler.trading, SEND_ACTION, f"to:{bob}|b1")
    first = world.trades.history(ALICE)[0]["trade_id"]
    pin("trade_cancel", press(world, world.handler.trading, CANCEL_ACTION, first))
    second = world.trades.propose(ALICE, bob, "b2").trade_id
    pin("trade_dm_decline", button(world, trade_listener(world.trades, "decline"), second))
    pin("trade_dm_error", button(world, trade_listener(SimpleNamespace(), "accept"), second))


def test_a_trade_offer_to_a_coworker_with_nothing_to_give(world):
    upload(world)
    upload(world, user_id=BOB, party=[party_member("bp", 4, 30)], pool=[box_entry("bob-1", 7, "꼬부기")])
    world.trades.propose(BOB, world.trades.handle(ALICE), "bob-1")
    pin("trade_offer_nothing_to_give", press(world, world.handler.trading, SEND_ACTION,
                                             f"to:{world.trades.handle(BOB)}|b1"))


def test_miracle_screens_and_cards(world):
    upload(world)
    upload(world, user_id=BOB, party=[party_member("bp", 4, 30)], pool=[box_entry("bob-1", 7, "꼬부기")])
    trading = world.handler.trading
    pin("miracle", slash(world, "/미라클"))
    pin("miracle_search_one", slash(world, "/미라클", "콘치"))
    pin("miracle_pick", press(world, trading, MIRACLE_PICK_ACTION, block_id="miracle", selected="miracle|b1"))
    pin("miracle_back", press(world, trading, MIRACLE_BACK_ACTION, "miracle"))
    pin("miracle_post", press(world, trading, MIRACLE_POST_ACTION, "b1"))
    pin("miracle_posted", slash(world, "/미라클"))
    offer_id = world.miracle.status(ALICE)["offer_id"]
    pin("miracle_card_own", button(world, miracle_listener(world.miracle, "accept"), offer_id, user_id=ALICE))
    pin("miracle_card_accept", button(world, miracle_listener(world.miracle, "accept"), offer_id))
    pin("miracle_card_cancel_not_poster", button(world, miracle_listener(world.miracle, "cancel"), offer_id))
    pin("miracle_card_options", picker_options(world, "miracle_pick", offer_id))
    pin("miracle_card_pick", button(world, miracle_listener(world.miracle, "pick"), selected=f"{offer_id}|bob-1"))
    pin("miracle_card_pick_late", button(world, miracle_listener(world.miracle, "pick"),
                                         selected=f"{offer_id}|bob-1", user_id=CAROL))


def test_miracle_take_down_and_ended_cards(world):
    upload(world)
    trading = world.handler.trading
    press(world, trading, MIRACLE_POST_ACTION, "b1")
    offer_id = world.miracle.status(ALICE)["offer_id"]
    pin("miracle_down", press(world, trading, MIRACLE_DOWN_ACTION, offer_id))
    pin("miracle_down_again", press(world, trading, MIRACLE_DOWN_ACTION, offer_id))
    world.slack.calls.clear()
    press(world, trading, MIRACLE_POST_ACTION, "b2")
    offer_id = world.miracle.status(ALICE)["offer_id"]
    pin("miracle_card_cancel", button(world, miracle_listener(world.miracle, "cancel"), offer_id, user_id=ALICE))
    offer = SimpleNamespace(poster_id=ALICE, give=world.trades.pool_entry(ALICE, "b3"))
    pin("miracle_ended_cards", [["card", dict(zip(("text", "blocks"), ended_card(offer, status)))]
                                for status in ("cancelled", "closed", "expired")])


def test_miracle_without_a_battle_channel(world):
    upload(world)
    without_channel = handler(world, MiracleService(world.trades, None, fixed_now))
    pin("miracle_unavailable", slash(world, "/미라클", handler=without_channel))
    pin("miracle_unavailable_press", press(world, without_channel.trading, MIRACLE_POST_ACTION, "b1"))


# Commands, battle results and their thread logs


def test_command_replies(world):
    upload(world)
    world.store.issue_token(BOB)
    world.store.save_party(BOB, [{"pokemon_id": 25, "level": 10, "shiny": False, "ivs": {}}],
                           normalize_dex({"dex": DEX}))
    pin("help", slash(world, "/ypoke"))
    pin("help_unknown_word", slash(world, "/ypoke", "아무거나"))
    pin("record", slash(world, "/전적", f"<@{BOB}>"))
    pin("ranking_empty", slash(world, "/랭킹"))
    pin("link", slash(world, "/포켓몬연결"))
    pin("dex", slash(world, "/도감", f"<@{BOB}>"))
    pin("dex_not_linked", slash(world, "/도감", f"<@{CAROL}>"))
    pin("dex_bot", slash(world, "/도감", f"<@{BOT}>"))
    pin("battle_self", slash(world, "/대결", f"<@{ALICE}>"))
    pin("battle_waits_for_an_unlinked_opponent", slash(world, "/대결", f"<@{CAROL}>"))
    pin("battle_waits_for_the_challenger", slash(world, "/대결", f"<@{BOB}>", user_id=CAROL))
    pin("command_error", slash(world, "/대결", f"<@{BOB}>", handler=Scripted()))


def test_ranking_with_battles(world):
    world.store.record_battle(ALICE, BOB, ALICE, 7, pokemon=(25, 7), turns=3)
    world.store.record_battle(BOB, CAROL, BOB, 8, pokemon=(7, 4), turns=5)
    pin("ranking", slash(world, "/랭킹"))


def test_battle_results(world):
    pictures = Pictures()
    pin("result_slash", slash(world, "/대결", handler=Scripted(result())))
    pin("result_slash_practice", slash(world, "/대결", handler=Scripted(result(practice=True, rules=()))))
    pin("result_slash_pictures", slash(world, "/대결", handler=Scripted(result()), pictures=pictures))
    world.slack.refuse = lambda method, message: method == "chat.postMessage"
    pin("result_slash_bot_not_in_channel", slash(world, "/대결", handler=Scripted(result())))
    world.slack.refuse = lambda method, message: any("slack_file" in block for block in message.get("blocks") or [])
    pin("result_pictures_refused", slash(world, "/대결", handler=Scripted(result()), pictures=Pictures()))


def test_a_long_battle_log_splits_into_messages(world):
    log = tuple(f"*{turn}턴*\n피카츄의 10만볼트!" for turn in range(1, 61))
    matchups = tuple(Matchup(PIKA, SQUIRT) if turn % 20 == 1 else None for turn in range(1, 61))
    world.slack.calls.clear()
    post_result(world.slack, CHANNEL, None, result(log=log, log_matchups=matchups))
    pin("result_long_log", world.slack.calls)


def test_mentions_and_rematches(world):
    upload(world)

    def mention(handler, text=f"<@{BOT}> 대결 <@{BOB}>", thread_ts="1.5"):
        world.slack.calls.clear()
        event = {"user": ALICE, "text": text, "channel": CHANNEL, "ts": "1.6", "thread_ts": thread_ts}
        mention_listener(handler)(event=event, client=world.slack)
        return world.slack.calls

    pin("mention_result", mention(Scripted(result(echo=None))))
    pin("mention_help", mention(world.handler, f"<@{BOT}>"))
    pin("mention_party", mention(world.handler, f"<@{BOT}> 파티"))
    pin("mention_record", mention(world.handler, f"<@{BOT}> 전적", thread_ts=None))
    pin("mention_link", mention(world.handler, f"<@{BOT}> 연결"))
    pin("mention_error", mention(Scripted()))
    card = {"ts": "9.1", "thread_ts": "9.1", "text": "카드",
            "blocks": [{"type": "section", "text": {"type": "mrkdwn", "text": "카드"}},
                       {"type": "actions", "elements": [{"type": "button", "action_id": "rematch",
                                                         "text": {"type": "plain_text", "text": "다시 붙기"},
                                                         "value": f"{ALICE}:{BOB}:1:{BOB}"}]}]}
    replies = (("rematch", replace(result(), spent_card=True)),
               ("rematch_denied", Reply("대결한 두 사람만 누를 수 있어요.")))
    for name, reply in replies:
        world.slack.calls.clear()
        rematch_listener(Scripted(reply))(ack=lambda: None, body={"user": {"id": BOB}, "channel": {"id": CHANNEL},
                                                                  "message": card},
                                          action={"value": f"{ALICE}:{BOB}:1:{BOB}"}, respond=world.slack.respond,
                                          client=world.slack)
        pin(name, world.slack.calls)


def test_pending_battle_deliveries(world, monkeypatch):
    class Webhook:
        def __init__(self, url):
            self.url = url

        def send(self, **message):
            world.slack.calls.append(["webhook", message])
            return SimpleNamespace(status_code=200, body="ok")

    monkeypatch.setattr(ypoke.transport, "WebhookClient", Webhook)
    reply = replace(result(), card=replace(CARD, note="기다리던 포켓몬이 올라와서 대결을 시작해요!"))
    for name, refuse, where in (
        ("deliver_channel", lambda method, message: False, Where(CHANNEL, "1.5", RESPONSE_URL)),
        ("deliver_response_url", lambda method, message: message.get("channel") == CHANNEL,
         Where(CHANNEL, None, RESPONSE_URL)),
        ("deliver_dm", lambda method, message: message.get("channel") == CHANNEL, Where(CHANNEL, None, None)),
    ):
        world.slack.calls.clear()
        world.slack.refuse = refuse
        deliver(world.slack, Delivery(ALICE, where, reply))
        pin(name, world.slack.calls)


def test_trade_picker_options_and_direct_messages(world):
    upload(world)
    upload(world, user_id=BOB, party=[party_member("bp", 4, 30)], pool=[box_entry("bob-1", 7, "꼬부기")])
    trade_id = world.trades.propose(ALICE, world.trades.handle(BOB), "b1").trade_id
    pin("trade_picker_options", picker_options(world, "trade_pick", trade_id, "꼬"))
    world.slack.calls.clear()
    post_direct_messages(world.slack, world.trades.propose(ALICE, world.trades.handle(BOB), "b2").direct_messages)
    pin("trade_offer_dm", world.slack.calls)


def test_a_screen_slack_refuses_is_answered_once(world):
    upload(world)
    world.slack.status = 400
    pin("party_moves_refused", press(world, world.handler.editor, MOVES_ACTION, "p1"))
    pin("party_error", press(world, SimpleNamespace(), MOVES_ACTION, "p1"))
