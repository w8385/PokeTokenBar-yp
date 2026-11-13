from dataclasses import replace

import pytest

from ypoke import items
from ypoke.battle import (
    AbilityTrigger, Action, BaseStats, BattleResult, Change, Combatant, ItemHeal, MegaEvolution, Move, SendOut,
    StatusDamage, WeatherDamage, WeatherEnd, simulate,
)
from ypoke.narration import (
    MAX_HIGHLIGHTS, MAX_LOG_CHARS, MAX_TURN_LINES, PRACTICE_NOTE, SKIPPED_LINE, battle_card, battle_header, battle_log,
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


def log_for(*events):
    return battle_log(BattleResult(winner=0, turns=len(events), events=list(events)))


def result_for(events, remaining, winner=0, turns=9):
    return BattleResult(winner=winner, turns=turns, events=list(events), remaining=remaining)


@pytest.mark.parametrize("event,expected", [
    (act(1, 0), "1턴 🔵 피카츄 10만볼트 → 꼬부기 100%"),
    (act(1, 0, defender_hp=31, critical=True, multiplier=2.0), "1턴 🔵 피카츄 10만볼트 → 꼬부기 31% 급소 굉장"),
    (act(1, 1, move="물대포", multiplier=0.5, defender_hp=88), "1턴 🔴 꼬부기 물대포 → 피카츄 88% 별로"),
    (act(1, 0, move="번개", missed=True), "1턴 🔵 피카츄 번개 → 빗나감"),
    (act(1, 0, move="몸통박치기", multiplier=0), "1턴 🔵 피카츄 몸통박치기 → 꼬부기 무효"),
    (act(1, 0, move="지진", multiplier=0, ability="levitate"), "1턴 🔵 피카츄 지진 → 꼬부기 무효 [부유]"),
    (act(1, 0, move="지진", ability="sturdy", defender_hp=1), "1턴 🔵 피카츄 지진 → 꼬부기 1% [옹골참]"),
    (act(1, 0, multiplier=2.0, knockout=True, defender_hp=0), "1턴 🔵 피카츄 10만볼트 → 꼬부기 쓰러짐 굉장"),
    (act(1, 0, changes=(Change(1, "꼬부기", "burn"),), defender_hp=50), "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% 🔥화상"),
    (act(1, 0, changes=(Change(1, "꼬부기", "toxic"),), defender_hp=50), "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% ☠️맹독"),
    (act(1, 0, changes=(Change(1, "꼬부기", "paralysis"),), defender_hp=50), "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% ⚡마비"),
    (act(1, 0, changes=(Change(1, "꼬부기", "sleep"),), defender_hp=50), "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% 💤잠듦"),
    (act(1, 0, changes=(Change(1, "꼬부기", "freeze"),), defender_hp=50), "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% 🧊얼음"),
    (act(1, 0, changes=(Change(1, "꼬부기", "confusion"),), defender_hp=50), "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% 💫혼란"),
    (act(1, 0, changes=(Change(1, "꼬부기", "thaw"),), defender_hp=50), "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% 🧊해동"),
    (act(1, 0, changes=(Change(1, "꼬부기", "defense", -1),), defender_hp=50), "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% 방어↓"),
    (act(1, 0, changes=(Change(0, "피카츄", "special_attack", -2),), defender_hp=50),
     "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% 자신 특공↓↓"),
    (act(1, 0, move="기가드레인", drained=True, defender_hp=40), "1턴 🔵 피카츄 기가드레인 → 꼬부기 40% 흡수"),
    (act(1, 0, move="누르기", recoil=True, defender_hp=40), "1턴 🔵 피카츄 누르기 → 꼬부기 40% 반동"),
    (act(1, 0, move="발버둥", recoil=True, attacker_fainted=True, defender_hp=40),
     "1턴 🔵 피카츄 발버둥 → 꼬부기 40% 반동 피카츄 쓰러짐"),
    (act(1, 0, move="연속뺨치기", hits=4, defender_hp=40), "1턴 🔵 피카츄 연속뺨치기 → 꼬부기 40% 4연타"),
    (act(1, 0, attacker_item=items.LIFE_ORB, defender_hp=40), "1턴 🔵 피카츄 10만볼트 → 꼬부기 40% @생명의구슬"),
    (act(1, 0, defender_item=items.FOCUS_SASH, defender_hp=1), "1턴 🔵 피카츄 10만볼트 → 꼬부기 1% @기합의띠"),
    (act(1, 1, move="", blocked="sleep"), "1턴 🔴 꼬부기 💤자는 중"),
    (act(1, 1, move="", blocked="freeze"), "1턴 🔴 꼬부기 🧊얼어서 못 움직임"),
    (act(1, 1, move="", blocked="paralysis", recovered=("sleep",)), "1턴 🔴 꼬부기 💤깸 ⚡몸이 저려 못 움직임"),
    (act(1, 1, move="", blocked="confusion", attacker_hp=63), "1턴 🔴 꼬부기 💫혼란 자해 63%"),
    (act(1, 1, move="", blocked="confusion", attacker_hp=0, attacker_fainted=True), "1턴 🔴 꼬부기 💫혼란 자해 쓰러짐"),
    (act(1, 1, move="물대포", recovered=("freeze",), defender_hp=70), "1턴 🔴 꼬부기 🧊풀림 물대포 → 피카츄 70%"),
    (act(1, 0, move="비바라기", weather="rain"), "1턴 🔵 피카츄 비바라기 ☔"),
    (act(1, 0, move="모래바람", weather="sandstorm"), "1턴 🔵 피카츄 모래바람 🏜️"),
    (act(1, 0, move="비바라기", failed=True), "1턴 🔵 피카츄 비바라기 → 실패"),
    (StatusDamage(3, 1, "꼬부기", 12, False), "3턴 🔴 꼬부기 🔥 12%"),
    (StatusDamage(3, 1, "꼬부기", 0, True, "toxic"), "3턴 🔴 꼬부기 ☠️ 쓰러짐"),
    (WeatherDamage(2, 1, "꼬부기", 80, False, "sandstorm"), "2턴 🔴 꼬부기 🏜️ 80%"),
    (WeatherDamage(2, 0, "피카츄", 0, True, "hail"), "2턴 🔵 피카츄 🌨️ 쓰러짐"),
    (WeatherEnd(5, "rain"), "5턴 ☔끝"),
    (ItemHeal(2, 1, "꼬부기", items.LEFTOVERS, 80), "2턴 🔴 꼬부기 @먹다남은음식 80%"),
])
def test_one_event_makes_one_turn_line(event, expected):
    assert log_for(event) == [expected]


def test_a_turn_is_one_line_with_both_actions_and_the_end_of_turn_effects():
    lines = log_for(
        act(1, 0, defender_hp=50), act(1, 1, move="물대포", defender_hp=90), StatusDamage(1, 1, "꼬부기", 44, False),
        WeatherEnd(1, "rain"), act(2, 0, defender_hp=20),
    )
    assert lines == [
        "1턴 🔵 피카츄 10만볼트 → 꼬부기 50% · 🔴 꼬부기 물대포 → 피카츄 90% · 🔴 꼬부기 🔥 44% · ☔끝",
        "2턴 🔵 피카츄 10만볼트 → 꼬부기 20%",
    ]


def test_a_faint_and_the_send_out_share_the_turn_line():
    lines = log_for(
        act(3, 0, multiplier=2.0, knockout=True, defender_hp=0), SendOut(3, 1, "거북왕"),
        act(4, 1, move="물대포", defender_hp=70),
    )
    assert lines == [
        "3턴 🔵 피카츄 10만볼트 → 꼬부기 쓰러짐 굉장 → 🔴 거북왕",
        "4턴 🔴 꼬부기 물대포 → 피카츄 70%",
    ]


def test_both_sides_sending_out_in_one_turn_are_listed_on_that_line():
    lines = log_for(
        act(2, 0, move="폭발", knockout=True, attacker_fainted=True, defender_hp=0),
        SendOut(2, 0, "이상해씨"), SendOut(2, 1, "거북왕"),
    )
    assert lines == ["2턴 🔵 피카츄 폭발 → 꼬부기 쓰러짐 → 🔵 이상해씨, 🔴 거북왕"]


def test_start_of_battle_abilities_and_mega_join_the_first_turn_line():
    intimidate = AbilityTrigger(0, "피카츄", "intimidate", change=Change(1, "꼬부기", "attack", -1))
    drizzle = AbilityTrigger(1, "꼬부기", "drizzle", weather="rain")
    mega = MegaEvolution(1, 0, "피카츄", "단단한발톱")
    assert log_for(mega, intimidate, drizzle, act(1, 0, defender_hp=80)) == [
        "1턴 🔵 피카츄 메가진화 [단단한발톱] · 🔵 피카츄 [위협] 공격↓ · 🔴 꼬부기 [잔비] ☔ · "
        "🔵 피카츄 10만볼트 → 꼬부기 80%"
    ]


def test_an_ability_or_mega_after_a_send_out_folds_into_that_send_out():
    lines = log_for(
        act(3, 0, knockout=True, defender_hp=0), SendOut(3, 1, "거북왕"),
        AbilityTrigger(1, "거북왕", "intimidate", change=Change(0, "피카츄", "attack", -1)),
        act(4, 0, knockout=True, defender_hp=0), SendOut(4, 1, "리자몽"), MegaEvolution(4, 1, "리자몽", None),
    )
    assert lines == [
        "3턴 🔵 피카츄 10만볼트 → 꼬부기 쓰러짐 → 🔴 거북왕 [위협] 공격↓",
        "4턴 🔵 피카츄 10만볼트 → 꼬부기 쓰러짐 → 🔴 리자몽 메가진화",
    ]


def test_weather_status_and_ability_moments_fold_into_the_turn_lines_of_a_simulated_battle():
    rain = Move("비바라기", None, 0, physical=False, weather="rain")
    burn = Move("화염방사", "fire", 90, physical=False, accuracy=100, ailment="burn", ailment_chance=100)
    sides = (
        (mon("골덕", moves=[rain, burn], ability="intimidate"),),
        (mon("괴력몬", base=(150, 80, 80, 80, 80, 20), moves=[Move("몸통박치기", "normal", 40, True, accuracy=100)]),),
    )
    lines = battle_log(simulate(sides, 3))
    assert lines[0].startswith("1턴 🔵 골덕 [위협] 공격↓ · ")
    text = "\n".join(lines)
    assert "🔥화상" in text and "🔥 " in text
    assert all(line.startswith(f"{number}턴 ") for number, line in enumerate(lines, start=1))


def test_long_battles_keep_the_start_and_the_end():
    lines = log_for(*[act(turn, 0, defender_hp=99) for turn in range(1, 60)])
    assert len(lines) == MAX_TURN_LINES + 1
    assert lines[0].startswith("1턴 ")
    assert lines[MAX_TURN_LINES // 2] == SKIPPED_LINE
    assert lines[-1].startswith("59턴 ")


def test_a_long_log_keeps_every_faint_and_send_out_within_the_limit():
    events = [act(turn, turn % 2, defender_hp=50) for turn in range(1, 41)]
    events.insert(20, act(20, 1, move="물대포", knockout=True, defender_hp=0))
    events.insert(21, SendOut(20, 0, "리자몽"))
    events.insert(31, StatusDamage(30, 1, "꼬부기", 0, True, "burn"))
    lines = log_for(*events)
    assert len("\n".join(lines)) <= MAX_LOG_CHARS
    assert any(line.startswith("20턴 ") and line.endswith("→ 🔵 리자몽") for line in lines)
    assert any(line.startswith("30턴 ") and "🔥 쓰러짐" in line for line in lines)
    assert SKIPPED_LINE in lines


def test_long_lines_shrink_the_kept_ends_until_the_log_fits():
    long_name = "아주아주긴이름의포켓몬" * 3
    events = [Action(turn, 0, long_name, "꼬부기", "아주아주긴이름의기술" * 4, defender_hp=1) for turn in range(1, 80)]
    lines = log_for(*events)
    assert len("\n".join(lines)) <= MAX_LOG_CHARS


def test_the_header_names_the_winner_the_format_and_the_turns():
    one = ((mon("피카츄"),), (mon("꼬부기"),))
    three = ((mon("피카츄"),) * 3, (mon("꼬부기"),) * 3)
    result = BattleResult(winner=1, turns=9)
    assert battle_header(TRAINERS, one, result) == "🏆 <@UB> 승 · 1:1 · 9턴"
    assert battle_header(TRAINERS, three, BattleResult(0, 9)) == "🏆 <@UA> 승 · 3:3 · 9턴"
    assert battle_header(TRAINERS, three, result, practice=True) == f"🏆 <@UB> 승 · 3:3 · 9턴 · {PRACTICE_NOTE}"


def test_the_card_lists_each_lineup_in_order_with_its_fate():
    sides = (
        (mon("골덕", shiny=True), mon("괴력몬", level=30), mon("쥬레곤", item=items.LEFTOVERS)),
        (mon("때때무노", rental=True), mon("이올브"), mon("이브이")),
    )
    result = result_for([], ((0, 0, 72), (0, 0, None)))
    card = battle_card(TRAINERS, sides, result)
    assert card.columns[0].splitlines() == ["🔵 *<@UA>*", "골덕✨ 💥", "괴력몬 Lv30 💥", "쥬레곤 @먹다남은음식 72%"]
    assert card.columns[1].splitlines() == ["🔴 *<@UB>*", "때때무노(대여) 💥", "이올브 💥", "이브이 대기"]


def test_the_card_marks_a_mega_evolved_member_and_a_one_on_one_has_one_line_per_column():
    sides = ((mon("리자몽"),), (mon("꼬부기"),))
    result = result_for([MegaEvolution(1, 0, "리자몽", None)], ((55,), (0,)))
    card = battle_card(("<@UA>", "YPoke"), sides, result)
    assert card.columns == ("🔵 *<@UA>*\n리자몽(메가) 55%", "🔴 *YPoke*\n꼬부기 💥")


def test_highlights_are_the_deciding_knockout_then_super_effective_knockouts_then_crits():
    events = [
        act(2, 0, critical=True, defender_hp=60),
        act(3, 0, move="번개", multiplier=2.0, knockout=True, defender_hp=0),
        SendOut(3, 1, "거북왕"),
        act(5, 0, move="냉동빔", multiplier=2.0, knockout=True, critical=True, defender_hp=0),
        SendOut(5, 1, "어니부기"),
        act(9, 0, move="파도타기", knockout=True, critical=True, defender_hp=0),
    ]
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"),) * 3), result_for(events, ((80,), (0, 0, 0))))
    assert card.highlights == (
        "💥 결정타 🔵 피카츄 파도타기 → 꼬부기 쓰러짐 급소 (9턴)",
        "⚡ 🔵 피카츄 번개 → 꼬부기 쓰러짐 굉장 (3턴)",
        "⚡ 🔵 피카츄 냉동빔 → 꼬부기 쓰러짐 급소 굉장 (5턴)",
    )


def test_highlights_cap_at_three_and_a_crit_without_a_knockout_ranks_below_knockouts():
    events = [act(turn, 0, critical=True, defender_hp=50) for turn in range(1, 6)]
    events.append(act(6, 0, move="번개", multiplier=2.0, knockout=True, defender_hp=0))
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"),)), result_for(events, ((80,), (0,))))
    assert len(card.highlights) == MAX_HIGHLIGHTS
    assert card.highlights[0].startswith("💥 결정타")
    assert all(line.startswith("🎯") for line in card.highlights[1:])
    assert [line.endswith(f"({turn}턴)") for turn, line in enumerate(card.highlights[1:], start=1)] == [True, True]


def test_a_faint_from_burn_can_decide_the_battle_and_ability_and_weather_moments_follow_crits():
    events = [
        AbilityTrigger(0, "피카츄", "drizzle", weather="rain"),
        act(2, 1, move="모래바람", weather="sandstorm"),
        act(3, 0, move="지진", multiplier=0, ability="levitate"),
        StatusDamage(4, 1, "꼬부기", 0, True, "burn"),
    ]
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"),)), result_for(events, ((80,), (0,))))
    assert card.highlights == (
        "💥 결정타 🔴 꼬부기 🔥 쓰러짐 (4턴)",
        "✨ 🔵 피카츄 [잔비] ☔",
        "🔴 꼬부기 모래바람 🏜️ (2턴)",
    )


def test_mega_comes_last_and_no_highlight_means_none():
    events = [MegaEvolution(1, 0, "피카츄", None)]
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"),)), result_for(events, ((80,), (30,))))
    assert card.highlights == ("🌟 🔵 피카츄 메가진화 (1턴)",)
    assert battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"),)), result_for([], ((80,), (30,)))).highlights == ()


def test_a_turn_limit_ending_has_no_deciding_knockout():
    events = [act(1, 0, multiplier=2.0, knockout=True, defender_hp=0), SendOut(1, 1, "거북왕")]
    result = result_for(events, ((80,), (0, 40)))
    card = battle_card(TRAINERS, ((mon("피카츄"),), (mon("꼬부기"), mon("거북왕"))), result)
    assert not any(line.startswith("💥") for line in card.highlights)


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
            mon("골덕", types=["water"], base=(80, 82, 78, 95, 80, 85), moves=[hydro, psychic]),
            mon("괴력몬", types=["fighting"], base=(90, 130, 80, 65, 85, 55), moves=[double_edge]),
            mon("쥬레곤", types=["water"], base=(130, 65, 60, 110, 95, 65), moves=[hydro, thunder]),
        ),
        (
            mon("때때무노", types=["bug"], base=(90, 45, 85, 20, 80, 56), moves=[bug], ability="intimidate"),
            mon("이올브", types=["psychic"], base=(95, 50, 90, 100, 90, 60), moves=[bug, psychic], ability="drizzle"),
            mon("이브이", base=(100, 55, 90, 45, 85, 55), moves=[double_edge, rain]),
        ),
    )


def test_a_seeded_nine_turn_three_on_three_fits_in_a_dozen_lines_beside_a_card_with_both_lineups():
    sides = three_on_three()
    result = simulate(sides, SIMULATED_SEED)
    assert result.turns == 9
    log = battle_log(result)
    assert len(log) <= 12
    assert [line.split(" ", 1)[0] for line in log] == [f"{turn}턴" for turn in range(1, 10)]
    assert sum("→ 🔵" in line or "→ 🔴" in line for line in log) == 4
    card = battle_card(TRAINERS, sides, result)
    assert [column.splitlines()[0] for column in card.columns] == ["🔵 *<@UA>*", "🔴 *<@UB>*"]
    assert [line.split(" ")[0] for line in card.columns[0].splitlines()[1:]] == ["골덕", "괴력몬", "쥬레곤"]
    assert [line.split(" ")[0] for line in card.columns[1].splitlines()[1:]] == ["때때무노", "이올브", "이브이"]
    assert [line.split(" ")[-1] for line in card.columns[1].splitlines()[1:]] == ["💥"] * 3
    assert 1 <= len(card.highlights) <= MAX_HIGHLIGHTS
    assert battle_header(TRAINERS, sides, result) == "🏆 <@UA> 승 · 3:3 · 9턴"


def test_a_one_on_one_simulated_battle_renders_a_card_and_a_log():
    sides = tuple(side[:1] for side in three_on_three())
    result = simulate(sides, 1)
    card = battle_card(TRAINERS, sides, result)
    assert [len(column.splitlines()) for column in card.columns] == [2, 2]
    assert len(battle_log(result)) == result.turns


def test_the_result_records_each_members_final_share_and_unentered_members_as_none():
    strong = mon("강함", level=100, base=(200, 200, 100, 100, 100, 200), moves=[Move("몸통박치기", "normal", 90, True)])
    weak = mon("약함", level=5, base=(20, 20, 20, 20, 20, 1), moves=[Move("몸통박치기", "normal", 40, True)])
    result = simulate(((strong, strong, strong), (weak,)), 1)
    assert result.remaining[1] == (0,)
    assert result.remaining[0][0] is not None and result.remaining[0][1:] == (None, None)
    assert replace(result, remaining=((), ())).remaining == ((), ())
