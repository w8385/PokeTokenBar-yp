from dataclasses import replace

import pytest

from ypoke import items
from ypoke.battle import (
    AbilityTrigger, Action, BaseStats, BattleResult, Change, Combatant, ItemHeal, MegaEvolution, Move, SendOut,
    StatusDamage, WeatherDamage, WeatherEnd, simulate,
)
from ypoke.dex import bar
from ypoke.narration import (
    MAX_LOG_BLOCKS, MAX_TAGS, PRACTICE_NOTE, SKIPPED_MARK, battle_card, battle_header, battle_log,
)

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TRAINERS = ("<@UA>", "<@UB>")


def mon(name, level=50, shiny=False, rental=False, item=None, base=(80, 80, 80, 80, 80, 80), moves=(),
        types=("normal",), **fields):
    return Combatant(name=name, level=level, types=tuple(types), base=BaseStats(*base), ivs=IVS, shiny=shiny,
                     rental=rental, item=item, moves=tuple(moves), **fields)


def act(turn, side, move="10만볼트", **fields):
    attacker, defender = ("피카츄", "꼬부기") if side == 0 else ("꼬부기", "피카츄")
    return Action(turn, side, attacker, defender, move, **fields)


def result_for(events, remaining, winner=0, turns=9):
    return BattleResult(winner=winner, turns=turns, events=list(events), remaining=remaining)


def log_for(*events):
    return battle_log(BattleResult(winner=0, turns=len(events), events=list(events)))


def lines_of(entry):
    """The action lines of a turn text, without its `*N턴*` head."""
    head, *lines = entry.splitlines()
    assert head.startswith("*") and head.endswith("턴*")
    return lines


@pytest.mark.parametrize("event,expected", [
    (act(1, 0), ["🔵 피카츄 › 10만볼트 → 꼬부기 100%"]),
    (act(1, 0, defender_hp=31, critical=True, multiplier=2.0), ["🔵 피카츄 › 10만볼트 → 꼬부기 31% 급소 효과 굉장"]),
    (act(1, 1, move="물대포", multiplier=0.5, defender_hp=88), ["🔴 꼬부기 › 물대포 → 피카츄 88% 효과 별로"]),
    (act(1, 0, move="번개", missed=True), ["🔵 피카츄 › 번개 → 빗나감"]),
    (act(1, 0, move="몸통박치기", multiplier=0), ["🔵 피카츄 › 몸통박치기 → 꼬부기 무효"]),
    (act(1, 0, move="지진", multiplier=0, ability="levitate"), ["🔵 피카츄 › 지진 → 꼬부기 무효 [부유]"]),
    (act(1, 0, move="지진", ability="sturdy", defender_hp=1), ["🔵 피카츄 › 지진 → 꼬부기 1% [옹골참]"]),
    (act(1, 0, multiplier=2.0, knockout=True, defender_hp=0),
     ["🔵 피카츄 › 10만볼트 → 꼬부기 💥 효과 굉장"]),
    (act(1, 0, changes=(Change(1, "꼬부기", "burn"),), defender_hp=50), ["🔵 피카츄 › 10만볼트 → 꼬부기 50% 🔥화상"]),
    (act(1, 0, changes=(Change(1, "꼬부기", "toxic"),), defender_hp=50), ["🔵 피카츄 › 10만볼트 → 꼬부기 50% ☠️맹독"]),
    (act(1, 0, changes=(Change(1, "꼬부기", "paralysis"),), defender_hp=50), ["🔵 피카츄 › 10만볼트 → 꼬부기 50% ⚡마비"]),
    (act(1, 0, changes=(Change(1, "꼬부기", "sleep"),), defender_hp=50), ["🔵 피카츄 › 10만볼트 → 꼬부기 50% 💤잠듦"]),
    (act(1, 0, changes=(Change(1, "꼬부기", "freeze"),), defender_hp=50), ["🔵 피카츄 › 10만볼트 → 꼬부기 50% 🧊얼음"]),
    (act(1, 0, changes=(Change(1, "꼬부기", "confusion"),), defender_hp=50), ["🔵 피카츄 › 10만볼트 → 꼬부기 50% 💫혼란"]),
    (act(1, 0, changes=(Change(1, "꼬부기", "thaw"),), defender_hp=50), ["🔵 피카츄 › 10만볼트 → 꼬부기 50% 🧊해동"]),
    (act(1, 0, changes=(Change(1, "꼬부기", "defense", -1),), defender_hp=50), ["🔵 피카츄 › 10만볼트 → 꼬부기 50% 방어↓"]),
    (act(1, 0, changes=(Change(0, "피카츄", "special_attack", -2),), defender_hp=50),
     ["🔵 피카츄 › 10만볼트 → 꼬부기 50% 자신 특공↓↓"]),
    (act(1, 0, move="기가드레인", drained=True, defender_hp=40), ["🔵 피카츄 › 기가드레인 → 꼬부기 40% 흡수"]),
    (act(1, 0, move="누르기", recoil=True, defender_hp=40), ["🔵 피카츄 › 누르기 → 꼬부기 40% 반동"]),
    (act(1, 0, move="발버둥", recoil=True, attacker_fainted=True, defender_hp=40),
     ["🔵 피카츄 › 발버둥 → 꼬부기 40% 반동", "💥 피카츄 쓰러짐"]),
    (act(1, 0, move="연속뺨치기", hits=4, defender_hp=40), ["🔵 피카츄 › 연속뺨치기 → 꼬부기 40% 4연타"]),
    (act(1, 0, attacker_item=items.LIFE_ORB, defender_hp=40), ["🔵 피카츄 › 10만볼트 → 꼬부기 40% @생명의구슬"]),
    (act(1, 0, defender_item=items.FOCUS_SASH, defender_hp=1), ["🔵 피카츄 › 10만볼트 → 꼬부기 1% @기합의띠"]),
    (act(1, 1, move="", blocked="sleep"), ["🔴 꼬부기 💤자는 중"]),
    (act(1, 1, move="", blocked="freeze"), ["🔴 꼬부기 🧊얼어서 못 움직임"]),
    (act(1, 1, move="", blocked="paralysis", recovered=("sleep",)), ["🔴 꼬부기 💤깸 ⚡몸이 저려 못 움직임"]),
    (act(1, 1, move="", blocked="confusion", attacker_hp=63), ["🔴 꼬부기 💫혼란 자해 63%"]),
    (act(1, 1, move="", blocked="confusion", attacker_hp=0, attacker_fainted=True),
     ["🔴 꼬부기 💫혼란 자해 0%", "💥 꼬부기 쓰러짐"]),
    (act(1, 1, move="물대포", recovered=("freeze",), defender_hp=70), ["🔴 꼬부기 🧊풀림 › 물대포 → 피카츄 70%"]),
    (act(1, 0, move="비바라기", weather="rain"), ["🔵 피카츄 › 비바라기 ☔"]),
    (act(1, 0, move="모래바람", weather="sandstorm"), ["🔵 피카츄 › 모래바람 🏜️"]),
    (act(1, 0, move="비바라기", failed=True), ["🔵 피카츄 › 비바라기 → 실패"]),
    (StatusDamage(1, 1, "꼬부기", 12, False), ["🔴 꼬부기 🔥 12%"]),
    (StatusDamage(1, 1, "꼬부기", 0, True, "toxic"), ["🔴 꼬부기 ☠️ 0%", "💥 꼬부기 쓰러짐"]),
    (WeatherDamage(1, 1, "꼬부기", 80, False, "sandstorm"), ["🔴 꼬부기 🏜️ 80%"]),
    (WeatherDamage(1, 0, "피카츄", 0, True, "hail"), ["🔵 피카츄 🌨️ 0%", "💥 피카츄 쓰러짐"]),
    (WeatherEnd(1, "rain"), ["☔끝"]),
    (ItemHeal(1, 1, "꼬부기", items.LEFTOVERS, 80), ["🔴 꼬부기 @먹다남은음식 80%"]),
    (SendOut(1, 1, "거북왕"), ["↪ 🔴 거북왕 등장"]),
])
def test_one_event_makes_its_own_lines(event, expected):
    assert [lines_of(entry) for entry in log_for(event)] == [expected]


def test_a_hit_shows_at_most_two_tags_most_telling_first():
    hit = act(1, 0, move="누르기", critical=True, multiplier=2.0, recoil=True, hits=2, defender_hp=40)
    assert MAX_TAGS == 2
    assert lines_of(log_for(hit)[0]) == ["🔵 피카츄 › 누르기 → 꼬부기 40% 급소 효과 굉장"]


def test_every_action_has_its_own_line_and_nothing_is_glued_with_a_middle_dot_or_an_arrow_chain():
    [entry] = log_for(
        act(1, 0, defender_hp=50), act(1, 1, move="물대포", defender_hp=90), StatusDamage(1, 1, "꼬부기", 44, False),
        WeatherEnd(1, "rain"),
    )
    assert entry.splitlines() == [
        "*1턴*", "🔵 피카츄 › 10만볼트 → 꼬부기 50%", "🔴 꼬부기 › 물대포 → 피카츄 90%", "🔴 꼬부기 🔥 44%", "☔끝",
    ]
    assert " · " not in entry


def test_each_turn_is_its_own_text_in_order():
    log = log_for(act(1, 0, defender_hp=50), act(2, 0, defender_hp=20))
    assert [entry.splitlines()[0] for entry in log] == ["*1턴*", "*2턴*"]


def test_a_faint_and_the_send_out_are_lines_of_the_turn_they_happened_in():
    log = log_for(
        act(3, 0, multiplier=2.0, knockout=True, defender_hp=0), SendOut(3, 1, "거북왕"),
        act(4, 1, move="물대포", defender_hp=70),
    )
    assert [lines_of(entry) for entry in log] == [
        ["🔵 피카츄 › 10만볼트 → 꼬부기 💥 효과 굉장", "↪ 🔴 거북왕 등장"],
        ["🔴 꼬부기 › 물대포 → 피카츄 70%"],
    ]


def test_both_sides_sending_out_in_one_turn_get_a_line_each():
    [entry] = log_for(
        act(2, 0, move="폭발", knockout=True, attacker_fainted=True, defender_hp=0),
        SendOut(2, 0, "이상해씨"), SendOut(2, 1, "거북왕"),
    )
    assert lines_of(entry) == [
        "🔵 피카츄 › 폭발 → 꼬부기 💥", "💥 피카츄 쓰러짐", "↪ 🔵 이상해씨 등장", "↪ 🔴 거북왕 등장",
    ]


def test_start_of_battle_abilities_and_mega_are_lines_of_the_first_turn():
    intimidate = AbilityTrigger(0, "피카츄", "intimidate", change=Change(1, "꼬부기", "attack", -1))
    drizzle = AbilityTrigger(1, "꼬부기", "drizzle", weather="rain")
    mega = MegaEvolution(1, 0, "피카츄", "단단한발톱")
    [entry] = log_for(mega, intimidate, drizzle, act(1, 0, defender_hp=80))
    assert lines_of(entry) == [
        "🔵 피카츄 메가진화 [단단한발톱]", "🔵 피카츄 [위협] 공격↓", "🔴 꼬부기 [잔비] ☔",
        "🔵 피카츄 › 10만볼트 → 꼬부기 80%",
    ]


def test_an_ability_or_mega_after_a_send_out_joins_that_send_out_line():
    log = log_for(
        act(3, 0, knockout=True, defender_hp=0), SendOut(3, 1, "거북왕"),
        AbilityTrigger(1, "거북왕", "intimidate", change=Change(0, "피카츄", "attack", -1)),
        act(4, 0, knockout=True, defender_hp=0), SendOut(4, 1, "리자몽"), MegaEvolution(4, 1, "리자몽", None),
    )
    assert [lines_of(entry)[-1] for entry in log] == ["↪ 🔴 거북왕 등장 [위협] 공격↓", "↪ 🔴 리자몽 등장 메가진화"]


def test_a_simulated_battle_has_numbered_turn_texts_and_one_action_per_line():
    rain = Move("비바라기", None, 0, physical=False, weather="rain")
    burn = Move("화염방사", "fire", 90, physical=False, accuracy=100, ailment="burn", ailment_chance=100)
    sides = (
        (mon("골덕", moves=[rain, burn], ability="intimidate"),),
        (mon("괴력몬", base=(150, 80, 80, 80, 80, 20), moves=[Move("몸통박치기", "normal", 40, True, accuracy=100)]),),
    )
    log = battle_log(simulate(sides, 3))
    assert lines_of(log[0])[0] == "🔵 골덕 [위협] 공격↓"
    text = "\n".join(log)
    assert "🔥화상" in text and "🔥 " in text
    assert [entry.splitlines()[0] for entry in log] == [f"*{number}턴*" for number in range(1, len(log) + 1)]
    assert " · " not in text


def test_long_battles_keep_the_start_and_the_end_and_say_how_many_turns_were_left_out():
    log = battle_log(
        BattleResult(0, 59, [act(turn, 0, defender_hp=99) for turn in range(1, 60)]), budget=11
    )
    assert len(log) == 11
    assert log[0].startswith("*1턴*") and log[-1].startswith("*59턴*")
    gaps = [entry for entry in log if entry.startswith(SKIPPED_MARK)]
    assert gaps == [f"{SKIPPED_MARK} 49턴 생략"]


def test_a_long_log_keeps_every_faint_and_send_out_and_fits_the_block_budget():
    events = [act(turn, turn % 2, defender_hp=50) for turn in range(1, 41)]
    events.insert(20, act(20, 1, move="물대포", knockout=True, defender_hp=0))
    events.insert(21, SendOut(20, 0, "리자몽"))
    events.insert(31, StatusDamage(30, 1, "꼬부기", 0, True, "burn"))
    log = battle_log(BattleResult(0, 40, events), budget=14)
    assert len(log) <= 14
    text = "\n".join(log)
    assert "*20턴*" in text and "↪ 🔵 리자몽 등장" in text
    assert "*30턴*" in text and "💥 꼬부기 쓰러짐" in text
    assert any(entry.startswith(SKIPPED_MARK) for entry in log)


def test_the_gap_marker_counts_the_turns_between_two_kept_ones():
    events = [act(turn, 0, defender_hp=50) for turn in range(1, 8)]
    events.insert(4, act(4, 1, knockout=True, defender_hp=0))
    log = battle_log(BattleResult(0, 7, events), budget=4)
    assert [entry.splitlines()[0] for entry in log] == ["*1턴*", f"{SKIPPED_MARK} 2턴 생략", "*4턴*", f"{SKIPPED_MARK} 2턴 생략", "*7턴*"]


def test_the_header_names_the_winner_the_format_and_the_turns():
    one = ((mon("피카츄"),), (mon("꼬부기"),))
    three = ((mon("피카츄"),) * 3, (mon("꼬부기"),) * 3)
    result = BattleResult(winner=1, turns=9)
    assert battle_header(TRAINERS, one, result) == "🏆 <@UB> 승 · 1:1 · 9턴"
    assert battle_header(TRAINERS, three, BattleResult(0, 9)) == "🏆 <@UA> 승 · 3:3 · 9턴"
    assert battle_header(TRAINERS, three, result, practice=True) == f"🏆 <@UB> 승 · 3:3 · 9턴 · {PRACTICE_NOTE}"
    card = battle_card(TRAINERS, one, result, practice=True)
    assert (card.title, card.detail, card.practice) == ("🏆 <@UB> 승", "1:1 · 9턴", True)


def test_the_card_lists_each_lineup_in_order_with_a_bar_and_percent_per_member():
    sides = (
        (mon("골덕", shiny=True), mon("괴력몬", level=30), mon("쥬레곤", item=items.LEFTOVERS)),
        (mon("때때무노", rental=True), mon("이올브"), mon("이브이")),
    )
    result = result_for([], ((0, 0, 72), (0, 0, None)))
    card = battle_card(TRAINERS, sides, result)
    assert card.columns[0].splitlines() == [
        "🔵 *<@UA>*", "골덕✨ 💥", "괴력몬 Lv30 💥", f"쥬레곤 @먹다남은음식 {bar(72, 100)} 72%",
    ]
    assert card.columns[1].splitlines() == [
        "🔴 *<@UB>*", "때때무노(대여) 💥", "이올브 💥", "이브이 대기",
    ]


def test_the_bar_follows_the_dex_grid_rule():
    sides = ((mon("피카츄"),) * 3, (mon("꼬부기"),))
    card = battle_card(TRAINERS, sides, result_for([], ((100, 1, 99), (50,))))
    assert [line.split(" ")[1:] for line in card.columns[0].splitlines()[1:]] == [
        ["▰" * 10, "100%"], ["▰▱▱▱▱▱▱▱▱▱", "1%"], ["▰" * 9 + "▱", "99%"],
    ]
    assert card.columns[1].splitlines()[1] == "꼬부기 ▰▰▰▰▰▱▱▱▱▱ 50%"


def test_the_card_marks_a_mega_evolved_member():
    sides = ((mon("리자몽"),), (mon("꼬부기"),))
    result = result_for([MegaEvolution(1, 0, "리자몽", None)], ((55,), (0,)))
    card = battle_card(("<@UA>", "YPoke"), sides, result)
    assert card.columns == (f"🔵 *<@UA>*\n리자몽(메가) {bar(55, 100)} 55%", "🔴 *YPoke*\n꼬부기 💥")


def test_a_one_on_one_has_no_highlight_even_with_a_deciding_knockout():
    events = [act(3, 0, move="번개", multiplier=2.0, knockout=True, defender_hp=0)]
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"),)), result_for(events, ((80,), (0,)), turns=3))
    assert card.highlights == ()


def test_a_full_lineup_keeps_only_the_deciding_knockout_as_a_highlight():
    events = [
        act(2, 0, critical=True, multiplier=2.0, knockout=True, defender_hp=0),
        SendOut(2, 1, "거북왕"),
        act(9, 0, move="파도타기", knockout=True, critical=True, defender_hp=0),
    ]
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"),) * 3), result_for(events, ((80,), (0, 0, 0))))
    assert card.highlights == ("💥 결정타 피카츄 파도타기",)


def test_a_faint_from_burn_can_be_the_deciding_knockout():
    events = [StatusDamage(4, 1, "꼬부기", 0, True, "burn")]
    card = battle_card(TRAINERS, ((mon("피카츄"),) * 2, (mon("꼬부기"),)), result_for(events, ((80, None), (0,))))
    assert card.highlights == ("💥 결정타 꼬부기 🔥",)


def test_a_turn_limit_ending_has_no_deciding_knockout():
    events = [act(1, 0, multiplier=2.0, knockout=True, defender_hp=0), SendOut(1, 1, "거북왕")]
    result = result_for(events, ((80,), (0, 40)))
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"), mon("거북왕"))), result)
    assert card.highlights == ()


def test_the_winners_last_standing_pokemon_is_the_sprite_and_a_shiny_gets_the_shiny_art():
    sides = ((mon("피카츄", pokemon_id=25), mon("꼬부기", pokemon_id=7, shiny=True)), (mon("이브이", pokemon_id=133),))
    card = battle_card(TRAINERS, sides, result_for([], ((0, 40), (0,))))
    url, name = card.sprite
    assert url.endswith("/shiny/7.png") and name == "꼬부기"
    plain = battle_card(TRAINERS, sides, result_for([], ((90, None), (0,))))
    assert plain.sprite[0].endswith("/25.png") and "shiny" not in plain.sprite[0]


def test_no_sprite_without_a_species_id():
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"),)), result_for([], ((80,), (0,))))
    assert card.sprite is None


SIMULATED_SEED = 2


def three_on_three():
    hydro = Move("하이드로펌프", "water", 110, physical=False, accuracy=80)
    psychic = Move("사이코키네시스", "psychic", 90, physical=False, accuracy=100)
    double_edge = Move("이판사판태클", "normal", 120, physical=True, accuracy=100, drain=-33)
    bug = Move("벌레의야단법석", "bug", 90, physical=False, accuracy=100)
    rain = Move("비바라기", None, 0, physical=False, weather="rain")
    thunder = Move("10만볼트", "electric", 90, physical=False, accuracy=100, ailment="paralysis", ailment_chance=30)
    return (
        (
            mon("골덕", types=["water"], base=(80, 82, 78, 95, 80, 85), moves=[hydro, psychic], pokemon_id=55),
            mon("괴력몬", types=["fighting"], base=(90, 130, 80, 65, 85, 55), moves=[double_edge], pokemon_id=68),
            mon("쥬레곤", types=["water"], base=(130, 65, 60, 110, 95, 65), moves=[hydro, thunder], pokemon_id=230),
        ),
        (
            mon("때때무노", types=["bug"], base=(90, 45, 85, 20, 80, 56), moves=[bug], ability="intimidate",
                pokemon_id=265),
            mon("이올브", types=["psychic"], base=(95, 50, 90, 100, 90, 60), moves=[bug, psychic], ability="drizzle",
                pokemon_id=196),
            mon("이브이", base=(100, 55, 90, 45, 85, 55), moves=[double_edge, rain], pokemon_id=133),
        ),
    )


def test_a_seeded_nine_turn_three_on_three_is_a_card_a_decisive_line_and_one_block_per_turn():
    sides = three_on_three()
    result = simulate(sides, SIMULATED_SEED)
    assert result.turns == 9
    card = battle_card(TRAINERS, sides, result)
    assert [entry.splitlines()[0] for entry in card.log] == [f"*{turn}턴*" for turn in range(1, 10)]
    assert all(" · " not in entry for entry in card.log)
    assert [column.splitlines()[0] for column in card.columns] == ["🔵 *<@UA>*", "🔴 *<@UB>*"]
    assert [line.split(" ")[0] for line in card.columns[0].splitlines()[1:]] == ["골덕", "괴력몬", "쥬레곤"]
    assert [line.split(" ")[-1] for line in card.columns[1].splitlines()[1:]] == ["💥"] * 3
    assert len(card.highlights) == 1 and card.highlights[0].startswith("💥 결정타 ")
    assert card.sprite[1] == "쥬레곤"
    assert battle_header(TRAINERS, sides, result) == "🏆 <@UA> 승 · 3:3 · 9턴"


def test_a_one_on_one_simulated_battle_has_a_turn_text_per_turn_and_no_highlight():
    sides = tuple(side[:1] for side in three_on_three())
    result = simulate(sides, 1)
    card = battle_card(TRAINERS, sides, result)
    assert [len(column.splitlines()) for column in card.columns] == [2, 2]
    assert len(card.log) == result.turns
    assert card.highlights == ()


def test_the_result_records_each_members_final_share_and_unentered_members_as_none():
    strong = mon("강함", level=100, base=(200, 200, 100, 100, 100, 200), moves=[Move("몸통박치기", "normal", 90, True)])
    weak = mon("약함", level=5, base=(20, 20, 20, 20, 20, 1), moves=[Move("몸통박치기", "normal", 40, True)])
    result = simulate(((strong, strong, strong), (weak,)), 1)
    assert result.remaining[1] == (0,)
    assert result.remaining[0][0] is not None and result.remaining[0][1:] == (None, None)
    assert replace(result, remaining=((), ())).remaining == ((), ())


def test_a_three_hundred_turn_battle_fits_the_block_budget_keeps_both_ends_and_every_faint():
    events = [act(turn, turn % 2, move="몸통박치기", defender_hp=99) for turn in range(1, 301)]
    for turn in (40, 120, 200, 260):
        events.insert(turn, SendOut(turn, 1, f"교체{turn}"))
        events.insert(turn, act(turn, 0, knockout=True, defender_hp=0))
    log = battle_log(BattleResult(0, 300, events))
    assert len(log) <= MAX_LOG_BLOCKS
    assert log[0].startswith("*1턴*") and log[-1].startswith("*300턴*")
    text = "\n".join(log)
    assert text.count("→ 꼬부기 💥") == 4 and text.count("등장") == 4
    assert any(entry.startswith(SKIPPED_MARK) for entry in log)
