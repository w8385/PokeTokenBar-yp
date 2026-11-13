import pytest

from ypoke.battle import Action, BaseStats, BattleResult, BurnDamage, Change, Combatant, Move, simulate
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
        act(2, 1, move=""),
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
    (BurnDamage(3, 1, "꼬부기", 12, False), "3턴 🔴 꼬부기는 화상 데미지를 입었다! (HP 12%)"),
    (BurnDamage(3, 1, "꼬부기", 0, True), "3턴 🔴 꼬부기는 화상 데미지를 입었다! 꼬부기는 쓰러졌다!"),
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
