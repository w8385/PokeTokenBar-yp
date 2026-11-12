import pytest

from ypoke.battle import BaseStats, BattleResult, Combatant, Hit, simulate
from ypoke.narration import PRACTICE_NOTE, battle_lines, with_particle

IVS = BaseStats(15, 15, 15, 15, 15, 15)


def mon(name, types=("normal",), level=50, shiny=False):
    return Combatant(name=name, level=level, types=tuple(types), base=BaseStats(80, 80, 80, 80, 80, 80),
                     ivs=IVS, shiny=shiny)


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


def hit(turn, side, move="전기 공격", multiplier=1.0, critical=False, knockout=False):
    return Hit(turn, side, move, multiplier, critical, knockout)


def test_lines_follow_the_game_order():
    result = BattleResult(winner=0, turns=2, hits=[
        hit(1, 0, multiplier=2.0),
        hit(1, 1, move="물 공격", multiplier=0.5),
        hit(2, 0, multiplier=2.0, critical=True, knockout=True),
    ])
    lines = battle_lines(("<@UA>", "<@UB>"), (mon("피카츄", shiny=True), mon("꼬부기", level=20)), result)
    assert lines == [
        "<@UB>에게 <@UA>이(가) 승부를 걸어왔다!",
        "<@UA>은(는) 피카츄를 내보냈다! (Lv50 ✨)",
        "<@UB>은(는) 꼬부기를 내보냈다! (Lv20)",
        "피카츄의 전기 공격! 효과가 굉장했다!",
        "꼬부기의 물 공격! 효과가 별로인 듯하다…",
        "피카츄의 전기 공격! 급소에 맞았다! 효과가 굉장했다!",
        "꼬부기는 쓰러졌다!",
        "<@UA>은(는) 승부에서 이겼다!",
    ]


def test_without_sim_detail_only_the_frame_lines_remain():
    lines = battle_lines(("<@UA>", "<@UB>"), (mon("리자몽"), mon("뮤")), BattleResult(winner=1, turns=0))
    assert lines == [
        "<@UB>에게 <@UA>이(가) 승부를 걸어왔다!",
        "<@UA>은(는) 리자몽을 내보냈다! (Lv50)",
        "<@UB>은(는) 뮤를 내보냈다! (Lv50)",
        "<@UB>은(는) 승부에서 이겼다!",
    ]


def test_long_battles_keep_at_most_three_key_hits_in_order():
    hits = [hit(turn, turn % 2) for turn in range(1, 20)]
    hits[7] = hit(8, 0, critical=True)
    hits[-1] = hit(19, 1, knockout=True)
    lines = battle_lines(("<@UA>", "<@UB>"), (mon("피카츄"), mon("꼬부기")), BattleResult(winner=1, turns=19, hits=hits))
    assert lines[3:6] == ["꼬부기의 전기 공격!", "피카츄의 전기 공격! 급소에 맞았다!", "꼬부기의 전기 공격!"]
    assert lines[6] == "피카츄는 쓰러졌다!"
    assert len(lines) <= 8


def test_practice_battle_says_so_on_the_last_line():
    lines = battle_lines(("<@UA>", "<@UBOT>"), (mon("피카츄"), mon("뮤")), BattleResult(winner=0, turns=0), practice=True)
    assert lines[-1] == f"<@UA>은(는) 승부에서 이겼다! {PRACTICE_NOTE}"


def test_same_seed_gives_the_same_narration():
    sides = ([mon("피카츄", ["electric"], level=40)], [mon("꼬부기", ["water"], level=40)])
    first = battle_lines(("<@UA>", "<@UB>"), (sides[0][0], sides[1][0]), simulate(sides, 9))
    second = battle_lines(("<@UA>", "<@UB>"), (sides[0][0], sides[1][0]), simulate(sides, 9))
    assert first == second
    assert first[-2] == "꼬부기는 쓰러졌다!"
    assert all(line.startswith(("피카츄의 전기 공격!", "꼬부기의 물 공격!")) for line in first[3:-2])
