from dataclasses import replace

from ypoke.battle import (
    STRUGGLE, TURN_LIMIT, Action, BaseStats, BurnDamage, Change, Combatant, Move, _Fighter, _stats_for, simulate,
)
from ypoke.type_chart import effectiveness

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)
FLAMETHROWER = Move("화염방사", "fire", 90, physical=False, accuracy=100)
SURF = Move("파도타기", "water", 90, physical=False, accuracy=100)
FIRE_BLAST = Move("불대문자", "fire", 120, physical=False, accuracy=50)
HAMMER_ARM = Move("암해머", "fighting", 100, physical=True, accuracy=90)


def mon(name, types, level=50, moves=(TACKLE,), hp=80, attack=80, defense=80, special_attack=80,
        special_defense=80, speed=80):
    return Combatant(
        name=name,
        level=level,
        types=tuple(types),
        base=BaseStats(hp, attack, defense, special_attack, special_defense, speed),
        ivs=IVS,
        moves=tuple(moves),
    )


def actions(result):
    return [event for event in result.events if isinstance(event, Action)]


def first_action(attacker, defender, seed=0):
    return actions(simulate((attacker, defender), seed))[0]


def test_effectiveness_multiplies_dual_types():
    assert effectiveness("electric", ("water", "flying")) == 4
    assert effectiveness("ground", ("electric", "flying")) == 0
    assert effectiveness("fire", ("grass",)) == 2
    assert effectiveness("normal", ("psychic",)) == 1


def test_same_seed_replays_the_same_battle():
    sides = (mon("A", ["fire"], moves=[FLAMETHROWER]), mon("B", ["water"], moves=[SURF]))
    assert simulate(sides, seed=42) == simulate(sides, seed=42)


def test_type_advantage_and_level_decide_the_winner():
    for seed in range(20):
        result = simulate((mon("물", ["water"], level=60, moves=[SURF]), mon("불", ["fire"], level=40, moves=[EMBER])), seed)
        assert result.winner == 0
        assert actions(result)[-1].knockout


def test_opponent_side_can_win():
    result = simulate((mon("약", ["bug"], level=5), mon("강", ["fire"], level=90, moves=[FLAMETHROWER])), seed=1)
    assert result.winner == 1
    last = actions(result)[-1]
    assert (last.attacker, last.move, last.multiplier, last.knockout) == ("강", "화염방사", 2.0, True)


def test_shedinja_style_base_hp_one_has_one_hp():
    assert _Fighter.enter(mon("껍질몬", ["bug", "ghost"], hp=1)).max_hp == 1


def test_stats_follow_the_mainline_formula():
    fighter = _Fighter.enter(mon("피카츄", ["electric"], level=50, hp=35, speed=90))
    assert fighter.max_hp == (2 * 35 + 15) * 50 // 100 + 50 + 10
    assert fighter.stat("speed") == (2 * 90 + 15) * 50 // 100 + 5


def test_picks_the_move_with_the_highest_expected_damage():
    attacker = mon("리자몽", ["fire"], moves=[TACKLE, EMBER, FLAMETHROWER, SURF], speed=200)
    assert first_action(attacker, mon("이상해씨", ["grass"])).move == "화염방사"
    assert first_action(attacker, mon("바위", ["rock"])).move == "파도타기"


def test_expected_damage_weighs_accuracy_and_the_matching_stat():
    wild_shot = mon("A", ["fire"], moves=[FIRE_BLAST, FLAMETHROWER], speed=200)
    assert first_action(wild_shot, mon("B", ["grass"])).move == "화염방사"
    strong_body = mon("C", ["normal"], moves=[FLAMETHROWER, HAMMER_ARM], speed=200, attack=150, special_attack=40)
    assert first_action(strong_body, mon("D", ["normal"])).move == "암해머"


def test_a_move_can_miss_and_does_no_damage():
    attacker = mon("A", ["fire"], moves=[Move("헛방", "fire", 200, physical=False, accuracy=1)], speed=200)
    action = first_action(attacker, mon("B", ["normal"], level=5))
    assert (action.move, action.missed, action.knockout, action.defender_hp) == ("헛방", True, False, 100)


def test_an_immune_target_takes_nothing():
    action = first_action(mon("노말", ["normal"], level=80, speed=200), mon("유령", ["ghost"], level=5))
    assert (action.move, action.multiplier, action.defender_hp) == ("몸통박치기", 0, 100)


def test_running_out_of_pp_falls_back_to_struggle_with_recoil():
    attacker = mon("A", ["normal"], moves=[replace(TACKLE, pp=1)], speed=200, hp=200, defense=200, special_defense=200)
    result = simulate((attacker, mon("B", ["normal"], moves=[], hp=200, defense=200)), seed=0)
    used = [action.move for action in actions(result) if action.side == 0]
    assert used[:2] == ["몸통박치기", STRUGGLE.name]
    assert all(action.recoil for action in actions(result)[1:] if action.side == 0)


def test_no_moves_means_struggle_and_struggle_hits_ghosts():
    action = first_action(mon("A", ["normal"], moves=[], speed=200), mon("유령", ["ghost"]))
    assert (action.move, action.multiplier, action.recoil) == ("발버둥", 1.0, True)
    assert action.defender_hp < 100


def test_a_critical_stage_of_three_always_crits():
    sure_crit = mon("A", ["normal"], moves=[replace(TACKLE, crit_stage=3)], speed=200)
    assert all(first_action(sure_crit, mon("B", ["normal"], hp=255), seed).critical for seed in range(10))


def test_burn_halves_physical_damage_and_hurts_each_turn():
    flame = replace(TACKLE, name="불꽃엄니", type="fire", ailment="burn", ailment_chance=100)
    result = simulate((mon("A", ["fire"], moves=[flame], speed=200, attack=10),
                       mon("B", ["normal"], hp=200, defense=200)), seed=0)
    assert actions(result)[0].changes == (Change(1, "B", "burn"),)
    burns = [event for event in result.events if isinstance(event, BurnDamage)]
    assert burns and burns[0] == BurnDamage(1, 1, "B", burns[0].hp, False)
    fighter = _Fighter.enter(mon("B", ["normal"]))
    plain = _stats_for(fighter, fighter, physical=True)[0]
    fighter.status = "burn"
    assert _stats_for(fighter, fighter, physical=True)[0] == plain / 2
    assert _stats_for(fighter, fighter, physical=False)[0] == fighter.stat("special_attack")


def test_type_immunity_blocks_the_ailment():
    flame = replace(TACKLE, type="fire", ailment="burn", ailment_chance=100)
    assert first_action(mon("A", ["fire"], moves=[flame], speed=200), mon("불", ["fire"], hp=200)).changes == ()


def test_paralysis_can_skip_a_turn_and_slows_the_target():
    nuzzle = Move("볼부비부비", "electric", 20, physical=True, accuracy=100, ailment="paralysis", ailment_chance=100)
    result = simulate((mon("A", ["electric"], moves=[nuzzle], speed=200, hp=255, defense=255),
                       mon("B", ["normal"], hp=255, defense=255, speed=150)), seed=3)
    assert actions(result)[0].changes == (Change(1, "B", "paralysis"),)
    assert any(action.side == 1 and action.move == "" for action in actions(result))


def test_stat_changes_hit_the_target_or_the_user_and_stop_at_six():
    crunch = replace(TACKLE, stat_changes=(("defense", -1),), stat_chance=100)
    overheat = replace(FLAMETHROWER, stat_changes=(("special_attack", -2),), stat_on_user=True, stat_chance=100)
    assert first_action(mon("A", ["normal"], moves=[crunch], speed=200), mon("B", ["normal"], hp=255)).changes == (
        Change(1, "B", "defense", -1),)
    assert first_action(mon("A", ["fire"], moves=[overheat], speed=200), mon("B", ["water"], hp=255)).changes == (
        Change(0, "A", "special_attack", -2),)
    fighter = _Fighter.enter(mon("B", ["normal"]))
    fighter.stages["defense"] = -6
    assert fighter.stat("defense") == fighter.stats["defense"] * 2 / 8


def test_a_stalemate_ends_at_the_turn_limit():
    lick = Move("핥기", "ghost", 30, physical=True, accuracy=100, pp=999)
    result = simulate((mon("노말", ["normal"], moves=[replace(TACKLE, pp=999)]), mon("유령", ["ghost"], moves=[lick])), 0)
    assert (result.turns, result.winner) == (TURN_LIMIT, 0)
