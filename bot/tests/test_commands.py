import re
import sqlite3
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
    Where,
    bot_entry,
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


def move(move_id, name, move_type, power, level, damage_class="special", accuracy=100, priority=0):
    return {"id": move_id, "name": name, "type": move_type, "power": power,
            "damage_class": damage_class, "accuracy": accuracy, "pp": 15, "crit_rate": 0, "priority": priority,
            "ailment": None, "ailment_chance": 0, "stat_changes": [], "stat_target": "target", "stat_chance": 0,
            "drain": 0, "min_hits": 1, "max_hits": 1,
            "weather": None, "always_hits_in": [], "level": level}


MOVES = {
    25: [move(84, "전기쇼크", "electric", 40, 1), move(98, "전광석화", "normal", 40, 1, "physical", priority=1),
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
    button = reply.direct_messages[0].blocks[1]["elements"][0]
    url = urlparse(button["url"])
    assert (url.scheme, url.netloc) == ("poketokenbar", "ypoke-register")
    token = parse_qs(url.query)["token"][0]
    assert store.user_for_token(token) == "U1"
    assert token not in reply.text
    assert token not in reply.direct_messages[0].text
    assert f"`{token}`" in reply.direct_messages[0].blocks[2]["elements"][0]["text"]
    assert "server" not in parse_qs(url.query)


def test_register_link_carries_the_public_server_url(store):
    reply = handler(store, public_url="http://example.local:8790").handle("U1", "", LINK_COMMAND)
    url = urlparse(reply.direct_messages[0].blocks[1]["elements"][0]["url"])
    assert parse_qs(url.query)["server"] == ["http://example.local:8790"]
    assert DOWNLOAD_URL in reply.direct_messages[0].blocks[3]["elements"][0]["text"]


def test_battle_without_a_party_points_to_the_download(store):
    upload(store, "UB", 7, 20)
    assert DOWNLOAD_URL in handler(store).handle("UA", "<@UB>").text


def lineups(reply):
    """Each column's member lines without the HP bar cells."""
    return [[re.sub(r" [▰▱]{10}", "", line) for line in column.splitlines()[1:]] for column in reply.card.columns]


def log_text(reply):
    return "\n".join(reply.card.log)


def test_battle_is_one_on_one_and_records(store):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)
    reply = handler(store).handle("UA", "<@UB|bob>")
    assert reply.in_channel
    assert reply.summary == "🏆 <@UA> 승 · 1:1 · 1턴"
    assert re.fullmatch(r"\*1턴\*\n🔵 피카츄 › 10만볼트 → 꼬부기 💥( 급소)? 효과 굉장", "\n".join(reply.card.log))
    assert reply.text == reply.summary
    assert lineups(reply) == [["피카츄 100%"], ["꼬부기 Lv20 💥"]]
    assert handler(store).handle("UA", "", RECORD_COMMAND).text == "<@UA> 전적: 1승 0패"
    assert handler(store).handle("UA", "<@UB>", RECORD_COMMAND).text == "<@UB> 전적: 0승 1패"


def test_a_three_member_upload_still_fights_one_on_one_by_default(store):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 50), member(7, 10), member(25, 50)])
    store.issue_token("UB")
    store.save_party("UB", [member(7, 20), member(25, 30), member(7, 5)])
    reply = handler(store).handle("UA", "<@UB>")
    assert [len(side) for side in lineups(reply)] == [1, 1]
    assert reply.rematch == "UA:UB:1"
    assert " · 1:1 · " in reply.summary
    assert (store.record("UA").wins, store.record("UA").losses) in ((1, 0), (0, 1))


@pytest.mark.parametrize("word", ["3", "3:3", "풀"])
def test_a_trailing_three_word_asks_for_the_three_member_lineup(store, word):
    store.issue_token("UA")
    store.save_party("UA", [member(7, 5), member(25, 30), member(7, 10), member(25, 100)])
    upload(store, "UB", 25, 60)
    reply = handler(store).handle("UA", f"<@UB> {word}")
    assert [len(side) for side in lineups(reply)] == [3, 1]
    assert lineups(reply)[0][0].startswith("꼬부기 Lv5")
    assert not any("Lv100" in line for line in lineups(reply)[0])
    assert " · 3:1 · " in reply.summary
    assert reply.rematch == "UA:UB:3"


def test_the_three_word_works_before_the_mention_and_in_a_mention_battle(store):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 50)] * 3)
    store.issue_token("UB")
    store.save_party("UB", [member(7, 20)] * 3)
    bot = handler(store)
    assert [len(side) for side in lineups(bot.handle("UA", "3 <@UB>"))] == [3, 3]
    assert [len(side) for side in lineups(bot.handle_mention("UA", "<@UBOT> 대결 <@UB> 3"))] == [3, 3]
    assert [len(side) for side in lineups(bot.handle_mention("UA", "<@UBOT> 대결 <@UB>"))] == [1, 1]


def test_a_number_inside_the_text_without_being_a_word_does_not_widen_the_lineup(store):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 50)] * 3)
    upload(store, "UB", 7, 20)
    assert [len(side) for side in lineups(handler(store).handle("UA", "<@UB> 30"))] == [1, 1]


def test_a_one_member_upload_battles_without_send_outs(store):
    upload(store, "UA", 7, 5)
    upload(store, "UB", 25, 60)
    reply = handler(store).handle("UA", "<@UB> 3")
    assert "등장" not in log_text(reply)
    assert reply.summary.startswith("🏆 <@UB> 승 · 1:1 · ")


def test_three_against_one_ends_when_the_lone_pokemon_is_beaten(store):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 50), member(25, 50), member(25, 50)])
    store.issue_token("UB")
    store.save_party("UB", [member(7, 5)])
    reply = handler(store).handle("UA", "<@UB> 3")
    assert " · 3:1 · " in reply.summary
    assert lineups(reply) == [["피카츄 100%", "피카츄 대기", "피카츄 대기"], ["꼬부기 Lv5 💥"]]
    assert store.record("UA") == Record(1, 0)


def test_one_against_three_lists_the_three_and_the_stronger_side_wins(store):
    store.issue_token("UA")
    store.save_party("UA", [member(7, 1)])
    store.issue_token("UB")
    store.save_party("UB", [member(25, 50), member(7, 50), member(25, 50)])
    reply = handler(store).handle("UA", "<@UB> 3")
    assert " · 1:3 · " in reply.summary
    assert lineups(reply) == [["꼬부기 Lv1 💥"], ["피카츄 100%", "꼬부기 대기", "피카츄 대기"]]
    assert store.record("UB") == Record(1, 0)


def battle_moves_of(store, monkeypatch, chosen, level=60):
    captured = []
    monkeypatch.setattr("ypoke.commands.simulate", lambda sides, seed: captured.append(sides) or simulate(sides, seed))
    store.issue_token("UA")
    store.save_party("UA", [{**member(25, level), **({"moves": chosen} if chosen is not None else {})}])
    upload(store, "UB", 7, 20)
    handler(store).handle("UA", "<@UB>")
    return [m.name for m in captured[0][0][0].moves]


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
    assert "피카츄 › 10만볼트 →" in log_text(handler(store).handle("UA", "<@UB>"))


def test_challenger_without_a_pokemon_is_told_privately(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).handle("UB", "<@UA>")
    assert "아직 내 포켓몬이 YPoke에 없어요" in reply.text
    assert not reply.in_channel


CHANNEL = Where("CCHAN", "1.1", "https://hooks.example/respond")


class Clock:
    def __init__(self):
        self.now = NOW

    def __call__(self):
        return self.now


def pending(store):
    """Every stored pending challenge; a far-past `since` keeps expired rows too."""
    since = datetime(2000, 1, 1, tzinfo=UTC)
    return list({challenge for user in ("UA", "UB") for challenge in store.pending_for(user, since)})


def test_a_battle_stores_both_lead_species_and_the_turn_count(store):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)
    reply = handler(store).handle("UA", "<@UB>")
    (mine,) = store.recent_battles("UA", 5)
    (theirs,) = store.recent_battles("UB", 5)
    assert (mine.my_pokemon_id, mine.opponent_pokemon_id, mine.opponent_id) == (25, 7, "UB")
    assert (theirs.my_pokemon_id, theirs.opponent_pokemon_id, theirs.opponent_id) == (7, 25, "UA")
    assert mine.won != theirs.won
    assert f" · {mine.turns}턴" in reply.summary


def test_a_rental_fights_at_the_opponents_level_and_counts(store):
    upload(store, "UA", 25, 60)
    store.issue_token("UB")
    store.save_party("UB", [{**member(1, 5), "rental": True}])
    reply = handler(store).handle("UA", "<@UB>")
    assert lineups(reply)[1] == ["야생몬(대여) 💥"]
    assert store.record("UA").wins + store.record("UA").losses == 1


def test_a_rental_against_a_lead_above_fifty_fights_at_fifty(store):
    upload(store, "UA", 25, 80)
    store.issue_token("UB")
    store.save_party("UB", [{**member(1, 5), "rental": True}])
    reply = handler(store).handle("UA", "<@UB>")
    assert all("Lv" not in side[0] for side in lineups(reply))
    assert [side[0].split()[0] for side in lineups(reply)] == ["피카츄", "야생몬(대여)"]


def test_a_rental_against_a_lead_below_fifty_keeps_that_level(store):
    upload(store, "UA", 25, 30)
    store.issue_token("UB")
    store.save_party("UB", [{**member(1, 5), "rental": True}])
    assert lineups(handler(store).handle("UA", "<@UB>"))[1][0].startswith("야생몬(대여) Lv30")


def sides_of(store, monkeypatch, challenger, opponent):
    captured = []
    monkeypatch.setattr("ypoke.commands.simulate", lambda sides, seed: captured.append(sides) or simulate(sides, seed))
    for user, party in (("UA", challenger), ("UB", opponent)):
        store.issue_token(user)
        store.save_party(user, [party])
    handler(store).handle("UA", "<@UB>")
    return captured[0][0][0], captured[0][1][0]


def test_a_fighter_above_fifty_fights_at_fifty_and_one_at_thirty_keeps_its_level(store, monkeypatch):
    high, low = sides_of(store, monkeypatch, member(25, 67), member(7, 30))
    assert (high.level, low.level) == (50, 30)


def test_moves_come_from_the_real_level_not_the_battle_level(store, monkeypatch):
    high, _ = sides_of(store, monkeypatch, {**member(25, 100), "moves": [87]}, member(7, 30))
    assert [m.name for m in high.moves] == ["번개"]


def test_the_uploaded_nature_reaches_the_combatant_and_unknown_ones_are_kept_for_neutral(store, monkeypatch):
    first, second = sides_of(store, monkeypatch, {**member(25, 30), "nature": "adamant"}, member(7, 30))
    assert (first.nature, second.nature) == ("adamant", None)


def test_the_uploaded_ability_reaches_the_combatant_and_a_member_without_one_has_none(store, monkeypatch):
    first, second = sides_of(store, monkeypatch, {**member(25, 30), "ability": "static"}, member(7, 30))
    assert (first.ability, second.ability) == ("static", None)


def test_a_rental_challenger_against_a_rental_keeps_both_levels(store):
    for user in ("UA", "UB"):
        store.issue_token(user)
        store.save_party(user, [{**member(7, 5), "rental": True}])
    first, second = lineups(handler(store).handle("UA", "<@UB>"))
    assert first[0].startswith("꼬부기(대여) Lv5")
    assert second[0].startswith("꼬부기(대여) Lv5")


def test_practice_with_a_rental_uses_the_same_level_on_both_sides(store):
    store.issue_token("UA")
    store.save_party("UA", [{**member(7, 5), "rental": True}])
    first, second = lineups(handler(store).handle("UA", "<@UBOT>"))
    assert first[0].startswith("꼬부기(대여) Lv5")
    assert second[0].startswith("야생몬 Lv5")


def test_unlinked_opponent_gets_one_link_dm_and_the_challenge_waits(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL)
    assert reply.in_channel
    assert reply.text.startswith("<@UB>님은 아직 YPoke에 포켓몬이 없어서 연결 안내를 DM으로 보냈어요.")
    [dm] = reply.direct_messages
    assert dm.user_id == "UB"
    assert dm.blocks[0]["text"]["text"] == "<@UA>님이 YPoke 대결을 신청했어요."
    token = parse_qs(urlparse(dm.blocks[2]["elements"][0]["url"]).query)["token"][0]
    assert store.user_for_token(token) == "UB"
    assert "회사 네트워크" in dm.blocks[-1]["elements"][0]["text"]
    [challenge] = pending(store)
    assert (challenge.challenger_id, challenge.opponent_id, challenge.channel_id, challenge.thread_ts) == (
        "UA", "UB", "CCHAN", "1.1")
    assert store.record("UA") == Record(0, 0)


def test_one_pending_row_per_pair_and_one_dm_per_day(store):
    upload(store, "UA", 25, 60)
    upload(store, "UC", 7, 20)
    clock = Clock()
    bot = handler(store, now=clock)
    assert len(bot.handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL).direct_messages) == 1
    clock.now += timedelta(hours=1)
    again = bot.handle("UA", "<@UB>", BATTLE_COMMAND, Where("COTHER"))
    assert again.direct_messages == ()
    assert again.in_channel
    assert bot.handle("UC", "<@UB>", BATTLE_COMMAND, CHANNEL).direct_messages == ()
    assert [(c.challenger_id, c.channel_id) for c in store.pending_for("UB", since=NOW)] == [
        ("UA", "COTHER"), ("UC", "CCHAN")]
    clock.now = NOW + timedelta(hours=24, minutes=1)
    assert len(bot.handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL).direct_messages) == 1


def test_linked_opponent_without_an_upload_keeps_their_old_token(store):
    upload(store, "UA", 25, 60)
    old = store.issue_token("UB")
    [dm] = handler(store).handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL).direct_messages
    assert dm.user_id == "UB"
    assert store.user_for_token(old) == "UB"


def test_the_first_upload_runs_the_pending_battle_once(store):
    upload(store, "UA", 25, 60)
    clock = Clock()
    bot = handler(store, now=clock)
    bot.handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL)
    clock.now += timedelta(minutes=10)
    upload(store, "UB", 7, 20)
    [delivery] = bot.run_pending("UB")
    assert delivery.challenger_id == "UA"
    assert delivery.where == CHANNEL
    assert delivery.reply.card.note == "기다리던 포켓몬이 올라와서 대결을 시작해요!"
    assert delivery.reply.summary.startswith("🏆 <@UA> 승 · 1:1")
    assert store.record("UA") == Record(1, 0)
    assert bot.run_pending("UB") == []
    assert bot.run_pending("UA") == []
    assert store.record("UA") == Record(1, 0)


def test_a_late_upload_posts_in_the_channel_not_the_stale_response_url(store):
    upload(store, "UA", 25, 60)
    clock = Clock()
    bot = handler(store, now=clock)
    bot.handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL)
    clock.now += timedelta(hours=2)
    upload(store, "UB", 7, 20)
    [delivery] = bot.run_pending("UB")
    assert delivery.where == Where("CCHAN", "1.1", None)


def test_a_pending_challenge_expires_after_a_day(store):
    upload(store, "UA", 25, 60)
    clock = Clock()
    bot = handler(store, now=clock)
    bot.handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL)
    clock.now += timedelta(hours=24, seconds=1)
    upload(store, "UB", 7, 20)
    assert bot.run_pending("UB") == []
    assert pending(store) == []
    assert store.record("UA") == Record(0, 0)


def test_the_pending_battle_waits_while_pokeapi_is_down(store):
    upload(store, "UA", 25, 60)
    handler(store).handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL)
    upload(store, "UB", 7, 20)
    assert handler(store, fail=True).run_pending("UB") == []
    assert len(handler(store).run_pending("UB")) == 1


def test_a_challenger_without_an_upload_is_told_privately_and_the_challenge_waits(store):
    upload(store, "UB", 7, 20)
    reply = handler(store).handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL)
    assert not reply.in_channel
    assert reply.text.startswith("아직 내 포켓몬이 YPoke에 없어요.")
    assert "<@UB>과(와)의 대결" in reply.text
    [dm] = reply.direct_messages
    assert dm.user_id == "UA"
    assert dm.blocks[0]["text"]["text"] == "<@UB>과(와)의 대결이 기다리고 있어요."
    upload(store, "UA", 25, 60)
    [delivery] = handler(store).run_pending("UA")
    assert delivery.reply.summary.startswith("🏆 ")


def test_a_waiting_three_member_challenge_keeps_its_size_and_a_default_one_stays_one_on_one(store):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 50)] * 3)
    bot = handler(store)
    bot.handle("UA", "<@UB> 3", BATTLE_COMMAND, CHANNEL)
    bot.handle("UA", "<@UC>", BATTLE_COMMAND, CHANNEL)
    assert {(c.opponent_id, c.size) for c in pending(store)} == {("UB", 3), ("UC", 1)}
    for user in ("UB", "UC"):
        store.issue_token(user)
        store.save_party(user, [member(7, 20)] * 3)
    [full] = bot.run_pending("UB")
    [single] = bot.run_pending("UC")
    assert [len(side) for side in lineups(full.reply)] == [3, 3]
    assert [len(side) for side in lineups(single.reply)] == [1, 1]
    assert (full.reply.rematch, single.reply.rematch) == ("UA:UB:3", "UA:UC:1")


def test_a_challenge_saved_before_the_size_column_existed_loads_as_one_on_one(tmp_path):
    path = str(tmp_path / "old.sqlite3")
    Store(path)
    with sqlite3.connect(path) as connection:
        connection.execute("ALTER TABLE pending_challenges DROP COLUMN size")
        connection.execute(
            "INSERT INTO pending_challenges (challenger_id, opponent_id, channel_id, thread_ts, response_url, "
            "created_at) VALUES ('UA', 'UB', 'CCHAN', '1.1', NULL, ?)", (NOW.isoformat(),))
    reopened = Store(path)
    [challenge] = reopened.pending_for("UB", NOW - timedelta(hours=1))
    assert challenge.size == 1


def test_when_neither_side_has_uploaded_both_get_a_dm_and_only_the_challenger_is_told(store):
    reply = handler(store).handle("UA", "<@UB>", BATTLE_COMMAND, CHANNEL)
    assert not reply.in_channel
    assert "<@UB>님도 아직 준비 전이라" in reply.text
    assert [dm.user_id for dm in reply.direct_messages] == ["UA", "UB"]
    upload(store, "UA", 25, 60)
    assert handler(store).run_pending("UA") == []
    upload(store, "UB", 7, 20)
    assert len(handler(store).run_pending("UB")) == 1


def test_practice_without_an_upload_waits_and_runs_on_the_first_upload(store, monkeypatch):
    reply = handler(store).handle("UA", "<@UBOT>", BATTLE_COMMAND, CHANNEL)
    assert not reply.in_channel
    [dm] = reply.direct_messages
    assert dm.blocks[0]["text"]["text"] == "<@UBOT>과(와)의 대결이 기다리고 있어요."
    upload(store, "UA", 25, 42)
    monkeypatch.setattr("ypoke.commands.secrets.randbits", lambda bits: 1234)
    [delivery] = handler(store).run_pending("UA")
    assert delivery.reply.summary.endswith(" · 연습 대결")
    assert store.records_since(datetime(2000, 1, 1, tzinfo=UTC)) == {}


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
    assert reply.direct_messages == ()


@pytest.mark.parametrize("text", ["", "<@UB>", "등록"])
def test_umbrella_command_only_shows_help(store, text):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)
    reply = handler(store).handle("UA", text, UMBRELLA_COMMAND)
    assert reply.text == HELP_TEXT
    assert store.record("UA") == Record(0, 0)


def test_link_command_sends_the_link_dm(store):
    reply = handler(store).handle("UA", "<@UB>", LINK_COMMAND)
    assert reply.direct_messages[0].blocks[1]["elements"][0]["url"].startswith("poketokenbar://ypoke-register?")
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
    assert reply.in_channel
    assert re.fullmatch(r"🏆 <@\w+> 승 · 1:1 · \d+턴 · 연습 대결", reply.summary)
    assert lineups(reply)[1][0].startswith("야생몬 Lv42")
    assert reply.card.columns[1].startswith("🔴 *<@UBOT>*")
    assert bot_entry(1234, 1)[0] in pokeapi.requested
    assert store.record("UA") == Record(0, 0)
    assert store.records_since(datetime(2000, 1, 1, tzinfo=UTC)) == {}


def test_practice_is_one_on_one_by_default_even_with_three_picks(store):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 42), member(7, 10), member(25, 70)])
    reply = handler(store).handle("UA", "<@UBOT>", BATTLE_COMMAND)
    assert [len(side) for side in lineups(reply)] == [1, 1]
    assert reply.rematch == "UA:UBOT:1"


def test_the_help_lists_the_three_member_option():
    assert "`/대결 @상대 3`" in HELP_TEXT
    assert "1:1" in HELP_TEXT


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
    assert reply.card.columns[1].startswith("🔴 *<@UB>*")
    assert store.record("UA") == Record(1, 0)


def test_mention_battle_with_only_the_bot_mentioned_twice_is_practice(store):
    upload(store, "UA", 25, 60)
    reply = handler(store).handle_mention("UA", "<@UBOT> 대결 <@UBOT>")
    assert reply.summary.endswith(" · 연습 대결")
    assert store.record("UA") == Record(0, 0)


def test_mention_record_ranking_and_link(store):
    store.record_battle("UA", "UB", "UA", 0, at=NOW)
    bot = handler(store)
    assert bot.handle_mention("UA", "<@UBOT> 전적").text == "<@UA> 전적: 1승 0패"
    assert bot.handle_mention("UA", "<@UBOT> 전적 <@UB>").text == "<@UB> 전적: 0승 1패"
    assert bot.handle_mention("UA", "<@UBOT> 랭킹").text.startswith("🏆 이번 주 랭킹")
    link = bot.handle_mention("UA", "<@UBOT> 연결")
    assert link.direct_messages[0].blocks is not None
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


def test_bot_entry_is_seeded_distinct_and_spans_the_national_dex():
    picks = [bot_entry(seed, 3) for seed in range(400)]
    assert picks == [bot_entry(seed, 3) for seed in range(400)]
    assert all(1 <= species <= 1025 and len(set(entry)) == 3 for entry in picks for species in entry)
    assert len({entry[0] for entry in picks}) > 250


def test_bot_practice_brings_as_many_random_pokemon_as_the_challenger_at_each_level(store, monkeypatch):
    store.issue_token("UA")
    store.save_party("UA", [member(25, 42), member(7, 10), member(25, 70), member(7, 99)])
    monkeypatch.setattr("ypoke.commands.secrets.randbits", lambda bits: 99)
    pokeapi = FakePokeAPI()
    reply = handler(store, pokeapi=pokeapi).handle("UA", "<@UBOT> 3", BATTLE_COMMAND)
    assert [len(side) for side in lineups(reply)] == [3, 3]
    assert lineups(reply)[0][0].startswith("피카츄 Lv42")
    assert [line.split()[0:2] for line in lineups(reply)[1]][0] == ["야생몬", "Lv42"]
    assert set(bot_entry(99, 3)) <= set(pokeapi.requested)
    assert store.record("UA") == Record(0, 0)
