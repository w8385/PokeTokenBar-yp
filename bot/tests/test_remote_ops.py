import json
import re
from dataclasses import replace

import pytest
from test_commands import NOW, handler, lineups, member
from test_upload_server import PIKACHU, FakeMoves, call

from ypoke.commands import BATTLE_COMMAND, COMMAND_NAMES, HELP_TEXT, UMBRELLA_COMMAND, message_blocks
from ypoke.remote_ops import (
    OLD_APP_REFUSAL,
    OP_KINDS,
    RESULT_HEADER,
    UNSUPPORTED,
    OpKind,
    RemoteOps,
    normalize_remote,
    register,
)
from ypoke.remote_views import (
    BAG_COMMAND,
    BOX_COMMAND,
    BOX_PAGE_SIZE,
    COMING_SOON,
    MIRACLE_COMMAND,
    NO_UPLOAD,
    NOT_LINKED,
    PARTY_COMMAND,
    REMOTE_COMMANDS,
    SHOP_COMMAND,
    TRADE_COMMAND,
    TRAINING_COMMAND,
)
from ypoke.store import Store
from ypoke.trades import MAX_POOL, TradeService
from ypoke.upload_server import serve

LEVEL_UP = "test_level_up"
REMOTE = {"remote_ops": 1, "wallet": 1200, "bag": [{"key": "rareCandy", "name": "이상한사탕", "count": 3}],
          "shop": [{"key": "mint", "name": "민트", "price": 300}]}


def _level_up(view, payload):
    """Deliberately not idempotent: replaying it twice shows twice the levels."""
    view.party[0]["level"] += payload["levels"]
    return replace(view, wallet=None if view.wallet is None else view.wallet - payload["cost"])


@pytest.fixture(autouse=True)
def level_up_kind():
    register(OpKind(LEVEL_UP, lambda payload: f"레벨 +{payload['levels']}", _level_up))
    yield
    OP_KINDS.pop(LEVEL_UP, None)


@pytest.fixture
def store(tmp_path):
    return Store(str(tmp_path / "bot.sqlite3"))


def upload(store, user_id, pokemon_id=7, level=20, applied=None, remote=True, pool=None):
    """An upload as the server stores it; `remote=False` is an app from before remote ops."""
    store.issue_token(user_id, keep_existing=True)
    payload = {**REMOTE, "applied_op_id": applied} if remote else {}
    store.save_party(user_id, [member(pokemon_id, level)], remote=normalize_remote(payload))
    if pool is not None:
        TradeService(store).save_pool(user_id, pool)


def queue(store, user_id, levels=10, cost=100):
    submitted = RemoteOps(store).submit(user_id, LEVEL_UP, {"levels": levels, "cost": cost})
    assert submitted.refusal is None
    return submitted.op_id


def text_of(reply):
    return "\n".join(block["text"]["text"] if block["type"] == "section" else block["elements"][0]["text"]
                     for block in message_blocks(reply, False))


def pool_entry(index, name="꼬부기", nature="bold"):
    return {"id": f"i{index:04d}", "pokemon_id": 7, "level": 5 + index % 90, "shiny": index % 7 == 0, "name": name,
            "entry": {"nature": nature}}


# Ops table


def test_ops_get_increasing_ids_per_user_and_come_back_in_order(store):
    upload(store, "UA")
    upload(store, "UB")
    assert [queue(store, "UA"), queue(store, "UA"), queue(store, "UB")] == [1, 2, 1]
    ops = RemoteOps(store).pending("UA")
    assert [(op.id, op.kind, op.payload) for op in ops] == [
        (1, LEVEL_UP, {"levels": 10, "cost": 100}), (2, LEVEL_UP, {"levels": 10, "cost": 100}),
    ]


def test_a_settled_op_id_is_never_reused(store):
    upload(store, "UA")
    queue(store, "UA")
    queue(store, "UA")
    RemoteOps(store).ack("UA", [1, 2], [])
    assert queue(store, "UA") == 3


def test_an_unregistered_kind_cannot_be_queued(store):
    upload(store, "UA")
    with pytest.raises(ValueError):
        RemoteOps(store).submit("UA", "nope", {})


# Old-app gate


def test_an_upload_from_an_app_without_remote_ops_refuses_edits(store):
    upload(store, "UA", remote=False)
    submitted = RemoteOps(store).submit("UA", LEVEL_UP, {"levels": 1, "cost": 0})
    assert (submitted.op_id, submitted.refusal) == (None, OLD_APP_REFUSAL)
    assert RemoteOps(store).pending("UA") == []


def test_no_upload_at_all_refuses_edits(store):
    store.issue_token("UA")
    assert RemoteOps(store).submit("UA", LEVEL_UP, {}).refusal == OLD_APP_REFUSAL


def test_a_downgrade_closes_the_gate_again_because_each_upload_overwrites_the_flag(store):
    upload(store, "UA")
    upload(store, "UA", remote=False)
    assert RemoteOps(store).edit_refusal("UA") == OLD_APP_REFUSAL


@pytest.mark.parametrize("command", [SHOP_COMMAND, TRAINING_COMMAND, TRADE_COMMAND, MIRACLE_COMMAND])
def test_the_edit_stubs_tell_an_old_app_to_update_and_a_new_one_that_they_open_soon(store, command):
    upload(store, "UA", remote=False)
    assert handler(store).handle("UA", "", command).text.split("\n")[0] == OLD_APP_REFUSAL
    upload(store, "UA")
    reply = handler(store).handle("UA", "", command)
    assert (reply.text.split("\n")[0], reply.in_channel, reply.public) == (COMING_SOON, False, None)
    assert reply.blocks[-1]["elements"][0]["text"].startswith("회사에서 마지막으로 동기화: ")


def test_views_still_work_for_an_old_app(store):
    upload(store, "UA", remote=False)
    reply = handler(store).handle("UA", "", PARTY_COMMAND)
    assert "꼬부기 Lv.20" in text_of(reply)
    assert "앱을 업데이트하고" in text_of(handler(store).handle("UA", "", BAG_COMMAND))


# Replay over uploads


def test_a_queued_op_survives_an_upload_that_has_not_applied_it_until_one_that_has(store):
    upload(store, "UA", 25, 30)
    upload(store, "UB", 7, 20)
    op_id = queue(store, "UB", levels=10)
    assert opponent_level(store) == "30"
    upload(store, "UB", 7, 20, applied=0)
    assert opponent_level(store) == "30"
    upload(store, "UB", 7, 20, remote=False)
    assert opponent_level(store) == "30"
    upload(store, "UB", 7, 30, applied=op_id)
    assert opponent_level(store) == "30"
    RemoteOps(store).ack("UB", [op_id], [])
    upload(store, "UB", 7, 20, applied=op_id)
    assert opponent_level(store) == "20"


def opponent_level(store):
    reply = handler(store).handle("UA", "<@UB>", BATTLE_COMMAND)
    return re.search(r"Lv(\d+)", lineups(reply)[1][0]).group(1)


def test_pending_ops_replay_in_order_on_top_of_the_upload(store):
    upload(store, "UA", 7, 20)
    queue(store, "UA", levels=1, cost=100)
    queue(store, "UA", levels=2, cost=200)
    view = RemoteOps(store).view("UA")
    assert (view.party[0]["level"], view.wallet, [op.id for op in view.pending]) == (23, 900, [1, 2])
    assert store.party("UA").party[0]["level"] == 20


def test_a_pending_challenge_plays_with_the_replayed_party(store):
    from test_commands import CHANNEL

    upload(store, "UB", 7, 20)
    queue(store, "UB", levels=5)
    battles = handler(store)
    battles.handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL)
    upload(store, "UA", 25, 30)
    [delivery] = battles.run_pending("UA")
    assert lineups(delivery.reply)[1][0].startswith("꼬부기 Lv25")


def test_party_view_shows_the_replayed_party(store):
    upload(store, "UA", 7, 20)
    queue(store, "UA", levels=4)
    assert "꼬부기 Lv.24" in text_of(handler(store).handle("UA", "", PARTY_COMMAND))


def test_a_replay_that_raises_leaves_the_view_as_uploaded(store):
    register(OpKind("test_broken", lambda payload: "고장", lambda view, payload: 1 / 0))
    try:
        upload(store, "UA", 7, 20)
        RemoteOps(store).submit("UA", "test_broken", {})
        queue(store, "UA", levels=1)
        assert RemoteOps(store).view("UA").party[0]["level"] == 21
    finally:
        OP_KINDS.pop("test_broken", None)


# Ack and DM


def test_ack_settles_ops_and_lists_applied_and_cancelled_with_the_reason(store):
    upload(store, "UA")
    queue(store, "UA", levels=1)
    queue(store, "UA", levels=2)
    message = RemoteOps(store).ack("UA", [1], [(2, UNSUPPORTED)])
    assert message.user_id == "UA"
    assert message.text == f"{RESULT_HEADER}\n✅ 레벨 +1\n❌ 레벨 +2: 이 앱 버전은 아직 이 작업을 못 해요"
    assert RemoteOps(store).pending("UA") == []


def test_an_unknown_reason_code_gets_the_generic_line(store):
    upload(store, "UA")
    queue(store, "UA")
    assert RemoteOps(store).ack("UA", [], [(1, "target_gone")]).text.endswith("❌ 레벨 +10: 앱에서 적용하지 못했어요")


def test_a_repeated_ack_changes_nothing_and_sends_no_dm(store):
    upload(store, "UA")
    queue(store, "UA")
    assert RemoteOps(store).ack("UA", [1], []) is not None
    assert RemoteOps(store).ack("UA", [1], []) is None
    assert RemoteOps(store).ack("UA", [], [(1, UNSUPPORTED)]) is None


def test_an_empty_ack_or_one_for_another_users_op_sends_no_dm(store):
    upload(store, "UA")
    upload(store, "UB")
    queue(store, "UA")
    assert RemoteOps(store).ack("UA", [], []) is None
    assert RemoteOps(store).ack("UB", [1], []) is None
    assert [op.id for op in RemoteOps(store).pending("UA")] == [1]


# Endpoints


@pytest.fixture
def server(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    sent = []
    http_server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), notify=sent.extend)
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}", sent
    http_server.shutdown()


def test_get_ops_returns_only_the_callers_pending_ops_in_order(server):
    store, base, _ = server
    token = store.issue_token("UA")
    call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU], **REMOTE})
    upload(store, "UB")
    queue(store, "UA", levels=1)
    queue(store, "UB")
    queue(store, "UA", levels=2)
    status, body = call(f"{base}/v1/ops", token=token)
    assert status == 200
    assert [(op["id"], op["kind"], op["payload"]["levels"]) for op in body["ops"]] == [(1, LEVEL_UP, 1), (2, LEVEL_UP, 2)]
    assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+00:00", body["ops"][0]["created_at"])


def test_get_ops_needs_a_token(server):
    _, base, _ = server
    assert call(f"{base}/v1/ops")[0] == 401


def test_ack_endpoint_settles_and_dms_once(server):
    store, base, sent = server
    token = store.issue_token("UA")
    call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU], **REMOTE})
    queue(store, "UA", levels=1)
    queue(store, "UA", levels=2)
    body = {"applied": [1], "cancelled": [{"id": 2, "reason": UNSUPPORTED}]}
    assert call(f"{base}/v1/ops/ack", "POST", token, body) == (200, {"ok": True})
    assert call(f"{base}/v1/ops/ack", "POST", token, body) == (200, {"ok": True})
    assert [message.text.splitlines()[1:] for message in sent] == [["✅ 레벨 +1", "❌ 레벨 +2: 이 앱 버전은 아직 이 작업을 못 해요"]]
    assert call(f"{base}/v1/ops", token=token)[1]["ops"] == []


def test_an_empty_ack_is_fine_and_sends_nothing(server):
    store, base, sent = server
    token = store.issue_token("UA")
    assert call(f"{base}/v1/ops/ack", "POST", token, {"applied": [], "cancelled": []}) == (200, {"ok": True})
    assert sent == []


@pytest.mark.parametrize("body", [
    {"applied": ["1"]}, {"applied": [0]}, {"applied": [True]}, {"cancelled": [{"id": 1}]},
    {"cancelled": [{"id": 1, "reason": "Not A Code"}]}, {"applied": list(range(1, 502))}, [],
])
def test_a_malformed_ack_is_refused(server, body):
    store, base, _ = server
    token = store.issue_token("UA")
    assert call(f"{base}/v1/ops/ack", "POST", token, body)[0] == 400


def test_an_upload_keeps_the_remote_fields_and_drops_malformed_lines(server):
    store, base, _ = server
    token = store.issue_token("UA")
    bag = [*REMOTE["bag"], {"key": "mega-stone:charizardite-x", "name": "리자몽나이트X", "count": 1},
           {"key": "", "name": "x", "count": 1}, {"key": "tm:85", "name": "기술머신", "count": -1}, "junk"]
    shop = [*REMOTE["shop"], {"key": "tm:85", "name": "10만볼트", "price": 4000, "category": "machine", "single": True},
            {"key": "x", "name": "y", "price": "free"}]
    payload = {"party": [PIKACHU], "remote_ops": 1, "wallet": 77, "bag": bag, "shop": shop, "applied_op_id": 4}
    assert call(f"{base}/v1/party", "POST", token, payload)[0] == 200
    assert store.party("UA").remote == {
        "remote_ops": True, "applied_op_id": 4, "wallet": 77,
        "bag": [{"key": "rareCandy", "name": "이상한사탕", "count": 3},
                {"key": "mega-stone:charizardite-x", "name": "리자몽나이트X", "count": 1}],
        "shop": [{"key": "mint", "name": "민트", "price": 300, "single": False},
                 {"key": "tm:85", "name": "10만볼트", "price": 4000, "single": True, "category": "machine"}],
    }


def test_an_upload_without_remote_ops_stores_no_remote_part(server):
    store, base, _ = server
    token = store.issue_token("UA")
    call(f"{base}/v1/party", "POST", token, {"party": [PIKACHU], "wallet": 5, "bag": REMOTE["bag"]})
    assert store.party("UA").remote is None


# Views


def test_party_view_lists_order_level_nature_ability_item_and_moves(store):
    store.issue_token("UA")
    party = [
        {"pokemon_id": 25, "level": 42, "shiny": True, "ivs": {}, "name": "피카츄", "nature": "timid",
         "ability": "static", "held_item": "light-ball", "moves": [85, 98]},
        {"pokemon_id": 7, "level": 20, "shiny": False, "ivs": {}},
    ]
    store.save_party("UA", party, remote=normalize_remote(REMOTE))
    reply = handler(store).handle("UA", "", PARTY_COMMAND)
    assert not reply.in_channel and reply.public is None
    text = text_of(reply)
    assert "1. 피카츄 ✨ Lv.42\n    겁쟁이 · 정전기 · @전기구슬\n    기술: 10만볼트 / 전광석화" in text
    assert "2. 꼬부기 Lv.20\n    성격 없음 · 특성 없음 · 도구 없음\n    기술: 레벨에 맞는 기본 기술" in text
    assert "회사에서 마지막으로 동기화: " in text


def test_box_view_pages_a_full_pool_and_points_to_the_next_page(store):
    pool = [pool_entry(index) for index in range(MAX_POOL)]
    upload(store, "UA", pool=pool)
    first = text_of(handler(store).handle("UA", "", BOX_COMMAND))
    assert f"*내 박스* 2,000마리 · 1/{MAX_POOL // BOX_PAGE_SIZE}쪽" in first
    assert "1. 꼬부기 Lv.5 ✨ 대담" in first
    assert f"다음 쪽: `{BOX_COMMAND} 2`" in first
    last = handler(store).handle("UA", "999", BOX_COMMAND)
    assert f"{MAX_POOL}. 꼬부기" in text_of(last)
    assert "다음 쪽" not in text_of(last)
    assert len(last.blocks) <= 50 and all(len(block.get("text", {}).get("text", "")) <= 3000 for block in last.blocks)


def test_box_view_searches_by_name_and_keeps_the_query_in_the_next_page_hint(store):
    pool = [pool_entry(index, "피카츄" if index % 2 else "꼬부기") for index in range(60)]
    upload(store, "UA", pool=pool)
    text = text_of(handler(store).handle("UA", "피카", BOX_COMMAND))
    assert "*내 박스* '피카' 검색 30마리 · 1/2쪽" in text
    assert "꼬부기" not in text.split("\n", 1)[1]
    assert f"`{BOX_COMMAND} 피카 2`" in text
    assert "에 맞는 포켓몬이 없어요" in text_of(handler(store).handle("UA", "뮤츠", BOX_COMMAND))


def test_box_view_with_an_empty_pool(store):
    upload(store, "UA")
    assert "박스가 비어 있어요" in text_of(handler(store).handle("UA", "", BOX_COMMAND))


def test_bag_view_shows_the_wallet_after_pending_spends_the_bag_and_the_pending_ops(store):
    upload(store, "UA")
    queue(store, "UA", levels=3, cost=200)
    text = text_of(handler(store).handle("UA", "", BAG_COMMAND))
    assert "쓸 수 있는 토큰: 1,000" in text
    assert "• 이상한사탕 ×3" in text
    assert "*대기 중인 슬랙 작업*\n1. 레벨 +3" in text


@pytest.mark.parametrize("command", REMOTE_COMMANDS)
def test_every_remote_command_before_any_upload_says_what_is_missing(store, command):
    assert handler(store).handle("UA", "", command).text == NOT_LINKED
    store.issue_token("UA")
    assert handler(store).handle("UA", "", command).text == NO_UPLOAD


@pytest.mark.parametrize("word", ["파티", "박스", "가방"])
def test_the_umbrella_and_mentions_reach_the_views(store, word):
    upload(store, "UA")
    for reply in (handler(store).handle("UA", word, UMBRELLA_COMMAND), handler(store).handle_mention("UA", f"<@UBOT> {word}")):
        assert "회사에서 마지막으로 동기화" in text_of(reply)


def test_every_remote_command_is_registered_and_in_the_help(store):
    assert set(REMOTE_COMMANDS) <= set(COMMAND_NAMES)
    for command in REMOTE_COMMANDS:
        assert command in HELP_TEXT
    assert "도장" not in HELP_TEXT
