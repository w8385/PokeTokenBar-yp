"""The dex summary: upload, storage, the `도감` command and its Slack reply shape."""

import sqlite3

import pytest
from test_commands import handler, upload
from test_result_thread import FakeClient, FakeRespond, slash

from ypoke.commands import DEX_COMMAND, UMBRELLA_COMMAND, Where
from ypoke.dex import normalize_dex, sprite_url
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
        "관동 151/151 ✅ · 성도 40/100 · 팔데아 0/120",
        "대표 포켓몬: 피카츄 ✨",
    ]
    assert reply.image_url == sprite_url(25, True)
    assert not reply.in_channel


def test_dex_without_a_target_is_your_own(store):
    with_dex(store, "UA", {"owned": 1, "shiny": 0})
    reply = handler(store).handle("UA", "", DEX_COMMAND)
    assert reply.text.splitlines() == ["📖 <@UA>님의 도감", "전체 *1*/1025 · ✨ 이로치 *0*"]
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
