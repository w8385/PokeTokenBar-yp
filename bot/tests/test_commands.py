from urllib.parse import parse_qs, urlparse

from datetime import UTC, datetime, timedelta

import pytest

from ypoke.commands import (
    BATTLE_COMMAND,
    DOWNLOAD_URL,
    HELP_TEXT,
    LINK_COMMAND,
    RANKING_COMMAND,
    RECORD_COMMAND,
    UMBRELLA_COMMAND,
    CommandHandler,
    bot_species,
    parse_mention,
    reply_thread_ts,
    week_start,
)
from ypoke.battle import simulate
from ypoke.store import Record, Store

SPECIES = {
    25: {"name_ko": "피카츄", "types": ["electric"],
         "base": {"hp": 35, "attack": 55, "defense": 40, "special_attack": 50, "special_defense": 50, "speed": 90}},
    7: {"name_ko": "꼬부기", "types": ["water"],
        "base": {"hp": 44, "attack": 48, "defense": 65, "special_attack": 50, "special_defense": 64, "speed": 43}},
}


WILD = {"name_ko": "야생몬", "types": ["normal"],
        "base": {"hp": 50, "attack": 50, "defense": 50, "special_attack": 50, "special_defense": 50, "speed": 50}}


def move(move_id, name, move_type, power, level, damage_class="special", accuracy=100):
    return {"id": move_id, "name": name, "type": move_type, "power": power,
            "damage_class": damage_class, "accuracy": accuracy, "pp": 15, "crit_rate": 0,
            "ailment": None, "ailment_chance": 0, "stat_changes": [], "stat_target": "target", "stat_chance": 0,
            "level": level}


MOVES = {
    25: [move(84, "전기쇼크", "electric", 40, 1), move(98, "전광석화", "normal", 40, 1, "physical"),
         move(209, "스파크", "electric", 65, 20, "physical"), move(231, "아이언테일", "steel", 100, 28, "physical", 75),
         move(85, "10만볼트", "electric", 90, 36), move(87, "번개", "electric", 110, 44, accuracy=70)],
    7: [move(33, "몸통박치기", "normal", 40, 1, "physical"), move(55, "물대포", "water", 40, 3)],
}
WILD_MOVES = [move(1, "막치기", "normal", 40, 1, "physical")]


class FakePokeAPI:
    def __init__(self, fail=False):
        self.fail = fail
        self.requested = []

    def pokemon(self, pokemon_id):
        if self.fail:
            raise OSError("offline")
        self.requested.append(pokemon_id)
        return SPECIES.get(pokemon_id, WILD)

    def attacking_moves(self, pokemon_id, level):
        if self.fail:
            raise OSError("offline")
        return [m for m in MOVES.get(pokemon_id, WILD_MOVES) if m["level"] <= level]


@pytest.fixture
def store(tmp_path):
    return Store(str(tmp_path / "bot.sqlite3"))


def handler(store, fail=False, public_url=None, now=lambda: NOW, pokeapi=None):
    return CommandHandler(store, pokeapi or FakePokeAPI(fail), public_url, now, bot_user_id="UBOT")


def member(pokemon_id, level):
    return {"pokemon_id": pokemon_id, "level": level, "shiny": False, "ivs": {}}


def upload(store, user_id, pokemon_id, level):
    store.issue_token(user_id)
    store.save_party(user_id, [member(pokemon_id, level)])


def test_register_dms_a_link_button_that_carries_the_token(store):
    reply = handler(store).handle("U1", "", LINK_COMMAND)
    assert not reply.in_channel
    button = reply.direct_message_blocks[1]["elements"][0]
    url = urlparse(button["url"])
    assert (url.scheme, url.netloc) == ("poketokenbar", "ypoke-register")
    token = parse_qs(url.query)["token"][0]
    assert store.user_for_token(token) == "U1"
    assert token not in reply.text
    assert token not in reply.direct_message
    assert f"`{token}`" in reply.direct_message_blocks[2]["elements"][0]["text"]
    assert "server" not in parse_qs(url.query)


def test_register_link_carries_the_public_server_url(store):
    reply = handler(store, public_url="http://example.local:8790").handle("U1", "", LINK_COMMAND)
    url = urlparse(reply.direct_message_blocks[1]["elements"][0]["url"])
    assert parse_qs(url.query)["server"] == ["http://example.local:8790"]
    assert DOWNLOAD_URL in reply.direct_message_blocks[3]["elements"][0]["text"]


def test_battle_without_a_party_points_to_the_download(store):
    upload(store, "UB", 7, 20)
    assert DOWNLOAD_URL in handler(store).handle("UA", "<@UB>").text


def test_battle_is_one_on_one_and_records(store):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)
    reply = handler(store).handle("UA", "<@UB|bob>")
    assert reply.in_channel
    lines = reply.text.splitlines()
    assert lines[:3] == [
        "<@UB>에게 <@UA>이(가) 승부를 걸어왔다!",
        "<@UA>은(는) 피카츄를 내보냈다! (Lv60)",
        "<@UB>은(는) 꼬부기를 내보냈다! (Lv20)",
    ]
    assert lines[-2].endswith("꼬부기는 쓰러졌다!")
    assert lines[-1] == "<@UA>은(는) 승부에서 이겼다!"
    assert handler(store).handle("UA", "", RECORD_COMMAND).text == "<@UA> 전적: 1승 0패"
    assert handler(store).handle("UA", "<@UB>", RECORD_COMMAND).text == "<@UB> 전적: 0승 1패"


def test_an_older_multi_pokemon_upload_sends_only_its_first(store):
    upload(store, "UA", 7, 5)
    store.save_party("UA", [member(7, 5), member(25, 30), member(7, 10), member(25, 100)])
    upload(store, "UB", 25, 60)
    lines = handler(store).handle("UA", "<@UB>").text.splitlines()
    assert lines[1] == "<@UA>은(는) 꼬부기를 내보냈다! (Lv5)"
    assert lines[2] == "<@UB>은(는) 피카츄를 내보냈다! (Lv60)"
    assert lines[-1] == "<@UB>은(는) 승부에서 이겼다!"
    assert sum(line.endswith("쓰러졌다!") for line in lines) == 1


def battle_moves_of(store, monkeypatch, chosen, level=60):
    captured = []
    monkeypatch.setattr("ypoke.commands.simulate", lambda sides, seed: captured.append(sides) or simulate(sides, seed))
    store.issue_token("UA")
    store.save_party("UA", [{**member(25, level), **({"moves": chosen} if chosen is not None else {})}])
    upload(store, "UB", 7, 20)
    handler(store).handle("UA", "<@UB>")
    return [m.name for m in captured[0][0].moves]


def test_default_moves_are_the_four_most_recently_learned(store, monkeypatch):
    assert battle_moves_of(store, monkeypatch, None) == ["스파크", "아이언테일", "10만볼트", "번개"]
    assert battle_moves_of(store, monkeypatch, None, level=20) == ["전기쇼크", "전광석화", "스파크"]


def test_chosen_moves_are_used_in_order(store, monkeypatch):
    assert battle_moves_of(store, monkeypatch, [85, 84]) == ["10만볼트", "전기쇼크"]


def test_chosen_moves_no_longer_learnable_fall_back_to_defaults(store, monkeypatch):
    assert battle_moves_of(store, monkeypatch, [87], level=40) == ["전광석화", "스파크", "아이언테일", "10만볼트"]
    assert battle_moves_of(store, monkeypatch, [87, 84], level=40) == ["전기쇼크"]


def test_chosen_moves_narrate_by_name(store):
    store.issue_token("UA")
    store.save_party("UA", [{**member(25, 60), "moves": [85]}])
    upload(store, "UB", 7, 20)
    assert "피카츄의 10만볼트!" in handler(store).handle("UA", "<@UB>").text


def test_challenger_without_a_pokemon_is_told_privately(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).handle("UB", "<@UA>")
    assert "아직 내 포켓몬이 YPoke에 없어요" in reply.text
    assert not reply.in_channel


def test_unlinked_opponent_is_named_in_the_channel(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).handle("UA", "<@UC>")
    assert reply.text.startswith("<@UC>님은 아직 YPoke에 앱을 연결하지 않아서 대결할 수 없어요.")
    assert reply.in_channel
    assert store.record("UA") == Record(0, 0)


def test_linked_opponent_without_an_upload_gets_the_egg_and_network_hint(store):
    upload(store, "UA", 25, 60)
    store.issue_token("UC")
    reply = handler(store).handle("UA", "<@UC>")
    assert reply.text.startswith("<@UC>님 앱이 아직 포켓몬을 올리지 않아서 대결할 수 없어요.")
    assert "알이 부화해야" in reply.text
    assert reply.in_channel


def test_cannot_battle_yourself(store):
    upload(store, "UA", 25, 60)
    assert handler(store).handle("UA", "<@UA>").text == "자기 자신과는 대결할 수 없어요."


def test_pokeapi_outage_is_not_recorded(store):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)
    reply = handler(store, fail=True).handle("UA", "<@UB>")
    assert "불러오지 못했어요" in reply.text
    assert store.record("UA").wins + store.record("UA").losses == 0


@pytest.mark.parametrize("text", ["", "help", "@bob", "등록", "전적"])
def test_battle_without_a_mention_shows_help(store, text):
    reply = handler(store).handle("UA", text, BATTLE_COMMAND)
    assert reply.text == HELP_TEXT
    assert reply.direct_message is None


@pytest.mark.parametrize("text", ["", "<@UB>", "등록"])
def test_umbrella_command_only_shows_help(store, text):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)
    reply = handler(store).handle("UA", text, UMBRELLA_COMMAND)
    assert reply.text == HELP_TEXT
    assert store.record("UA") == Record(0, 0)


def test_link_command_sends_the_link_dm(store):
    reply = handler(store).handle("UA", "<@UB>", LINK_COMMAND)
    assert reply.direct_message_blocks[1]["elements"][0]["url"].startswith("poketokenbar://ypoke-register?")
    assert not reply.in_channel


def test_record_command_shows_mentioned_or_own_record(store):
    store.record_battle("UA", "UB", "UA", 1)
    assert handler(store).handle("UA", "", RECORD_COMMAND).text == "<@UA> 전적: 1승 0패"
    assert handler(store).handle("UA", "<@UB|bob>", RECORD_COMMAND).text == "<@UB> 전적: 0승 1패"


def test_help_shows_every_command():
    for command in (BATTLE_COMMAND, LINK_COMMAND, RECORD_COMMAND, RANKING_COMMAND):
        assert f"`{command}" in HELP_TEXT
    assert "등록" not in HELP_TEXT


NOW = datetime(2026, 11, 12, 9, 30, tzinfo=UTC)  # Thursday 18:30 KST
MONDAY_KST_IN_UTC = datetime(2026, 11, 8, 15, 0, tzinfo=UTC)  # Monday 2026-11-09 00:00 KST


@pytest.mark.parametrize("now,expected", [
    (NOW, MONDAY_KST_IN_UTC),
    (MONDAY_KST_IN_UTC, MONDAY_KST_IN_UTC),
    (MONDAY_KST_IN_UTC - timedelta(seconds=1), MONDAY_KST_IN_UTC - timedelta(days=7)),
    (datetime(2026, 11, 15, 14, 59, tzinfo=UTC), MONDAY_KST_IN_UTC),  # Sunday 23:59 KST
])
def test_week_starts_monday_midnight_kst(now, expected):
    assert week_start(now) == expected


def ranking(store):
    return handler(store, now=lambda: NOW).handle("UA", "", RANKING_COMMAND)


def test_ranking_counts_only_battles_since_monday_kst(store):
    store.record_battle("UA", "UB", "UA", 1, at=MONDAY_KST_IN_UTC - timedelta(seconds=1))
    store.record_battle("UA", "UB", "UB", 2, at=MONDAY_KST_IN_UTC)
    reply = ranking(store)
    assert reply.in_channel
    assert reply.text.splitlines()[1:] == ["1. <@UB> 1승 0패 (100%)", "2. <@UA> 0승 1패 (0%)"]


def test_ranking_without_battles_this_week_says_so(store):
    store.record_battle("UA", "UB", "UA", 1, at=MONDAY_KST_IN_UTC - timedelta(days=1))
    reply = ranking(store)
    assert reply.text == "이번 주에는 아직 대결이 없어요."
    assert reply.in_channel


def test_ranking_orders_by_wins_then_win_rate_then_fewer_battles(store):
    at = MONDAY_KST_IN_UTC + timedelta(hours=1)
    for winner, loser, times in [("UA", "UX", 2), ("UB", "UX", 2), ("UX", "UB", 1), ("UC", "UX", 2), ("UC", "UY", 0)]:
        for _ in range(times):
            store.record_battle(winner, loser, winner, 0, at=at)
    store.record_battle("UD", "UY", "UD", 0, at=at)
    store.record_battle("UD", "UY", "UY", 0, at=at)
    store.record_battle("UE", "UY", "UE", 0, at=at)
    lines = ranking(store).text.splitlines()[1:]
    assert lines == [
        "1. <@UA> 2승 0패 (100%)",
        "2. <@UC> 2승 0패 (100%)",
        "3. <@UB> 2승 1패 (67%)",
        "4. <@UE> 1승 0패 (100%)",
        "5. <@UD> 1승 1패 (50%)",
        "6. <@UY> 1승 2패 (33%)",
        "7. <@UX> 1승 6패 (14%)",
    ]


def test_ranking_shows_top_ten(store):
    at = MONDAY_KST_IN_UTC + timedelta(hours=1)
    for index in range(12):
        store.record_battle(f"U{index:02}", "UZ", f"U{index:02}", 0, at=at)
    assert len(ranking(store).text.splitlines()) == 1 + 10


@pytest.mark.parametrize("command,text,mention", [
    (BATTLE_COMMAND, "<@UBOT|ypoke>", False),
    (None, "<@UBOT> 대결", True),
])
def test_bot_battle_is_practice_and_writes_nothing(store, monkeypatch, command, text, mention):
    upload(store, "UA", 25, 42)
    monkeypatch.setattr("ypoke.commands.secrets.randbits", lambda bits: 1234)
    pokeapi = FakePokeAPI()
    bot = handler(store, pokeapi=pokeapi)
    reply = bot.handle_mention("UA", text) if mention else bot.handle("UA", text, command)
    lines = reply.text.splitlines()
    assert reply.in_channel
    assert lines[0] == "<@UBOT>에게 <@UA>이(가) 승부를 걸어왔다!"
    assert lines[2] == "<@UBOT>은(는) 야생몬을 내보냈다! (Lv42)"
    assert lines[-1].endswith("승부에서 이겼다! (연습 대결 — 전적에 안 남아요)")
    assert bot_species(1234) in pokeapi.requested
    assert store.record("UA") == Record(0, 0)
    assert store.records_since(datetime(2000, 1, 1, tzinfo=UTC)) == {}


def test_bot_battle_needs_my_party(store):
    reply = handler(store).handle("UA", "<@UBOT>", BATTLE_COMMAND)
    assert "아직 내 포켓몬이 YPoke에 없어요" in reply.text
    assert not reply.in_channel


@pytest.mark.parametrize("text", ["<@UBOT>", "<@UBOT> 안녕"])
def test_mention_without_a_command_word_shows_help(store, text):
    assert handler(store).handle_mention("UA", text).text == HELP_TEXT


@pytest.mark.parametrize("text,command,rest", [
    ("<@UBOT> 대결 <@UB>", BATTLE_COMMAND, "대결 <@UB>"),
    ("<@UBOT|ypoke> 대결 <@UB|bob>", BATTLE_COMMAND, "대결 <@UB|bob>"),
    ("<@UBOT> 대결 <@UBOT>", BATTLE_COMMAND, "대결"),
    ("<@UBOT> 대결", BATTLE_COMMAND, "대결"),
    ("<@UBOT> Battle", BATTLE_COMMAND, "Battle"),
    ("<@UBOT> 전적 <@UB>", RECORD_COMMAND, "전적 <@UB>"),
    ("<@UBOT> 랭킹", RANKING_COMMAND, "랭킹"),
    ("<@UBOT> 연결", LINK_COMMAND, "연결"),
    ("<@UBOT>", None, ""),
])
def test_parse_mention_strips_the_bot_mention(text, command, rest):
    assert parse_mention(text, "UBOT") == (command, rest)


def test_mention_battle_fights_the_other_person_not_the_bot(store):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)
    reply = handler(store).handle_mention("UA", "<@UBOT> 대결 <@UB>")
    assert reply.text.splitlines()[0] == "<@UB>에게 <@UA>이(가) 승부를 걸어왔다!"
    assert store.record("UA") == Record(1, 0)


def test_mention_battle_with_only_the_bot_mentioned_twice_is_practice(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).handle_mention("UA", "<@UBOT> 대결 <@UBOT>")
    assert reply.text.endswith("(연습 대결 — 전적에 안 남아요)")
    assert store.record("UA") == Record(0, 0)


def test_mention_record_ranking_and_link(store):
    store.record_battle("UA", "UB", "UA", 0, at=NOW)
    bot = handler(store)
    assert bot.handle_mention("UA", "<@UBOT> 전적").text == "<@UA> 전적: 1승 0패"
    assert bot.handle_mention("UA", "<@UBOT> 전적 <@UB>").text == "<@UB> 전적: 0승 1패"
    assert bot.handle_mention("UA", "<@UBOT> 랭킹").text.startswith("🏆 이번 주 랭킹")
    link = bot.handle_mention("UA", "<@UBOT> 연결")
    assert link.direct_message_blocks is not None
    assert not link.in_channel


@pytest.mark.parametrize("event,expected", [
    ({"ts": "1.1"}, "1.1"),
    ({"ts": "2.2", "thread_ts": "1.1"}, "1.1"),
])
def test_reply_thread_ts_stays_in_the_thread(event, expected):
    assert reply_thread_ts(event) == expected


def test_help_links_the_home_channel_when_configured(store):
    bot = CommandHandler(store, FakePokeAPI(), home_channel="CHOME")
    assert bot.handle("UA", "", UMBRELLA_COMMAND).text.endswith("<#CHOME>")
    assert "스레드에서는 `@YPoke 대결 @상대`처럼 멘션으로 불러요." in HELP_TEXT


def test_bot_species_is_seeded_and_spans_the_national_dex():
    picks = [bot_species(seed) for seed in range(400)]
    assert picks == [bot_species(seed) for seed in range(400)]
    assert all(1 <= species <= 1025 for species in picks)
    assert len(set(picks)) > 250


def test_bot_battle_uses_the_first_of_an_older_entry_at_its_level(store, monkeypatch):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 42), member(7, 10)])
    monkeypatch.setattr("ypoke.commands.secrets.randbits", lambda bits: 99)
    lines = handler(store).handle("UA", "<@UBOT>", BATTLE_COMMAND).text.splitlines()
    assert lines[1] == "<@UA>은(는) 피카츄를 내보냈다! (Lv42)"
    assert lines[2] == "<@UBOT>은(는) 야생몬을 내보냈다! (Lv42)"
