"""What each slash command shows the channel and what only the caller sees."""

import json

import pytest
from test_commands import NOW, handler, upload
from test_dex import with_dex
from test_result_thread import FakeClient, FakeRespond, slash

from ypoke.commands import (
    BATTLE_COMMAND,
    DEX_COMMAND,
    HELP_PUBLIC_LINE,
    HELP_TEXT,
    LINK_COMMAND,
    RANKING_COMMAND,
    RECORD_COMMAND,
    REGISTER_LINK,
    UMBRELLA_COMMAND,
    command_echo,
)
from ypoke.remote_views import REMOTE_COMMANDS
from ypoke.store import Store
from ypoke.transport import mention_listener

CHANNEL_ID = "CCHAN"


@pytest.fixture
def store(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    upload(store, "UA", 25, 60)
    with_dex(store, "UB")
    store.record_battle("UA", "UB", "UA", 1, at=NOW)
    return store


def split(client, respond):
    """Public: channel posts and in-channel responses. Private: ephemeral responses and DMs."""
    public = [call for call in respond.calls if call.get("response_type") == "in_channel"]
    public += [post for post in client.posts if post["channel"] == CHANNEL_ID]
    private = [call for call in respond.calls if call.get("response_type") == "ephemeral"]
    private += [post for post in client.posts if post["channel"] != CHANNEL_ID] + client.ephemerals
    return public, private


def run(store, command, text):
    client, respond = FakeClient(), FakeRespond()
    slash(handler(store), client, respond, command=command, text=text)
    return split(client, respond)


@pytest.mark.parametrize(("command", "text", "public_line"), [
    (RECORD_COMMAND, "", "<@UA> 전적: 1승 0패"),
    (RECORD_COMMAND, "<@UB|bob>", "<@UB> 전적: 0승 1패"),
    (DEX_COMMAND, "<@UB|bob>", "📖 <@UB>님의 도감"),
    (RANKING_COMMAND, "", "🏆 이번 주 랭킹"),
    (UMBRELLA_COMMAND, "전적", "<@UA> 전적: 1승 0패"),
    (UMBRELLA_COMMAND, "도감 <@UB|bob>", "📖 <@UB>님의 도감"),
])
def test_a_result_is_posted_in_the_channel_under_the_echo_and_nothing_is_private(store, command, text, public_line):
    public, private = run(store, command, text)
    [message] = public
    echo, first = message["text"].splitlines()[:2]
    assert echo == command_echo("UA", command, text)
    assert first.startswith(public_line)
    assert private == []


def test_a_slash_battle_is_posted_in_the_channel_under_the_echo(store):
    upload(store, "UB", 7, 20)
    public, private = run(store, BATTLE_COMMAND, "<@UB|bob>")
    [message] = public
    assert message["blocks"][0]["elements"][0]["text"] == command_echo("UA", BATTLE_COMMAND, "<@UB|bob>")
    assert private == []


@pytest.mark.parametrize(("command", "text"), [(LINK_COMMAND, ""), (UMBRELLA_COMMAND, "연결")])
def test_linking_tells_the_channel_one_line_and_keeps_the_link_in_the_dm(store, command, text):
    public, private = run(store, command, text)
    [message] = public
    assert message["text"] == f"{command_echo('UA', command, text)}\n<@UA>님이 YPoke 연결 링크를 받았어요."
    ephemeral, dm = private
    assert ephemeral["text"] == "DM으로 연결 링크를 보냈어요."
    assert dm["channel"] == "UA" and REGISTER_LINK in json.dumps(dm["blocks"])


@pytest.mark.parametrize("text", ["", "help", "도움말"])
def test_the_help_shows_one_public_line_and_keeps_the_long_text_private(store, text):
    public, private = run(store, UMBRELLA_COMMAND, text)
    [message] = public
    assert message["text"] == f"{command_echo('UA', UMBRELLA_COMMAND, text)}\n{HELP_PUBLIC_LINE}"
    [ephemeral] = private
    assert ephemeral["text"] == HELP_TEXT


@pytest.mark.parametrize(("command", "text", "private_text"), [
    (UMBRELLA_COMMAND, "등록", HELP_TEXT),
    (BATTLE_COMMAND, "help", HELP_TEXT),
    (BATTLE_COMMAND, "<@UA>", "자기 자신과는 대결할 수 없어요."),
    (DEX_COMMAND, "<@UC>", "<@UC>님은 아직 YPoke에 연결하지 않았어요."),
    (DEX_COMMAND, "<@UBOT>", "YPoke는 도감이 없어요."),
])
def test_a_mistake_or_a_not_ready_target_is_answered_only_to_the_caller(store, command, text, private_text):
    public, private = run(store, command, text)
    assert public == []
    [ephemeral] = private
    assert ephemeral["text"] == private_text and "님이" not in ephemeral["text"].splitlines()[0]


def test_a_mention_dex_error_stays_private_in_the_thread(store):
    client = FakeClient()
    mention_listener(handler(store))({"user": "UA", "channel": CHANNEL_ID, "ts": "5.5", "text": "<@UBOT> 도감 <@UC>"}, client)
    assert client.posts == []
    assert client.ephemerals[0]["text"] == "<@UC>님은 아직 YPoke에 연결하지 않았어요."


def test_no_token_link_or_response_url_ever_reaches_a_public_message(store, monkeypatch):
    tokens = []
    issue = store.issue_token
    monkeypatch.setattr(store, "issue_token", lambda *args, **kwargs: tokens.append(issue(*args, **kwargs)) or tokens[-1])
    bot = handler(store)
    client, respond = FakeClient(), FakeRespond()
    for command, text in [
        (LINK_COMMAND, ""), (UMBRELLA_COMMAND, "연결"), (BATTLE_COMMAND, "<@UC>"), (BATTLE_COMMAND, "<@UB>"),
        (RECORD_COMMAND, ""), (DEX_COMMAND, "<@UB>"), (UMBRELLA_COMMAND, ""),
    ]:
        slash(bot, client, respond, command=command, text=text)
    slash(bot, client, respond, user="UD", command=BATTLE_COMMAND, text="<@UA>")
    mention_listener(bot)({"user": "UA", "channel": CHANNEL_ID, "ts": "5.5", "text": "<@UBOT> 연결"}, client)
    public, private = split(client, respond)
    assert len(tokens) >= 5 and public
    shared, kept = json.dumps(public, ensure_ascii=False), json.dumps(private, ensure_ascii=False)
    for secret in [*tokens, REGISTER_LINK, "hooks.example", "legacy-secret"]:
        assert secret not in shared
    assert all(token in kept for token in tokens)


@pytest.mark.parametrize(("command", "text"), [
    *((command, "") for command in REMOTE_COMMANDS), (UMBRELLA_COMMAND, "파티"), (UMBRELLA_COMMAND, "박스 피카"),
])
def test_the_remote_views_and_stubs_are_only_seen_by_the_caller(store, command, text):
    public, private = run(store, command, text)
    assert public == []
    [ephemeral] = private
    assert ephemeral["blocks"]
