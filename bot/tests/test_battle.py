from ypoke.battle import BaseStats, Combatant, _Fighter, simulate
from ypoke.type_chart import effectiveness

IVS = BaseStats(15, 15, 15, 15, 15, 15)


def mon(name, types, level=50, hp=80, attack=80, defense=80, special_attack=80, special_defense=80, speed=80):
    return Combatant(
        name=name,
        level=level,
        types=tuple(types),
        base=BaseStats(hp, attack, defense, special_attack, special_defense, speed),
        ivs=IVS,
    )


def test_effectiveness_multiplies_dual_types():
    assert effectiveness("electric", ("water", "flying")) == 4
    assert effectiveness("ground", ("electric", "flying")) == 0
    assert effectiveness("fire", ("grass",)) == 2
    assert effectiveness("normal", ("psychic",)) == 1


def test_same_seed_replays_the_same_battle():
    sides = ([mon("A", ["fire"]), mon("B", ["water"])], [mon("C", ["grass"]), mon("D", ["rock"])])
    first = simulate(sides, seed=42)
    second = simulate(sides, seed=42)
    assert (first.winner, first.turns, first.log) == (second.winner, second.turns, second.log)


def test_type_advantage_and_level_decide_the_winner():
    for seed in range(20):
        result = simulate(([mon("물", ["water"], level=60)], [mon("불", ["fire"], level=40)]), seed)
        assert result.winner == 0
        assert result.remaining == (1, 0)


def test_opponent_side_can_win():
    result = simulate(([mon("약", ["bug"], level=5)], [mon("강", ["fire"], level=90)]), seed=1)
    assert result.winner == 1
    assert "🔴 강 Lv90의 불꽃 공격 (효과가 굉장했다!) → 약 Lv5 쓰러짐" in result.log[0]


def test_immune_attacker_falls_back_to_typeless_attack():
    result = simulate(([mon("노말", ["normal"], level=80)], [mon("유령", ["ghost"], level=5, hp=10)]), seed=3)
    assert result.winner == 0
    assert "몸통박치기" in result.log[-1]


def test_next_party_member_enters_after_a_knockout():
    result = simulate(
        ([mon("A1", ["water"], level=70), mon("A2", ["water"], level=70)],
         [mon("B1", ["fire"], level=20), mon("B2", ["fire"], level=20), mon("B3", ["fire"], level=20)]),
        seed=7,
    )
    assert result.winner == 0
    assert len(result.log) >= 3


def test_shedinja_style_base_hp_one_has_one_hp():
    assert _Fighter.enter(mon("껍질몬", ["bug", "ghost"], hp=1)).max_hp == 1


def test_stats_follow_the_mainline_formula():
    fighter = _Fighter.enter(mon("피카츄", ["electric"], level=50, hp=35, speed=90))
    assert fighter.max_hp == (2 * 35 + 15) * 50 // 100 + 50 + 10
    assert fighter.speed == (2 * 90 + 15) * 50 // 100 + 5
