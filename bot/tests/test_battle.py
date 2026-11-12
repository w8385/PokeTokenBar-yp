from dataclasses import replace

from ypoke.battle import BaseStats, Combatant, Move, _Fighter, simulate
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


TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)
FLAMETHROWER = Move("화염방사", "fire", 90, physical=False, accuracy=100)
SURF = Move("파도타기", "water", 90, physical=False, accuracy=100)
FIRE_BLAST = Move("불대문자", "fire", 120, physical=False, accuracy=50)
HAMMER_ARM = Move("암해머", "fighting", 100, physical=True, accuracy=90)


def armed(name, types, moves, level=50, **stats):
    return replace(mon(name, types, level=level, **stats), moves=tuple(moves))


def first_move(attacker, defender, seed=0):
    return simulate(([attacker], [defender]), seed).hits[0]


def test_picks_the_move_with_the_highest_expected_damage():
    attacker = armed("리자몽", ["fire"], [TACKLE, EMBER, FLAMETHROWER, SURF], speed=200)
    assert first_move(attacker, mon("이상해씨", ["grass"])).move == "화염방사"
    assert first_move(attacker, mon("바위", ["rock"])).move == "파도타기"


def test_expected_damage_weighs_accuracy_and_the_matching_stat():
    wild_shot = armed("A", ["fire"], [FIRE_BLAST, FLAMETHROWER], speed=200)
    assert first_move(wild_shot, mon("B", ["grass"])).move == "화염방사"
    strong_body = armed("C", ["normal"], [FLAMETHROWER, HAMMER_ARM], speed=200, attack=150, special_attack=40)
    assert first_move(strong_body, mon("D", ["normal"])).move == "암해머"


def test_a_move_can_miss_and_does_no_damage():
    attacker = armed("A", ["fire"], [Move("헛방", "fire", 200, physical=False, accuracy=1)], speed=200)
    result = simulate(([attacker], [mon("B", ["normal"], level=5)]), seed=0)
    assert result.hits[0].missed
    assert result.hits[0].move == "헛방"
    assert not result.hits[0].knockout


def test_immune_moves_fall_back_to_the_typeless_attack():
    ghost_proof = armed("노말", ["normal"], [TACKLE], level=80, speed=200)
    assert first_move(ghost_proof, mon("유령", ["ghost"], level=5)).move == "몸통박치기"
    assert first_move(ghost_proof, mon("유령", ["ghost"], level=5)).multiplier == 1.0


def test_knockout_log_uses_the_move_name():
    attacker = armed("A", ["fire"], [FLAMETHROWER], level=90, speed=200)
    result = simulate(([attacker], [mon("B", ["grass"], level=5)]), seed=1)
    assert "화염방사" in result.log[0]
    assert result.hits[-1].defender == "B"
