"""Command echo, the summary + thread-log result shape, the rematch button and the Slack listeners."""

import logging
import sqlite3
from datetime import timedelta

import pytest
from test_commands import CHANNEL, NOW, Clock, handler, pending, upload

from ypoke.commands import (
    BATTLE_COMMAND,
    RANKING_COMMAND,
    RECORD_COMMAND,
    REMATCH_ACTION_ID,
    REMATCH_DENIED,
    Where,
    command_echo,
    result_blocks,
)
from ypoke.store import Record, Store
from ypoke.transport import mention_listener, rematch_listener, slash_listener


@pytest.fixture
def store(tmp_path):
    return Store(str(tmp_path / "bot.sqlite3"))


class FakeClient:
    def __init__(self, fail_post=False):
        self.fail_post = fail_post
        self.posts = []
        self.ephemerals = []

    def chat_postMessage(self, **kwargs):
        if self.fail_post:
            raise RuntimeError("not_in_channel")
        self.posts.append(kwargs)
        return {"ts": f"9.{len(self.posts)}"}

    def chat_postEphemeral(self, **kwargs):
        self.ephemerals.append(kwargs)


class FakeRespond:
    def __init__(self):
        self.calls = []

    def __call__(self, **kwargs):
        self.calls.append(kwargs)


def ready_pair(store):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)


def slash(bot, client, respond, user="UA", command=BATTLE_COMMAND, text="<@UB|bob>", **extra):
    body = {"user_id": user, "command": command, "text": text, "channel_id": "CCHAN",
            "response_url": "https://hooks.example/respond/SECRET", "token": "legacy-secret", **extra}
    slash_listener(bot)(lambda: None, body, respond, client)


def test_echo_names_who_ran_which_command_and_keeps_mentions():
    assert command_echo("UA", "/대결", "<@UB|bob>") == "<@UA> 님이 `/대결` <@UB> 을(를) 썼어요"
    assert command_echo("UA", "/랭킹", "") == "<@UA> 님이 `/랭킹` 을(를) 썼어요"


def test_echo_cannot_ping_or_break_out_of_the_code_span():
    echo = command_echo("UA", "/대결", "<!channel> `x` hello")
    assert "<!channel>" not in echo
    assert "`" not in echo.replace("`/대결`", "").replace("`!channel x hello`", "")


def test_in_channel_slash_replies_carry_the_echo_and_ephemeral_ones_do_not(store):
    ready_pair(store)
    bot = handler(store)
    battle = bot.handle("UA", "<@UB>", BATTLE_COMMAND, echo=True)
    assert battle.in_channel and battle.echo == "<@UA> 님이 `/대결` <@UB> 을(를) 썼어요"
    store.record_battle("UA", "UB", "UA", 1, at=NOW)
    ranking = bot.handle("UA", "", RANKING_COMMAND, echo=True)
    assert ranking.in_channel and ranking.echo == "<@UA> 님이 `/랭킹` 을(를) 썼어요"
    record = bot.handle("UA", "", RECORD_COMMAND, echo=True)
    assert not record.in_channel and record.echo is None


def test_mention_replies_have_no_echo(store):
    ready_pair(store)
    assert handler(store).handle_mention("UA", "<@UBOT> 대결 <@UB>", CHANNEL).echo is None


def test_battle_summary_is_one_line_with_the_rematch_value(store):
    ready_pair(store)
    reply = handler(store).handle("UA", "<@UB>")
    assert reply.summary.startswith("🏆 <@UA> 승 — 피카츄 vs 꼬부기 (")
    assert reply.summary.endswith("턴)")
    assert "\n" not in reply.summary
    assert reply.rematch == "UA:UB"
    assert reply.text.startswith("<@UB>에게 <@UA>이(가) 승부를 걸어왔다!")


def test_a_practice_summary_says_so(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).handle("UA", "<@UBOT>")
    assert reply.summary.endswith(" · 연습 대결")
    assert reply.rematch == "UA:UBOT"


def test_result_blocks_are_echo_summary_and_a_button(store):
    ready_pair(store)
    reply = handler(store).handle("UA", "<@UB>", echo=True)
    context, section, actions = result_blocks(reply)
    assert context["elements"][0]["text"] == reply.echo
    assert section["text"]["text"] == reply.summary
    button = actions["elements"][0]
    assert (button["action_id"], button["value"], button["text"]["text"]) == (REMATCH_ACTION_ID, "UA:UB", "다시 붙기")
    assert len(result_blocks(reply, with_log=True)) == 4


def test_a_pending_battle_keeps_the_original_command_echo(store):
    upload(store, "UA", 25, 60)
    bot = handler(store)
    bot.handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL, echo=True)
    upload(store, "UB", 7, 20)
    [delivery] = bot.run_pending("UB")
    assert delivery.reply.echo == "<@UA> 님이 `/대결` <@UB> 을(를) 썼어요"
    assert delivery.reply.summary and delivery.reply.rematch == "UA:UB"
    assert delivery.text.startswith("기다리던 포켓몬이 올라와서 대결을 시작해요!")


def test_a_pending_challenge_made_by_mention_has_no_echo(store):
    upload(store, "UA", 25, 60)
    bot = handler(store)
    bot.handle_mention("UA", "<@UBOT> 대결 <@UB>", CHANNEL)
    upload(store, "UB", 7, 20)
    [delivery] = bot.run_pending("UB")
    assert delivery.reply.echo is None


def test_a_pending_row_from_before_the_echo_column_still_loads(tmp_path):
    path = str(tmp_path / "old.sqlite3")
    with sqlite3.connect(path) as connection:
        connection.executescript(
            "CREATE TABLE pending_challenges (challenger_id TEXT NOT NULL, opponent_id TEXT NOT NULL,"
            " channel_id TEXT NOT NULL, thread_ts TEXT, response_url TEXT, created_at TEXT NOT NULL,"
            " PRIMARY KEY (challenger_id, opponent_id));"
            "INSERT INTO pending_challenges VALUES ('UA', 'UB', 'CCHAN', '1.1', NULL, '2026-11-12T09:00:00+00:00');"
        )
    [challenge] = Store(path).pending_for("UB", since=NOW - timedelta(days=1))
    assert (challenge.challenger_id, challenge.echo) == ("UA", None)


def test_rematch_by_a_non_participant_is_refused_and_plays_nothing(store):
    ready_pair(store)
    reply = handler(store).rematch("UC", "UA:UB", Where("CCHAN", "1.1"))
    assert reply.text == REMATCH_DENIED
    assert not reply.in_channel
    assert store.record("UA") == Record(0, 0)


def test_rematch_reruns_the_matchup_with_the_current_upload(store):
    ready_pair(store)
    bot = handler(store)
    store.save_party("UB", [{"pokemon_id": 7, "level": 100, "shiny": False, "ivs": {}}])
    reply = bot.rematch("UB", "UA:UB", Where("CCHAN", "1.1"))
    assert reply.in_channel and reply.echo == "<@UB> 님이 다시 붙기를 눌렀어요"
    assert "Lv100" in reply.text
    assert reply.rematch == "UA:UB"
    assert store.record("UB") == Record(1, 0)


def test_rematch_of_a_practice_stays_a_practice(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).rematch("UA", "UA:UBOT", Where("CCHAN", "1.1"))
    assert reply.summary.endswith(" · 연습 대결")
    assert store.record("UA") == Record(0, 0)


def test_rematch_when_a_side_has_no_upload_goes_to_the_pending_flow(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).rematch("UA", "UA:UB", Where("CCHAN", "1.1"))
    assert reply.in_channel and reply.summary is None
    [challenge] = pending(store)
    assert (challenge.channel_id, challenge.thread_ts) == ("CCHAN", "1.1")
    assert challenge.echo == "<@UA> 님이 다시 붙기를 눌렀어요"


def test_a_challenger_without_an_upload_gets_a_visible_line_beside_the_private_detail(store):
    upload(store, "UB", 7, 20)
    reply = handler(store).handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL, echo=True)
    assert not reply.in_channel
    assert reply.text.startswith("아직 내 포켓몬이 YPoke에 없어요.")
    assert reply.public.startswith("<@UA>님은 아직 YPoke에 포켓몬이 없어요.")
    assert reply.echo == "<@UA> 님이 `/대결` <@UB> 을(를) 썼어요"


def test_slash_battle_posts_the_summary_and_threads_the_log_under_it(store):
    ready_pair(store)
    client, respond = FakeClient(), FakeRespond()
    slash(handler(store), client, respond)
    root, log = client.posts
    assert root["channel"] == "CCHAN" and root["thread_ts"] is None
    assert root["blocks"][0]["elements"][0]["text"] == "<@UA> 님이 `/대결` <@UB> 을(를) 썼어요"
    assert root["blocks"][1]["text"]["text"].startswith("🏆")
    assert root["blocks"][2]["elements"][0]["action_id"] == REMATCH_ACTION_ID
    assert log["thread_ts"] == "9.1"
    assert log["text"].startswith("<@UB>에게 <@UA>이(가) 승부를 걸어왔다!")
    assert respond.calls == []


def test_slash_battle_falls_back_to_one_inline_message_where_the_bot_cannot_post(store):
    ready_pair(store)
    client, respond = FakeClient(fail_post=True), FakeRespond()
    slash(handler(store), client, respond)
    [call] = respond.calls
    assert call["response_type"] == "in_channel"
    assert call["blocks"][-1]["text"]["text"].startswith("<@UB>에게 <@UA>이(가) 승부를 걸어왔다!")


def test_slash_ranking_is_echoed_and_record_is_ephemeral_without_it(store):
    store.record_battle("UA", "UB", "UA", 1, at=NOW)
    client, respond = FakeClient(), FakeRespond()
    bot = handler(store, now=lambda: NOW)
    slash(bot, client, respond, command=RANKING_COMMAND, text="")
    slash(bot, client, respond, command=RECORD_COMMAND, text="")
    ranking, record = respond.calls
    assert ranking["response_type"] == "in_channel"
    assert ranking["text"].startswith("<@UA> 님이 `/랭킹` 을(를) 썼어요\n🏆")
    assert record["response_type"] == "ephemeral" and "님이" not in record["text"]


def test_slash_with_an_unready_challenger_shows_a_public_line_after_the_echo(store):
    upload(store, "UB", 7, 20)
    client, respond = FakeClient(), FakeRespond()
    slash(handler(store), client, respond)
    public, private = respond.calls
    assert public["response_type"] == "in_channel"
    assert public["text"].splitlines()[0] == "<@UA> 님이 `/대결` <@UB> 을(를) 썼어요"
    assert "<@UA>님은 아직 YPoke에 포켓몬이 없어요." in public["text"]
    assert private["response_type"] == "ephemeral"


def mention_event(text="<@UBOT> 대결 <@UB>", thread_ts=None):
    return {"user": "UA", "text": text, "channel": "CCHAN", "ts": "5.5", **({"thread_ts": thread_ts} if thread_ts else {})}


def test_mention_result_and_log_both_go_in_the_mentions_thread(store):
    ready_pair(store)
    client = FakeClient()
    mention_listener(handler(store))(mention_event(), client)
    root, log = client.posts
    assert root["thread_ts"] == log["thread_ts"] == "5.5"
    assert root["blocks"][0]["type"] == "section"
    assert client.ephemerals == []


def test_a_mention_from_an_unready_challenger_gets_a_visible_thread_reply(store):
    upload(store, "UB", 7, 20)
    client = FakeClient()
    mention_listener(handler(store))(mention_event(thread_ts="4.4"), client)
    [public] = [post for post in client.posts if post["channel"] == "CCHAN"]
    assert public["thread_ts"] == "4.4"
    assert public["text"].startswith("<@UA>님은 아직 YPoke에 포켓몬이 없어요.")
    [private] = client.ephemerals
    assert private["text"].startswith("아직 내 포켓몬이 YPoke에 없어요.")


def rematch_body(user="UA", message=None):
    return {"user": {"id": user}, "channel": {"id": "CCHAN"}, "message": message or {"ts": "9.1"}}


def test_rematch_posts_the_new_result_in_the_same_thread(store):
    ready_pair(store)
    client, respond = FakeClient(), FakeRespond()
    rematch_listener(handler(store))(lambda: None, rematch_body(), {"value": "UA:UB"}, respond, client)
    root, log = client.posts
    assert root["thread_ts"] == log["thread_ts"] == "9.1"
    assert root["blocks"][0]["elements"][0]["text"] == "<@UA> 님이 다시 붙기를 눌렀어요"


def test_a_rematch_waiting_on_the_opponent_keeps_its_echo_line_in_the_thread(store):
    upload(store, "UA", 25, 60)
    client = FakeClient()
    rematch_listener(handler(store))(lambda: None, rematch_body(), {"value": "UA:UB"}, FakeRespond(), client)
    [notice] = [post for post in client.posts if post["channel"] == "CCHAN"]
    assert notice["thread_ts"] == "9.1"
    assert notice["text"].startswith("<@UA> 님이 다시 붙기를 눌렀어요\n<@UB>님은 아직 YPoke에 포켓몬이 없어서")


def test_rematch_in_a_reply_uses_the_threads_root(store):
    ready_pair(store)
    client = FakeClient()
    message = {"ts": "9.3", "thread_ts": "9.1"}
    rematch_listener(handler(store))(lambda: None, rematch_body(message=message), {"value": "UB:UA"}, FakeRespond(), client)
    assert {post["thread_ts"] for post in client.posts} == {"9.1"}


def test_rematch_by_someone_else_gets_only_a_private_refusal(store):
    ready_pair(store)
    client, respond = FakeClient(), FakeRespond()
    rematch_listener(handler(store))(lambda: None, rematch_body(user="UC"), {"value": "UA:UB"}, respond, client)
    assert client.posts == []
    [call] = respond.calls
    assert call["text"] == REMATCH_DENIED and call["response_type"] == "ephemeral"


def test_the_command_log_line_has_no_token_or_response_url(store, caplog):
    ready_pair(store)
    with caplog.at_level(logging.INFO):
        slash(handler(store), FakeClient(), FakeRespond())
        mention_listener(handler(store))(mention_event(), FakeClient())
    lines = [record.getMessage() for record in caplog.records]
    assert any(line.startswith("slash user=UA command=/대결 args=") for line in lines)
    assert any(line.startswith("mention user=UA command=/대결 args=") for line in lines)
    joined = "\n".join(lines)
    assert "SECRET" not in joined and "legacy-secret" not in joined and "hooks.example" not in joined
