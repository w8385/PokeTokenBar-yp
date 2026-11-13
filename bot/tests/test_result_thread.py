"""Command echo, the one-message battle result, the rematch button and the Slack listeners."""

import logging
import re
import sqlite3
from dataclasses import replace
from datetime import timedelta

import pytest
from test_commands import CHANNEL, NOW, Clock, handler, lineups, member, pending, upload

from ypoke.battle import Action, BaseStats, BattleResult, Combatant, SendOut
from ypoke.commands import (
    BATTLE_COMMAND,
    RANKING_COMMAND,
    RECORD_COMMAND,
    REMATCH_ACTION_ID,
    REMATCH_DENIED,
    Delivery,
    Reply,
    Where,
    command_echo,
    fallback_text,
    result_blocks,
)
from ypoke.narration import Card, battle_card
from ypoke.store import Record, Store
from ypoke.transport import deliver, mention_listener, rematch_listener, slash_listener


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
    assert re.fullmatch(r"🏆 <@U[AB]> 승 · 1:1 · \d+턴", reply.summary)
    assert reply.rematch == "UA:UB:1"
    assert reply.card.columns[0].startswith("🔵 *<@UA>*") and reply.card.columns[1].startswith("🔴 *<@UB>*")
    assert reply.text == reply.summary
    assert reply.card.log[0].startswith("*1턴*\n")


def test_a_practice_summary_says_so(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).handle("UA", "<@UBOT>")
    assert reply.summary.endswith(" · 연습 대결")
    assert reply.card.practice
    assert reply.rematch == "UA:UBOT:1"


def test_result_blocks_are_context_header_lineups_button_divider_and_one_context_block_per_turn(store):
    ready_pair(store)
    reply = handler(store).handle("UA", "<@UB>", echo=True)
    context, header, lineups, actions, divider, *turns = result_blocks(reply)
    assert context["elements"][0]["text"] == reply.echo
    assert header["text"]["text"] == f"*{reply.card.title}*\n{reply.card.detail}"
    assert header["accessory"]["type"] == "image" and header["accessory"]["image_url"].endswith("/25.png")
    assert [field["text"] for field in lineups["fields"]] == list(reply.card.columns)
    button = actions["elements"][0]
    assert (button["action_id"], button["value"], button["text"]["text"]) == (
        REMATCH_ACTION_ID, "UA:UB:1", "다시 붙기")
    assert divider == {"type": "divider"}
    assert [turn["type"] for turn in turns] == ["context"] * len(reply.card.log)
    assert [turn["elements"][0]["text"] for turn in turns] == list(reply.card.log)


def test_a_one_on_one_has_no_highlight_section_and_a_full_lineup_has_the_deciding_knockout_in_the_header(store):
    for user in ("UA", "UB"):
        store.issue_token(user)
        store.save_party(user, [member(25, 50), member(7, 20), member(25, 40)])
    bot = handler(store)
    one = bot.handle("UA", "<@UB>")
    assert result_blocks(one)[0]["text"]["text"] == f"*{one.card.title}*\n{one.card.detail}"
    three = bot.handle("UA", "<@UB> 3")
    header = result_blocks(three)[0]["text"]["text"].splitlines()
    assert header[0] == f"*{three.card.title}*" and header[1].startswith("3:3 · ")
    assert len(header) == 3 and header[2].startswith("💥 결정타 ")


def test_result_blocks_without_echo_or_note_start_with_the_header_and_have_no_divider_without_a_log():
    card = Card(("🔵 *<@UA>*\n피카츄 100%", "🔴 *<@UB>*\n꼬부기 💥"), title="🏆 <@UA> 승", detail="1:1 · 1턴")
    reply = Reply("🏆 <@UA> 승 · 1:1 · 1턴", summary="🏆 <@UA> 승 · 1:1 · 1턴", card=card, rematch="UA:UB:1")
    assert [block["type"] for block in result_blocks(reply)] == ["section", "section", "actions"]
    noted = replace(reply, card=replace(card, note="기다리던 포켓몬이 올라와서 대결을 시작해요!", practice=True))
    context = result_blocks(noted)[0]
    assert context["type"] == "context"
    assert [element["text"] for element in context["elements"]] == [
        "기다리던 포켓몬이 올라와서 대결을 시작해요!", "연습 대결"]


def test_a_long_battle_stays_within_slacks_fifty_blocks_and_keeps_every_faint():
    sides = ((mon_of("피카츄"),) * 3, (mon_of("꼬부기"),) * 3)
    events = [Action(turn, turn % 2, "피카츄", "꼬부기", "몸통박치기", defender_hp=99) for turn in range(1, 301)]
    for turn in (40, 120, 200, 260):
        events.insert(turn, SendOut(turn, 1, "꼬부기"))
        events.insert(turn, Action(turn, 0, "피카츄", "꼬부기", "몸통박치기", knockout=True, defender_hp=0))
    result = BattleResult(0, 300, events, remaining=((50, None, None), (0, 0, 70)))
    reply = Reply("h", summary="h", card=battle_card(("<@UA>", "<@UB>"), sides, result), rematch="UA:UB:3")
    blocks = result_blocks(replace(reply, echo="echo"))
    assert len(blocks) <= 50
    text = "\n".join(entry["elements"][0]["text"] for entry in blocks if entry["type"] == "context")
    assert text.count("→ 꼬부기 💥") == 4
    assert "생략" in text and "*1턴*" in text and "*300턴*" in text
    assert all(len(entry["elements"][0]["text"]) <= 3000 for entry in blocks if entry["type"] == "context")


def mon_of(name):
    return Combatant(name, 50, ("normal",), BaseStats(80, 80, 80, 80, 80, 80), BaseStats(15, 15, 15, 15, 15, 15))


def test_the_plain_text_fallback_stays_short(store):
    ready_pair(store)
    reply = handler(store).handle("UA", "<@UB>", echo=True)
    assert fallback_text(reply) == f"{reply.echo}\n{reply.summary}"
    assert "\n" not in reply.summary and "턴\n" not in fallback_text(reply)


def test_a_pending_battle_keeps_the_original_command_echo(store):
    upload(store, "UA", 25, 60)
    bot = handler(store)
    bot.handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL, echo=True)
    upload(store, "UB", 7, 20)
    [delivery] = bot.run_pending("UB")
    assert delivery.reply.echo == "<@UA> 님이 `/대결` <@UB> 을(를) 썼어요"
    assert delivery.reply.summary and delivery.reply.rematch == "UA:UB:1"
    assert delivery.reply.card.note == "기다리던 포켓몬이 올라와서 대결을 시작해요!"


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
    store.save_party("UB", [{"pokemon_id": 7, "level": 40, "shiny": False, "ivs": {}}])
    reply = bot.rematch("UB", "UA:UB:1", Where("CCHAN", "1.1"))
    assert reply.in_channel and reply.echo == "<@UB> 님이 다시 붙기를 눌렀어요"
    assert lineups(reply)[1][0].startswith("꼬부기 Lv40")
    assert reply.rematch == "UA:UB:1"
    record = store.record("UB")
    assert record.wins + record.losses == 1


def test_rematch_keeps_the_three_member_format(store):
    for user in ("UA", "UB"):
        store.issue_token(user)
        store.save_party(user, [member(25, 50), member(7, 20), member(25, 40)])
    reply = handler(store).rematch("UA", "UA:UB:3", Where("CCHAN", "1.1"))
    assert [len(side) for side in lineups(reply)] == [3, 3]
    assert " · 3:3 · " in reply.summary
    assert reply.rematch == "UA:UB:3"


def test_a_rematch_value_without_a_size_is_one_on_one(store):
    for user in ("UA", "UB"):
        store.issue_token(user)
        store.save_party(user, [member(25, 50), member(7, 20), member(25, 40)])
    reply = handler(store).rematch("UA", "UA:UB", Where("CCHAN", "1.1"))
    assert [len(side) for side in lineups(reply)] == [1, 1]
    assert reply.rematch == "UA:UB:1"


def test_a_rematch_waiting_on_an_upload_keeps_the_three_member_format(store):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 50)] * 3)
    handler(store).rematch("UA", "UA:UB:3", Where("CCHAN", "1.1"))
    [challenge] = pending(store)
    assert challenge.size == 3


def test_rematch_of_a_practice_stays_a_practice(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).rematch("UA", "UA:UBOT:1", Where("CCHAN", "1.1"))
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


def button_of(message):
    [actions] = [block for block in message["blocks"] if block["type"] == "actions"]
    return actions["elements"][0]


def assert_one_blocks_only_message(message):
    """The whole battle is in `blocks`; `text` is only the echo line and the one-line header."""
    assert any(block["type"] == "context" and block["elements"][0]["text"].startswith("*1턴*")
               for block in message["blocks"])
    assert len(message["text"].splitlines()) <= 2 and message["text"].splitlines()[-1].startswith("🏆 ")
    assert "›" not in message["text"]


def test_slash_battle_posts_one_blocks_message_with_the_log_in_it_and_no_thread_reply(store):
    ready_pair(store)
    client, respond = FakeClient(), FakeRespond()
    slash(handler(store), client, respond)
    [message] = client.posts
    assert message["channel"] == "CCHAN" and message["thread_ts"] is None
    assert message["blocks"][0]["elements"][0]["text"] == "<@UA> 님이 `/대결` <@UB> 을(를) 썼어요"
    assert message["blocks"][1]["text"]["text"].startswith("*🏆")
    assert [field["text"][0] for field in message["blocks"][2]["fields"]] == ["🔵", "🔴"]
    assert button_of(message)["action_id"] == REMATCH_ACTION_ID
    assert_one_blocks_only_message(message)
    assert respond.calls == []


def test_slash_battle_answers_with_the_one_message_where_the_bot_cannot_post(store):
    ready_pair(store)
    client, respond = FakeClient(fail_post=True), FakeRespond()
    slash(handler(store), client, respond)
    [message] = respond.calls
    assert message["response_type"] == "in_channel"
    assert button_of(message)["action_id"] == REMATCH_ACTION_ID
    assert_one_blocks_only_message(message)


def test_the_slash_three_member_battle_posts_both_lineups_with_bars_and_a_three_member_rematch_value(store):
    for user in ("UA", "UB"):
        store.issue_token(user)
        store.save_party(user, [member(25, 50), member(7, 20), member(25, 40)])
    client, respond = FakeClient(), FakeRespond()
    slash(handler(store), client, respond, text="<@UB|bob> 3")
    [message] = client.posts
    fields = message["blocks"][2]["fields"]
    assert all(len(field["text"].splitlines()) == 4 for field in fields)
    members = [line for field in fields for line in field["text"].splitlines()[1:]]
    assert all(re.search(r"[▰▱]{10} \d+%$|💥$|대기$", line) for line in members)
    assert [line.split(" ")[0] for line in fields[0]["text"].splitlines()[1:]] == ["피카츄", "꼬부기", "피카츄"]
    assert button_of(message)["value"] == "UA:UB:3"


class FakeWebhook:
    sent = []

    def __init__(self, url):
        self.url = url

    def send(self, **message):
        FakeWebhook.sent.append(message)
        return type("Response", (), {"status_code": 200})()


def delivery_of(store, response_url="https://hooks.example/respond/SECRET"):
    ready_pair(store)
    reply = handler(store).handle("UA", "<@UB>", echo=True)
    return Delivery("UA", Where("CCHAN", "1.1", response_url), reply)


def test_a_pending_battle_goes_by_response_url_as_the_one_message(store, monkeypatch):
    FakeWebhook.sent = []
    monkeypatch.setattr("ypoke.transport.WebhookClient", FakeWebhook)
    delivery = delivery_of(store)
    deliver(FakeClient(fail_post=True), delivery)
    [message] = FakeWebhook.sent
    assert button_of(message)["action_id"] == REMATCH_ACTION_ID
    assert message["text"] == fallback_text(delivery.reply)
    assert message["response_type"] == "in_channel"
    assert_one_blocks_only_message(message)


def test_a_pending_battle_with_no_other_way_arrives_in_the_challengers_dm_as_the_one_message(store):
    delivery = delivery_of(store, response_url=None)
    client = FakeClient()
    original = client.chat_postMessage

    def only_dm(**kwargs):
        if kwargs["channel"] == "CCHAN":
            raise RuntimeError("not_in_channel")
        return original(**kwargs)

    client.chat_postMessage = only_dm
    deliver(client, delivery)
    note, message = client.posts
    assert {post["channel"] for post in client.posts} == {"UA"}
    assert "blocks" not in note and message["thread_ts"] is None
    assert_one_blocks_only_message(message)


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


def test_a_mention_result_is_one_message_in_the_mentions_thread(store):
    ready_pair(store)
    client = FakeClient()
    mention_listener(handler(store))(mention_event(), client)
    [message] = client.posts
    assert message["thread_ts"] == "5.5"
    assert message["blocks"][0]["type"] == "section"
    assert_one_blocks_only_message(message)
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


def test_rematch_posts_the_new_result_as_one_message_in_the_same_thread(store):
    ready_pair(store)
    client, respond = FakeClient(), FakeRespond()
    rematch_listener(handler(store))(lambda: None, rematch_body(), {"value": "UA:UB:1"}, respond, client)
    [message] = client.posts
    assert message["thread_ts"] == "9.1"
    assert message["blocks"][0]["elements"][0]["text"] == "<@UA> 님이 다시 붙기를 눌렀어요"
    assert button_of(message)["value"] == "UA:UB:1"
    assert respond.calls == []


def test_a_rematch_where_the_bot_cannot_post_answers_the_one_message_without_replacing_the_original(store):
    ready_pair(store)
    client, respond = FakeClient(fail_post=True), FakeRespond()
    rematch_listener(handler(store))(lambda: None, rematch_body(), {"value": "UA:UB:1"}, respond, client)
    [message] = respond.calls
    assert button_of(message)["value"] == "UA:UB:1"
    assert_one_blocks_only_message(message)
    assert message["replace_original"] is False and message["thread_ts"] == "9.1"


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
