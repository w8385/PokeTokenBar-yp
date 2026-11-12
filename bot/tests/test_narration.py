import pytest

from ypoke.battle import BaseStats, BattleResult, Combatant, Hit, Move, simulate
from ypoke.narration import PRACTICE_NOTE, battle_lines, with_particle

IVS = BaseStats(15, 15, 15, 15, 15, 15)
THUNDERBOLT = Move("10만볼트", "electric", 90, physical=False, accuracy=100)
WATER_GUN = Move("물대포", "water", 40, physical=False, accuracy=100)


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


def hit(turn, side, move="10만볼트", multiplier=1.0, critical=False, knockout=False, missed=False,
        names=("피카츄", "꼬부기")):
    attacker, defender = names if side == 0 else names[::-1]
    return Hit(turn, side, attacker, defender, move, multiplier, critical, knockout, missed)


def test_one_on_one_lines_follow_the_game_order():
    result = BattleResult(winner=0, turns=2, hits=[
        hit(1, 0, multiplier=2.0),
        hit(1, 1, move="물대포", multiplier=0.5),
        hit(2, 0, multiplier=2.0, critical=True, knockout=True),
    ])
    lines = battle_lines(("<@UA>", "<@UB>"), ([mon("피카츄", shiny=True)], [mon("꼬부기", level=20)]), result)
    assert lines == [
        "<@UB>에게 <@UA>이(가) 승부를 걸어왔다!",
        "<@UA>은(는) 피카츄를 내보냈다! (Lv50 ✨)",
        "<@UB>은(는) 꼬부기를 내보냈다! (Lv20)",
        "피카츄의 10만볼트! 효과가 굉장했다!",
        "꼬부기의 물대포! 효과가 별로인 듯하다…",
        "피카츄의 10만볼트! 급소에 맞았다! 효과가 굉장했다! 꼬부기는 쓰러졌다!",
        "<@UA>은(는) 승부에서 이겼다!",
    ]


def test_without_sim_detail_only_the_frame_lines_remain():
    lines = battle_lines(("<@UA>", "<@UB>"), ([mon("리자몽")], [mon("뮤")]), BattleResult(winner=1, turns=0))
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
    lines = battle_lines(("<@UA>", "<@UB>"), ([mon("피카츄")], [mon("꼬부기")]), BattleResult(winner=1, turns=19, hits=hits))
    assert lines[3:6] == ["꼬부기의 10만볼트!", "피카츄의 10만볼트! 급소에 맞았다!", "꼬부기의 10만볼트! 피카츄는 쓰러졌다!"]
    assert len(lines) == 7


def test_a_miss_is_narrated():
    result = BattleResult(winner=1, turns=1, hits=[hit(1, 0, move="번개", missed=True)])
    assert battle_lines(("<@UA>", "<@UB>"), ([mon("피카츄")], [mon("꼬부기")]), result)[3] == "피카츄의 번개! 하지만 빗나갔다!"


def test_three_on_three_lists_the_order_and_every_knockout_in_ten_lines():
    entries = (
        [mon("피카츄", ["electric"], level=60, shiny=True, moves=[THUNDERBOLT]), mon("꼬부기", ["water"], level=40),
         mon("이상해씨", ["grass"], level=40)],
        [mon("야도란", ["water", "psychic"], level=50), mon("갸라도스", ["water", "flying"], level=50),
         mon("잉어킹", ["water"], level=50, moves=[WATER_GUN])],
    )
    result = simulate(entries, seed=5)
    lines = battle_lines(("<@UA>", "<@UB>"), entries, result)
    assert lines[1] == "<@UA>은(는) 피카츄(Lv60 ✨) → 꼬부기(Lv40) → 이상해씨(Lv40) 순으로 내보낸다!"
    assert lines[2] == "<@UB>은(는) 야도란(Lv50) → 갸라도스(Lv50) → 잉어킹(Lv50) 순으로 내보낸다!"
    knockouts = [line for line in lines if line.endswith("쓰러졌다!")]
    assert len(knockouts) == sum(hit.knockout for hit in result.hits) >= 3
    assert len(lines) <= 10
    assert any("피카츄의 10만볼트!" in line for line in lines)


def test_practice_battle_says_so_on_the_last_line():
    lines = battle_lines(("<@UA>", "<@UBOT>"), ([mon("피카츄")], [mon("뮤")]), BattleResult(winner=0, turns=0), practice=True)
    assert lines[-1] == f"<@UA>은(는) 승부에서 이겼다! {PRACTICE_NOTE}"


def test_same_seed_gives_the_same_narration():
    sides = ([mon("피카츄", ["electric"], level=40, moves=[THUNDERBOLT])], [mon("꼬부기", ["water"], level=40, moves=[WATER_GUN])])
    first = battle_lines(("<@UA>", "<@UB>"), sides, simulate(sides, 9))
    second = battle_lines(("<@UA>", "<@UB>"), sides, simulate(sides, 9))
    assert first == second
    assert first[-2].endswith("꼬부기는 쓰러졌다!")
    assert all(line.startswith(("피카츄의 10만볼트!", "꼬부기의 물대포!")) for line in first[3:-1])
