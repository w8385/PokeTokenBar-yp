import random
from dataclasses import replace

from status_moves import choose, data_move, pair, put, resolve, weather
from test_battle import TACKLE, mon

from ypoke import battle
from ypoke.battle import Change, Move, _Arena

GROWL, LEER, SAND_ATTACK, DOUBLE_TEAM = data_move(45), data_move(43), data_move(28), data_move(104)
DRAGON_DANCE, BELLY_DRUM, SHELL_SMASH, GROWTH = data_move(349), data_move(187), data_move(504), data_move(74)
STOCKPILE, CHARGE, NO_RETREAT, TAKE_HEART = data_move(254), data_move(268), data_move(748), data_move(850)
GEAR_UP, ROTOTILLER, VENOM_DRENCH, ACUPRESSURE = data_move(674), data_move(563), data_move(599), data_move(367)
PSYCH_UP, TOPSY_TURVY, HEART_SWAP, POWER_SWAP = data_move(244), data_move(576), data_move(391), data_move(384)
SPEED_SWAP, POWER_SPLIT, POWER_TRICK, DECORATE = data_move(683), data_move(471), data_move(379), data_move(777)
FLOWER_TRICK = Move("트릭플라워", "grass", 70, physical=True, accuracy=None, id=870)
THUNDERBOLT = Move("10만볼트", "electric", 90, physical=False, accuracy=100)
WEAK_SHOT = Move("빗나가기쉬운기술", "normal", 40, physical=True, accuracy=50)


def fighters(arena=None, user_types=("normal",), foe_types=("normal",), **stats):
    arena = arena or _Arena()
    return put(mon("사용자", user_types, **stats), arena), put(mon("상대", foe_types), arena, 1), arena


def test_a_foe_drop_lowers_the_foes_stage_and_fails_at_minus_six_or_through_mist():
    user, foe, arena = fighters()
    assert resolve(user, foe, GROWL, arena).changes == (Change(1, "상대", "attack", -1),)
    foe.stages["attack"] = -6
    assert resolve(user, foe, GROWL, arena).failed
    foe.stages["attack"] = 0
    arena.sides[1]["mist"] = 3
    assert resolve(user, foe, GROWL, arena).failed and foe.stages["attack"] == 0


def test_a_self_boost_raises_every_listed_stage_once_per_entry():
    user, foe, arena = fighters()
    assert resolve(user, foe, DRAGON_DANCE, arena).changes == (
        Change(0, "사용자", "attack", 1), Change(0, "사용자", "speed", 1))
    assert user.danced
    smash = resolve(user, foe, SHELL_SMASH, arena)
    assert [(change.kind, change.stages) for change in smash.changes] == [
        ("defense", -1), ("special_defense", -1), ("attack", 2), ("special_attack", 2), ("speed", 2)]


def test_belly_drum_pays_half_its_hp_for_plus_six_and_fails_at_half_or_below():
    user, foe, arena = fighters()
    used = resolve(user, foe, BELLY_DRUM, arena)
    assert used.changes == (Change(0, "사용자", "attack", 6),) and user.hp == user.max_hp - user.max_hp // 2
    user.stages["attack"], user.hp = 0, user.max_hp // 2
    assert resolve(user, foe, BELLY_DRUM, arena).failed and user.stages["attack"] == 0


def test_growth_raises_twice_as_much_in_sun():
    user, foe, arena = fighters()
    assert {change.stages for change in resolve(user, foe, GROWTH, arena).changes} == {1}
    user.stages = dict.fromkeys(battle.STAGES, 0)
    arena.weather = weather("sun")
    assert {change.stages for change in resolve(user, foe, GROWTH, arena).changes} == {2}


def test_stockpile_stacks_three_times_and_no_retreat_once_per_entry():
    user, foe, arena = fighters()
    for _ in range(3):
        assert not resolve(user, foe, STOCKPILE, arena).failed
    assert resolve(user, foe, STOCKPILE, arena).failed and user.stages["defense"] == 3
    assert not resolve(user, foe, NO_RETREAT, arena).failed
    assert resolve(user, foe, NO_RETREAT, arena).failed
    user.leave()
    assert not resolve(user, foe, STOCKPILE, arena).failed


def test_charge_doubles_electric_moves_across_turn_ends_until_its_user_tries_one():
    user, foe, arena = fighters()
    act(user, foe, CHARGE, arena)
    for _ in range(3):
        battle._volatile_upkeep(1, (user, foe), [], None)
    assert battle._power(user, foe, THUNDERBOLT, None, 1.0) == 180
    assert battle._power(user, foe, TACKLE, None, 1.0) == TACKLE.power
    act(user, foe, TACKLE, arena)
    assert battle._power(user, foe, THUNDERBOLT, None, 1.0) == 180
    act(user, foe, THUNDERBOLT, arena)
    assert battle._power(user, foe, THUNDERBOLT, None, 1.0) == 90


def test_charge_ends_when_its_users_electric_move_cannot_be_used():
    user, foe, arena = fighters()
    act(user, foe, CHARGE, arena)
    user.volatiles["flinch"] = True
    assert act(user, foe, THUNDERBOLT, arena).blocked
    assert battle._power(user, foe, THUNDERBOLT, None, 1.0) == 90


def act(user, target, move, arena):
    user.combatant = replace(user.combatant, moves=(move, *user.combatant.moves[1:]))
    user.pp = [move.pp, *user.pp[1:]]
    return battle._act(1, user.side, (user, target), 0, arena.weather, random.Random(0), arena)


def test_take_heart_cures_and_plus_minus_needs_its_ability():
    user, foe, arena = fighters()
    user.status = "burn"
    assert Change(0, "사용자", "cure") in resolve(user, foe, TAKE_HEART, arena).changes and user.status is None
    assert resolve(user, foe, GEAR_UP, arena).failed
    plus = put(mon("플러스", ("electric",)), arena, ability="plus")
    assert not resolve(plus, foe, GEAR_UP, arena).failed


def test_rototiller_raises_grounded_grass_types_on_both_sides_and_fails_without_one():
    arena = _Arena()
    user, foe = put(mon("풀", ("grass",)), arena), put(mon("풀상대", ("grass",)), arena, 1)
    assert {change.side for change in resolve(user, foe, ROTOTILLER, arena).changes} == {0, 1}
    plain, other = put(mon("노말", ("normal",)), arena), put(mon("새", ("grass", "flying")), arena, 1)
    assert resolve(plain, other, ROTOTILLER, arena).failed


def test_venom_drench_needs_a_poisoned_foe_and_acupressure_raises_one_stage_by_two():
    user, foe, arena = fighters()
    assert resolve(user, foe, VENOM_DRENCH, arena).failed
    foe.status = "toxic"
    assert len(resolve(user, foe, VENOM_DRENCH, arena).changes) == 3
    changes = resolve(user, foe, ACUPRESSURE, arena).changes
    assert len(changes) == 1 and changes[0].stages == 2


def test_the_stage_copies_swap_invert_and_copy_the_foes_stages():
    user, foe, arena = fighters()
    foe.stages.update(attack=2, evasion=1)
    assert resolve(user, foe, PSYCH_UP, arena).effect == "psych-up" and user.stages == foe.stages
    assert resolve(user, foe, PSYCH_UP, arena).failed
    user.stages = dict.fromkeys(battle.STAGES, 0)
    assert resolve(user, foe, POWER_SWAP, arena).effect == "stage-swap"
    assert user.stages["attack"] == 2 and user.stages["evasion"] == 0 and foe.stages["attack"] == 0
    assert resolve(user, foe, HEART_SWAP, arena).effect == "stage-swap" and user.stages["evasion"] == 1
    assert resolve(user, foe, TOPSY_TURVY, arena).effect == "topsy-turvy" and foe.stages["attack"] == -2


def test_the_raw_stat_swaps_last_until_the_pokemon_leaves():
    arena = _Arena()
    user, foe = put(mon("느림", ("normal",), speed=20, attack=50, defense=150), arena), put(
        mon("빠름", ("normal",), speed=150), arena, 1)
    slow, fast, attack, defense = user.stats["speed"], foe.stats["speed"], user.stats["attack"], user.stats["defense"]
    resolve(user, foe, SPEED_SWAP, arena)
    assert (user.stats["speed"], foe.stats["speed"]) == (fast, slow)
    resolve(user, foe, POWER_TRICK, arena)
    assert (user.stats["attack"], user.stats["defense"]) == (defense, attack)
    resolve(user, foe, POWER_SPLIT, arena)
    assert user.stats["special_attack"] == foe.stats["special_attack"]
    user.leave()
    assert (user.stats["speed"], user.stats["attack"]) == (slow, attack)


def test_accuracy_and_evasion_stages_scale_the_draw_but_never_a_never_miss_move():
    user, foe, arena = fighters()
    resolve(foe, user, DOUBLE_TEAM, arena)
    assert battle._accuracy_stages(user, foe) == 3 / 4
    foe.stages["evasion"] = 0
    resolve(user, foe, SAND_ATTACK, arena)
    assert battle._accuracy_stages(foe, user) == 3 / 4
    foe.stages["evasion"] = 6
    assert all(not resolve(user, foe, FLOWER_TRICK, arena, seed=seed).missed for seed in range(20))
    assert any(resolve(user, foe, WEAK_SHOT, arena, seed=seed).missed for seed in range(20))
    user.stages["accuracy"], foe.stages["evasion"] = 6, 0
    assert battle._accuracy_stages(user, foe) == 3


def test_the_chooser_boosts_once_per_entry_and_never_decorates_the_foe():
    teams, arena = pair((DRAGON_DANCE, TACKLE))
    assert choose(teams, arena) == 0
    teams[0].active.danced = True
    assert choose(teams, arena) == 1
    teams, arena = pair((DECORATE, TACKLE))
    assert choose(teams, arena) == 1


def test_the_chooser_drops_a_foe_stat_that_matters_until_minus_two_and_never_through_mist():
    teams, arena = pair((LEER, TACKLE))
    assert choose(teams, arena) == 0
    teams[1].active.stages["defense"] = -2
    assert choose(teams, arena) == 1
    teams[1].active.stages["defense"] = 0
    arena.sides[1]["mist"] = 3
    assert choose(teams, arena) == 1
    teams, arena = pair((GROWL, TACKLE), foe_moves=(THUNDERBOLT,))
    assert choose(teams, arena) == 1
