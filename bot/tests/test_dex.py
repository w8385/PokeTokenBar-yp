"""The dex summary: upload, storage, the `도감` command and its Slack reply shape."""

import sqlite3

import pytest
from test_commands import handler, upload
from test_result_thread import FakeClient, FakeRespond, slash

from ypoke.commands import DEX_COMMAND, UMBRELLA_COMMAND, Where, message_blocks
from ypoke.dex import bar, normalize_dex, percent, progress_fields, progress_lines, sprite_url
from ypoke.store import Store
from ypoke.transport import mention_listener

DEX = {
    "owned": 120, "shiny": 3,
    "regions": {"kanto": 151, "johto": 40, "paldea": 0},
    "representative": {"pokemon_id": 25, "shiny": True},
}


@pytest.fixture
def store(tmp_path):
    return Store(str(tmp_path / "bot.sqlite3"))


def with_dex(store, user_id, dex=DEX):
    upload(store, user_id, 25, 10)
    store.save_party(user_id, [{"pokemon_id": 25, "level": 10, "shiny": False, "ivs": {}}], normalize_dex({"dex": dex}))


def test_a_missing_or_broken_dex_is_ignored_not_rejected():
    assert normalize_dex({}) is None
    assert normalize_dex({"dex": "x"}) is None
    assert normalize_dex({"dex": {"owned": 2000, "shiny": 0}}) is None
    assert normalize_dex({"dex": {"owned": True, "shiny": 0}}) is None


def test_bad_parts_of_the_dex_are_dropped():
    dex = normalize_dex({"dex": {
        "owned": 5, "shiny": 1,
        "regions": {"kanto": 152, "johto": 3, "nowhere": 1, "hoenn": "x"},
        "representative": {"pokemon_id": 0, "shiny": True},
    }})
    assert dex == {"owned": 5, "shiny": 1, "regions": {"johto": 3}}


def test_a_party_upload_without_dex_keeps_the_stored_dex(store):
    with_dex(store, "UB")
    store.save_party("UB", [{"pokemon_id": 7, "level": 5, "shiny": False, "ivs": {}}])
    assert store.dex("UB")["owned"] == 120


def test_a_database_from_before_the_dex_column_still_opens(tmp_path):
    path = str(tmp_path / "old.sqlite3")
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE users (slack_user_id TEXT PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL, "
                           "party_json TEXT, uploaded_at TEXT)")
    store = Store(path)
    assert store.dex("U1") is None


def test_dex_of_a_target_lists_counts_regions_and_the_representative(store):
    with_dex(store, "UB")
    reply = handler(store).handle("UA", "<@UB|bob>", DEX_COMMAND)
    assert reply.text.splitlines() == [
        "📖 <@UB>님의 도감",
        "전체 *120*/1025 · ✨ 이로치 *3*",
        "관동 151/151 ✅ · 성도 40/100 · 호연 0/135",
        "신오 0/107 · 하나 0/156 · 칼로스 0/72",
        "알로라 0/88 · 가라르 0/96 · 팔데아 0/120",
        "전국 120/1025",
        "대표 포켓몬: 피카츄 ✨",
    ]
    assert reply.image_url == sprite_url(25, True)
    assert not reply.in_channel


def test_dex_without_a_target_is_your_own(store):
    with_dex(store, "UA", {"owned": 1, "shiny": 0})
    reply = handler(store).handle("UA", "", DEX_COMMAND)
    assert reply.text.splitlines()[:2] == ["📖 <@UA>님의 도감", "전체 *1*/1025 · ✨ 이로치 *0*"]
    assert reply.lead == "📖 <@UA>님의 도감\n전체 *1*/1025 · ✨ 이로치 *0*"
    assert reply.image_url is None


def test_an_unlinked_target_gets_one_short_line(store):
    assert handler(store).handle("UA", "<@UB>", DEX_COMMAND).text == "<@UB>님은 아직 YPoke에 연결하지 않았어요."
    assert "/포켓몬연결" in handler(store).handle("UA", "", DEX_COMMAND).text


def test_a_linked_target_without_a_dex_upload_gets_one_short_line(store):
    upload(store, "UB", 25, 10)
    reply = handler(store).handle("UA", "<@UB>", DEX_COMMAND)
    assert len(reply.text.splitlines()) == 1 and "아직 올라오지 않았어요" in reply.text


def test_the_bot_has_no_dex(store):
    assert handler(store).handle("UA", "<@UBOT>", DEX_COMMAND).text == "YPoke는 도감이 없어요."


def test_the_umbrella_command_routes_a_dex_word(store):
    with_dex(store, "UB")
    assert handler(store).handle("UA", "도감 <@UB>", UMBRELLA_COMMAND).text.startswith("📖 <@UB>님의 도감")
    assert handler(store).handle("UA", "", UMBRELLA_COMMAND).text.startswith("*YPoke 대결*")


def test_a_mention_answers_visibly_in_the_thread_with_the_sprite(store):
    with_dex(store, "UB")
    client = FakeClient()
    mention_listener(handler(store))(
        {"user": "UA", "channel": "CCHAN", "ts": "5.5", "text": "<@UBOT> 도감 <@UB>"}, client)
    post = client.posts[0]
    assert post["thread_ts"] == "5.5" and "echo" not in post
    assert post["text"].startswith("📖 <@UB>님의 도감")
    assert post["blocks"][0]["accessory"]["image_url"] == sprite_url(25, True)
    assert client.ephemerals == []


def test_a_slash_answers_privately_with_the_sprite(store):
    with_dex(store, "UB")
    respond = FakeRespond()
    slash(handler(store), FakeClient(), respond, command=DEX_COMMAND, text="<@UB>")
    call = respond.calls[0]
    assert call["response_type"] == "ephemeral"
    assert call["text"].startswith("📖 <@UB>님의 도감")
    assert call["blocks"][0]["accessory"]["image_url"] == sprite_url(25, True)


def test_a_one_line_reply_has_no_blocks(store):
    respond = FakeRespond()
    slash(handler(store), FakeClient(), respond, command=DEX_COMMAND, text="<@UB>")
    assert respond.calls[0]["blocks"] is None


SUMMARY = normalize_dex({"dex": DEX})


def test_the_grid_has_ten_fields_in_dex_order_with_the_national_total_last():
    fields = progress_fields(SUMMARY)
    assert len(fields) == 10
    names = [field.split("*")[1] for field in fields]
    assert names == ["관동", "성도", "호연", "신오", "하나", "칼로스", "알로라", "가라르", "팔데아", "전국"]
    assert fields[0] == "*관동*  151/151 ✅\n▰▰▰▰▰▰▰▰▰▰ 100%"
    assert fields[1] == "*성도*  40/100\n▰▰▰▰▱▱▱▱▱▱ 40%"
    assert fields[2] == "*호연*  0/135\n▱▱▱▱▱▱▱▱▱▱ 0%"
    assert fields[9] == "*전국*  120/1025\n▰▱▱▱▱▱▱▱▱▱ 12%"


def test_the_bar_and_percent_round_at_the_edges():
    assert (bar(0, 151), percent(0, 151)) == ("▱" * 10, 0)
    assert (bar(1, 151), percent(1, 151)) == ("▰" + "▱" * 9, 1)
    assert (bar(150, 151), percent(150, 151)) == ("▰" * 9 + "▱", 99)
    assert (bar(151, 151), percent(151, 151)) == ("▰" * 10, 100)
    assert (bar(37, 151), percent(37, 151)) == ("▰▰" + "▱" * 8, 25)
    assert percent(1, 2) == 50


def test_only_a_completed_region_gets_the_check():
    fields = progress_fields(SUMMARY)
    assert [("✅" in field) for field in fields] == [True] + [False] * 9


def test_the_fallback_text_has_at_most_three_regions_a_line():
    lines = progress_lines(SUMMARY)
    assert len(lines) == 4 and all(line.count(" · ") <= 2 for line in lines)


def test_the_blocks_are_the_lead_with_the_sprite_then_the_grid(store):
    with_dex(store, "UB")
    result = message_blocks(handler(store).handle("UA", "<@UB>", DEX_COMMAND), False)
    assert [block["type"] for block in result] == ["section", "section"]
    assert "관동" not in result[0]["text"]["text"] and "대표 포켓몬: 피카츄 ✨" in result[0]["text"]["text"]
    assert len(result[1]["fields"]) == 10 and result[1]["fields"][0]["type"] == "mrkdwn"


def test_a_dex_without_a_representative_still_gets_the_grid(store):
    with_dex(store, "UB", {"owned": 1, "shiny": 0})
    respond = FakeRespond()
    slash(handler(store), FakeClient(), respond, command=DEX_COMMAND, text="<@UB>")
    blocks = respond.calls[0]["blocks"]
    assert "accessory" not in blocks[0] and len(blocks[1]["fields"]) == 10
    assert respond.calls[0]["response_type"] == "ephemeral"


def test_a_mention_reply_carries_the_grid_in_the_thread(store):
    with_dex(store, "UB")
    client = FakeClient()
    mention_listener(handler(store))(
        {"user": "UA", "channel": "CCHAN", "ts": "5.5", "text": "<@UBOT> 도감 <@UB>"}, client)
    assert len(client.posts[0]["blocks"][1]["fields"]) == 10
