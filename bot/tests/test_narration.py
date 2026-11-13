from dataclasses import replace

import pytest

from ypoke.battle import (
    AbilityTrigger, Action, BaseStats, BattleResult, Change, Combatant, Move, StatusDamage, WeatherDamage,
    WeatherEnd, simulate,
)
from ypoke.narration import MAX_EVENT_LINES, PRACTICE_NOTE, SKIPPED_LINE, battle_lines, with_particle

IVS = BaseStats(15, 15, 15, 15, 15, 15)
THUNDERBOLT = Move("10만볼트", "electric", 90, physical=False, accuracy=100, ailment="paralysis", ailment_chance=10)
WATER_GUN = Move("물대포", "water", 40, physical=False, accuracy=100)
TRAINERS = ("<@UA>", "<@UB>")


def mon(name, types=("normal",), level=50, shiny=False, moves=()):
    return Combatant(name=name, level=level, types=tuple(types), base=BaseStats(80, 80, 80, 80, 80, 80),
                     ivs=IVS, shiny=shiny, moves=tuple(moves))


@pytest.mark.parametrize("word,pair,expected", [
    ("피카츄", ("을", "를"), "피카츄를"),
    ("리자몽", ("을", "를"), "리자몽을"),
    ("이상해꽃", ("은", "는"), "이상해꽃은"),
    ("꼬부기", ("은", "는"), "꼬부기는"),
    ("뮤", ("이", "가"), "뮤가"),
    ("Pikachu", ("을", "를"), "Pikachu을(를)"),
    ("포리곤2", ("은", "는"), "포리곤2은(는)"),
    ("", ("이", "가"), "이(가)"),
])
def test_particle_follows_the_final_consonant_or_falls_back(word, pair, expected):
    assert with_particle(word, pair) == expected


def act(turn, side, move="10만볼트", **fields):
    attacker, defender = ("피카츄", "꼬부기") if side == 0 else ("꼬부기", "피카츄")
    return Action(turn, side, attacker, defender, move, **fields)


def lines_for(*events, winner=0, practice=False):
    return battle_lines(TRAINERS, (mon("피카츄", shiny=True), mon("꼬부기", level=20)),
                        BattleResult(winner=winner, turns=len(events), events=list(events)), practice)


def test_every_action_gets_a_turn_line_with_its_details():
    lines = lines_for(
        act(1, 0, multiplier=2.0, critical=True, changes=(Change(1, "꼬부기", "paralysis"),), defender_hp=31),
        act(1, 1, move="물대포", multiplier=0.5, defender_hp=88),
        act(2, 1, move="", blocked="paralysis"),
        act(2, 0, multiplier=2.0, knockout=True, defender_hp=0),
    )
    assert lines == [
        "<@UB>에게 <@UA>이(가) 승부를 걸어왔다!",
        "<@UA>은(는) 피카츄를 내보냈다! (Lv50 ✨)",
        "<@UB>은(는) 꼬부기를 내보냈다! (Lv20)",
        "1턴 🔵 피카츄의 10만볼트! 급소에 맞았다! 효과가 굉장했다! 꼬부기는 마비되어 기술이 나오기 어려워졌다! (꼬부기 HP 31%)",
        "1턴 🔴 꼬부기의 물대포! 효과가 별로인 듯하다… (피카츄 HP 88%)",
        "2턴 🔴 꼬부기는 몸이 저려서 움직일 수 없다!",
        "2턴 🔵 피카츄의 10만볼트! 효과가 굉장했다! 꼬부기는 쓰러졌다!",
        "<@UA>은(는) 승부에서 이겼다!",
    ]


@pytest.mark.parametrize("event,expected", [
    (act(1, 0, move="번개", missed=True), "1턴 🔵 피카츄의 번개! 하지만 빗나갔다!"),
    (act(1, 0, move="몸통박치기", multiplier=0), "1턴 🔵 피카츄의 몸통박치기! 꼬부기에게는 효과가 없는 것 같다…"),
    (act(1, 0, changes=(Change(1, "꼬부기", "burn"),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 꼬부기는 화상을 입었다! (꼬부기 HP 50%)"),
    (act(1, 0, changes=(Change(1, "꼬부기", "defense", -1),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 꼬부기의 방어가 떨어졌다! (꼬부기 HP 50%)"),
    (act(1, 0, changes=(Change(0, "피카츄", "special_attack", -2),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 피카츄의 특수공격이 크게 떨어졌다! (꼬부기 HP 50%)"),
    (act(1, 0, changes=(Change(0, "피카츄", "speed", 1),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 피카츄의 스피드가 올랐다! (꼬부기 HP 50%)"),
    (act(1, 0, move="발버둥", recoil=True, attacker_fainted=True, defender_hp=40),
     "1턴 🔵 피카츄의 발버둥! 피카츄는 반동으로 데미지를 입었다! 피카츄는 쓰러졌다!"),
    (act(1, 0, changes=(Change(1, "꼬부기", "poison"),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 꼬부기는 독에 걸렸다! (꼬부기 HP 50%)"),
    (act(1, 0, changes=(Change(1, "꼬부기", "toxic"),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 꼬부기는 맹독에 걸렸다! (꼬부기 HP 50%)"),
    (act(1, 0, changes=(Change(1, "꼬부기", "sleep"),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 꼬부기는 잠들어 버렸다! (꼬부기 HP 50%)"),
    (act(1, 0, changes=(Change(1, "꼬부기", "freeze"),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 꼬부기는 얼어붙었다! (꼬부기 HP 50%)"),
    (act(1, 0, changes=(Change(1, "꼬부기", "confusion"),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 꼬부기는 혼란에 빠졌다! (꼬부기 HP 50%)"),
    (act(1, 0, changes=(Change(1, "꼬부기", "thaw"),), defender_hp=50),
     "1턴 🔵 피카츄의 10만볼트! 꼬부기의 얼음이 녹았다! (꼬부기 HP 50%)"),
    (act(1, 0, move="기가드레인", drained=True, defender_hp=40),
     "1턴 🔵 피카츄의 기가드레인! 꼬부기에게서 체력을 흡수했다! (꼬부기 HP 40%)"),
    (act(1, 0, move="누르기", recoil=True, defender_hp=40),
     "1턴 🔵 피카츄의 누르기! 피카츄는 반동으로 데미지를 입었다! (꼬부기 HP 40%)"),
    (act(1, 0, move="연속뺨치기", hits=4, defender_hp=40),
     "1턴 🔵 피카츄의 연속뺨치기! 4번 맞았다! (꼬부기 HP 40%)"),
    (act(1, 0, move="연속뺨치기", hits=1, defender_hp=40), "1턴 🔵 피카츄의 연속뺨치기! (꼬부기 HP 40%)"),
    (act(1, 1, move="", blocked="sleep"), "1턴 🔴 꼬부기는 쿨쿨 잠들어 있다!"),
    (act(1, 1, move="", blocked="freeze"), "1턴 🔴 꼬부기는 얼어서 움직일 수 없다!"),
    (act(1, 1, move="", blocked="confusion", attacker_hp=63), "1턴 🔴 꼬부기는 혼란에 빠져 자신을 공격했다! (꼬부기 HP 63%)"),
    (act(1, 1, move="", blocked="confusion", attacker_hp=0, attacker_fainted=True),
     "1턴 🔴 꼬부기는 혼란에 빠져 자신을 공격했다! 꼬부기는 쓰러졌다!"),
    (act(1, 1, move="물대포", recovered=("sleep",), defender_hp=70),
     "1턴 🔴 꼬부기는 눈을 떴다! 꼬부기의 물대포! (피카츄 HP 70%)"),
    (act(1, 1, move="", blocked="paralysis", recovered=("sleep", "confusion")),
     "1턴 🔴 꼬부기는 눈을 떴다! 꼬부기의 혼란이 풀렸다! 꼬부기는 몸이 저려서 움직일 수 없다!"),
    (act(1, 1, move="물대포", recovered=("freeze",), defender_hp=70),
     "1턴 🔴 꼬부기의 얼음이 녹았다! 꼬부기의 물대포! (피카츄 HP 70%)"),
    (StatusDamage(3, 1, "꼬부기", 12, False), "3턴 🔴 꼬부기는 화상 데미지를 입었다! (HP 12%)"),
    (StatusDamage(3, 1, "꼬부기", 30, False, "poison"), "3턴 🔴 꼬부기는 독 데미지를 입었다! (HP 30%)"),
    (StatusDamage(3, 1, "꼬부기", 0, True, "toxic"), "3턴 🔴 꼬부기는 독 데미지를 입었다! 꼬부기는 쓰러졌다!"),
    (StatusDamage(3, 1, "꼬부기", 0, True), "3턴 🔴 꼬부기는 화상 데미지를 입었다! 꼬부기는 쓰러졌다!"),
    (act(1, 0, move="비바라기", weather="rain"), "1턴 🔵 피카츄의 비바라기! 비가 내리기 시작했다!"),
    (act(1, 0, move="모래바람", weather="sandstorm"), "1턴 🔵 피카츄의 모래바람! 모래바람이 불기 시작했다!"),
    (act(1, 0, move="비바라기", failed=True), "1턴 🔵 피카츄의 비바라기! 하지만 실패했다!"),
    (WeatherDamage(2, 1, "꼬부기", 80, False, "sandstorm"), "2턴 🔴 꼬부기는 모래바람에 휩싸였다! (HP 80%)"),
    (WeatherDamage(2, 0, "피카츄", 0, True, "hail"), "2턴 🔵 피카츄는 싸라기눈에 맞았다! 피카츄는 쓰러졌다!"),
    (WeatherEnd(5, "rain"), "5턴 비가 그쳤다!"),
    (WeatherEnd(5, "sun"), "5턴 햇살이 원래대로 돌아왔다!"),
])
def test_event_lines(event, expected):
    assert lines_for(event)[3] == expected


def test_long_battles_keep_the_start_and_the_end():
    events = [act(turn, 0, defender_hp=99) for turn in range(1, 40)]
    lines = lines_for(*events)
    assert len(lines) == 3 + MAX_EVENT_LINES + 1 + 1
    assert lines[3].startswith("1턴 ")
    assert lines[3 + MAX_EVENT_LINES // 2] == SKIPPED_LINE
    assert lines[-2].startswith("39턴 ")


def test_practice_battle_says_so_on_the_last_line():
    assert lines_for(practice=True)[-1] == f"<@UA>은(는) 승부에서 이겼다! {PRACTICE_NOTE}"


def test_a_simulated_battle_narrates_from_send_out_to_knockout():
    sides = (mon("피카츄", ["electric"], level=40, moves=[THUNDERBOLT]), mon("꼬부기", ["water"], level=40, moves=[WATER_GUN]))
    first = battle_lines(TRAINERS, sides, simulate(sides, 9))
    assert first == battle_lines(TRAINERS, sides, simulate(sides, 9))
    assert first[-2].endswith("꼬부기는 쓰러졌다!")
    assert all(line.split(" ", 2)[2].startswith(("피카츄의 10만볼트!", "꼬부기의 물대포!", "꼬부기는 몸이 저려서"))
               for line in first[3:-1])


def test_long_status_battles_still_collapse_the_middle_turns():
    events = []
    for turn in range(1, 20):
        events += [act(turn, 1, move="", blocked="sleep"), StatusDamage(turn, 1, "꼬부기", 90 - turn, False, "toxic")]
    lines = lines_for(*events)
    assert len(lines) == 3 + MAX_EVENT_LINES + 1 + 1
    assert lines[3 + MAX_EVENT_LINES // 2] == SKIPPED_LINE
    assert lines[3].endswith("쿨쿨 잠들어 있다!") and lines[-2].startswith("19턴 ")


def test_an_entry_ability_is_narrated_without_a_turn_number():
    intimidate = AbilityTrigger(0, "피카츄", "intimidate", change=Change(1, "꼬부기", "attack", -1))
    drizzle = AbilityTrigger(1, "꼬부기", "drizzle", weather="rain")
    assert lines_for(intimidate, drizzle)[3:5] == [
        "🔵 피카츄의 위협! 꼬부기의 공격이 떨어졌다!",
        "🔴 꼬부기의 잔비! 비가 내리기 시작했다!",
    ]


def test_levitate_and_sturdy_are_narrated_inside_the_move_line():
    dodged = act(1, 0, "지진", multiplier=0, ability="levitate", defender_hp=100)
    held = act(2, 0, "지진", ability="sturdy", defender_hp=1)
    assert lines_for(dodged)[3] == "1턴 🔵 피카츄의 지진! 꼬부기의 부유! 땅 타입 기술이 맞지 않는다!"
    assert lines_for(held)[3] == "2턴 🔵 피카츄의 지진! 꼬부기의 옹골참! 간신히 버텼다! (꼬부기 HP 1%)"


def test_a_battle_with_abilities_narrates_every_event():
    sides = (replace(mon("피카츄", ["electric"], moves=[THUNDERBOLT]), ability="drizzle"),
             replace(mon("꼬부기", ["water"], moves=[WATER_GUN]), ability="intimidate"))
    lines = battle_lines(TRAINERS, sides, simulate(sides, 4))
    assert set(lines[3:5]) == {"🔴 꼬부기의 위협! 피카츄의 공격이 떨어졌다!", "🔵 피카츄의 잔비! 비가 내리기 시작했다!"}


def test_a_status_ability_is_narrated_inside_the_move_line():
    shocked = act(1, 0, "몸통박치기", ability="static", changes=(Change(0, "피카츄", "paralysis"),), defender_hp=70)
    blocked = act(2, 0, "10만볼트", ability="limber", defender_hp=70)
    assert lines_for(shocked)[3] == (
        "1턴 🔵 피카츄의 몸통박치기! 꼬부기의 정전기! 피카츄는 마비되어 기술이 나오기 어려워졌다! (꼬부기 HP 70%)"
    )
    assert lines_for(blocked)[3] == "2턴 🔵 피카츄의 10만볼트! 꼬부기의 유연! 마비되지 않는다! (꼬부기 HP 70%)"
