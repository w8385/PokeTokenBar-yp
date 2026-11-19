import random

import pytest
from status_moves import choose, data_move, pair, put, resolve, weather
from test_battle import TACKLE, mon

from ypoke import battle
from ypoke.battle import Change, Move, _Arena, _Team

PROTECT, KINGS_SHIELD, SPIKY_SHIELD, BANEFUL_BUNKER = data_move(182), data_move(588), data_move(596), data_move(661)
QUICK_GUARD, CRAFTY_SHIELD, MAT_BLOCK, ENDURE = data_move(501), data_move(578), data_move(561), data_move(203)
SUBSTITUTE, SHED_TAIL, WISH = data_move(164), data_move(880), data_move(273)
GROWL, HYPER_VOICE, SWORDS_DANCE, FLAIL = data_move(45), data_move(304), data_move(14), data_move(175)
LEER, BODY_SLAM, EARTHQUAKE = data_move(43), data_move(34), data_move(89)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)
QUICK_ATTACK = Move("전광석화", "normal", 40, physical=True, accuracy=100, priority=1)
HUGE_HIT = Move("큰기술", "normal", 250, physical=True, accuracy=100)


def fighters(arena=None):
    arena = arena or _Arena()
    return put(mon("사용자", ("normal",)), arena), put(mon("상대", ("normal",)), arena, 1), arena


def test_protect_stops_attacks_and_aimed_status_moves_for_the_turn_only():
    user, foe, arena = fighters()
    assert resolve(user, foe, PROTECT, arena).effect == "protect"
    assert resolve(foe, user, TACKLE, arena).blocked == "protect" and user.hp == user.max_hp
    assert resolve(foe, user, GROWL, arena).blocked == "protect" and user.stages["attack"] == 0
    assert not resolve(foe, user, SWORDS_DANCE, arena).failed
    battle._volatile_upkeep(1, (user, foe), [], random.Random(0))
    assert resolve(foe, user, TACKLE, arena).blocked == "" and user.hp < user.max_hp


def test_protect_fails_when_the_user_moves_last():
    user, foe, arena = fighters()
    foe.acted = True
    assert resolve(user, foe, PROTECT, arena).failed and "protect" not in user.volatiles


def test_a_repeat_protect_works_one_time_in_three_per_straight_success():
    landed = 0
    for seed in range(600):
        user, foe, arena = fighters()
        resolve(user, foe, PROTECT, arena, turn=1)
        user.volatiles.clear()
        landed += not resolve(user, foe, PROTECT, arena, seed=seed, turn=2).failed
    assert 170 < landed < 230
    user, foe, arena = fighters()
    resolve(user, foe, PROTECT, arena, turn=1)
    user.volatiles.clear()
    assert not resolve(user, foe, PROTECT, arena, seed=0, turn=3).failed


def test_the_shields_punish_a_contact_attack():
    user, foe, arena = fighters()
    resolve(user, foe, KINGS_SHIELD, arena)
    assert resolve(foe, user, BODY_SLAM, arena).changes == (Change(1, "상대", "attack", -1),)
    assert not resolve(foe, user, GROWL, arena).failed
    user.volatiles.clear()
    user.memory.clear()
    resolve(user, foe, SPIKY_SHIELD, arena)
    resolve(foe, user, BODY_SLAM, arena)
    assert foe.hp == foe.max_hp - foe.max_hp // 8
    user.volatiles.clear()
    user.memory.clear()
    resolve(user, foe, BANEFUL_BUNKER, arena)
    resolve(foe, user, EMBER, arena)
    assert foe.status is None
    resolve(foe, user, BODY_SLAM, arena)
    assert foe.status == "poison"


def test_the_shields_leave_a_physical_attack_without_contact_alone():
    user, foe, arena = fighters()
    resolve(user, foe, KINGS_SHIELD, arena)
    assert resolve(foe, user, EARTHQUAKE, arena).changes == ()
    user.volatiles.clear()
    user.memory.clear()
    resolve(user, foe, SPIKY_SHIELD, arena)
    resolve(foe, user, EARTHQUAKE, arena)
    assert foe.hp == foe.max_hp


def test_quick_guard_stops_priority_and_crafty_shield_stops_status_moves():
    user, foe, arena = fighters()
    resolve(user, foe, QUICK_GUARD, arena)
    assert resolve(foe, user, QUICK_ATTACK, arena).blocked == "quick-guard"
    assert resolve(foe, user, TACKLE, arena).blocked == ""
    user.volatiles.clear()
    resolve(user, foe, CRAFTY_SHIELD, arena)
    assert resolve(foe, user, GROWL, arena).blocked == "crafty-shield"
    assert resolve(foe, user, TACKLE, arena).blocked == ""


def test_mat_block_works_on_the_first_turn_in_only():
    user, foe, arena = fighters()
    assert resolve(user, foe, MAT_BLOCK, arena).effect == "mat-block"
    user.volatiles.clear()
    user.last_used = 0
    assert resolve(user, foe, MAT_BLOCK, arena, turn=3).failed


def test_endure_leaves_one_hp():
    user, foe, arena = fighters()
    resolve(user, foe, ENDURE, arena)
    user.hp = 5
    resolve(foe, user, HUGE_HIT, arena)
    assert user.hp == 1


def test_substitute_takes_hits_and_stops_status_moves_until_it_breaks():
    user, foe, arena = fighters()
    resolve(user, foe, SUBSTITUTE, arena)
    paid = user.max_hp // 4
    assert user.hp == user.max_hp - paid and user.volatiles["substitute"] == paid
    assert resolve(foe, user, LEER, arena).blocked == "substitute" and user.stages["defense"] == 0
    resolve(foe, user, EMBER, arena)
    assert user.hp == user.max_hp - paid and 0 < user.volatiles["substitute"] < paid
    assert isinstance(arena.log[-1], battle.VolatileTick)
    resolve(foe, user, HUGE_HIT, arena)
    assert "substitute" not in user.volatiles and user.hp == user.max_hp - paid
    assert isinstance(arena.log[-1], battle.VolatileEnd)
    assert resolve(user, foe, SUBSTITUTE, arena).effect == "substitute"
    user.hp = user.max_hp // 4
    user.volatiles.clear()
    assert resolve(user, foe, SUBSTITUTE, arena).failed


def test_sound_moves_and_infiltrator_pass_a_substitute():
    user, foe, arena = fighters()
    resolve(user, foe, SUBSTITUTE, arena)
    assert not resolve(foe, user, GROWL, arena).failed and user.stages["attack"] == -1
    resolve(foe, user, HYPER_VOICE, arena)
    assert user.hp < user.max_hp - user.max_hp // 4
    user, foe, arena = fighters()
    foe = put(mon("상대", ("normal",)), arena, 1, ability="infiltrator")
    resolve(user, foe, SUBSTITUTE, arena)
    assert not resolve(foe, user, LEER, arena).failed and user.stages["defense"] == -1


def test_shed_tail_hands_its_substitute_to_the_next_member():
    arena = _Arena()
    team = _Team((mon("사용자", ("normal",), moves=(SHED_TAIL,)), mon("후속", ("normal",))), arena=arena)
    foe_team = _Team((mon("상대", ("normal",)),), arena=arena, side=1)
    arena.teams = (team, foe_team)
    user = team.active
    used = battle._act(1, 0, (user, foe_team.active), 0, battle._Weather(), random.Random(0), arena)
    assert used.effect == "shed-tail" and user.hp == user.max_hp - user.max_hp // 2
    assert battle._pivots(team, used, 0)
    battle._pivot((team, foe_team), 0, 1, arena, battle._Weather(), random.Random(0), [])
    assert team.active.combatant.name == "후속" and team.active.volatiles["substitute"] == user.max_hp // 4
    assert "shed-tail" not in arena.hazards[0]


def test_the_chooser_guards_only_when_a_turn_of_stalling_pays_and_never_twice_in_a_row():
    teams, arena = pair((PROTECT, TACKLE))
    assert choose(teams, arena) == 1
    teams[1].active.status = "toxic"
    assert choose(teams, arena) == 0
    teams[0].active.memory["guard"] = (arena.turn - 1, 1)
    assert choose(teams, arena) == 1
    teams, arena = pair((PROTECT, TACKLE))
    teams[0].active.volatiles["wish"] = [1, 10]
    assert choose(teams, arena) == 0


def test_the_chooser_guards_against_the_kind_of_move_the_foe_used_last():
    teams, arena = pair((CRAFTY_SHIELD, QUICK_GUARD, TACKLE), foe_moves=(GROWL, QUICK_ATTACK))
    assert choose(teams, arena) == 2
    teams[1].active.last_used = 0
    assert choose(teams, arena) == 0
    teams[1].active.last_used = 1
    assert choose(teams, arena) == 1


def test_the_chooser_endures_only_ahead_of_a_flail_and_subs_only_above_half():
    teams, arena = pair((ENDURE, TACKLE), foe_moves=(HUGE_HIT,))
    assert choose(teams, arena) == 1
    teams, arena = pair((ENDURE, FLAIL), foe_moves=(HUGE_HIT,))
    assert choose(teams, arena) == 0
    teams, arena = pair((SUBSTITUTE, TACKLE), foe_moves=(GROWL, TACKLE))
    assert choose(teams, arena) == 0
    teams[0].active.hp = teams[0].active.max_hp // 2
    assert choose(teams, arena) == 1


def test_endure_in_sand_outlasts_a_foe_that_the_chip_knocks_out_at_the_end_of_the_turn():
    teams, arena, user, foe = facing_a_finishing_hit()
    foe.hp = foe.max_hp // 16
    assert choose(teams, arena, weather="sandstorm") == 0
    assert end_of_a_turn_of_endure(teams, arena, weather("sandstorm")) == 1 and user.hp == 1


def test_endure_is_not_used_when_the_chip_leaves_the_foe_standing():
    teams, arena, _, foe = facing_a_finishing_hit()
    foe.hp = foe.max_hp // 16 + 1
    assert choose(teams, arena, weather="sandstorm") == 1


@pytest.mark.parametrize("foe_type", ["rock", "ground", "steel"])
def test_endure_is_not_used_against_a_foe_the_sand_does_not_chip(foe_type):
    teams, arena, _, foe = facing_a_finishing_hit(foe_types=(foe_type,))
    foe.hp = foe.max_hp // 16
    assert choose(teams, arena, weather="sandstorm") == 1


def test_endure_is_not_used_when_the_chip_would_knock_out_the_enduring_user_too():
    teams, arena, _, foe = facing_a_finishing_hit(user_types=("normal",))
    foe.hp = foe.max_hp // 16
    assert choose(teams, arena, weather="sandstorm") == 1


@pytest.mark.parametrize(("ticking", "share"), [
    ({"status": "poison"}, 8), ({"status": "toxic"}, 16), ({"status": "burn"}, 16),
    ({"volatile": "leech-seed"}, 8), ({"volatile": "salt-cure"}, 8), ({"volatile": "binding"}, 8),
])
def test_endure_outlasts_a_foe_that_its_status_or_state_finishes_at_the_end_of_the_turn(ticking, share):
    teams, arena, user, foe = facing_a_finishing_hit()
    foe.status = ticking.get("status")
    if ticking.get("volatile") == "binding":
        user.memory["binding"] = token = (1, user.combatant.name)
        foe.volatiles["binding"] = [3, token]
    elif "volatile" in ticking:
        foe.volatiles[ticking["volatile"]] = True
    foe.hp = foe.max_hp // share
    assert choose(teams, arena) == 0
    assert end_of_a_turn_of_endure(teams, arena, weather(None)) == 1 and user.hp > 0
    foe.hp = foe.max_hp
    assert choose(teams, arena) == 1


def facing_a_finishing_hit(user_types=("ground",), foe_types=("normal",)):
    """A faster Endure user at half HP, which the foe's best hit knocks out, and whose Tackle cannot finish the foe
    at 1/16 HP."""
    teams, arena = pair((ENDURE, TACKLE), foe_moves=(HUGE_HIT,), user_types=user_types, foe_types=foe_types,
                        speed=200, attack=1)
    teams[0].active.hp = teams[0].active.max_hp // 2
    return teams, arena, teams[0].active, teams[1].active


def end_of_a_turn_of_endure(teams, arena, field):
    """The user endures, the foe's hit leaves it 1 HP, and the turn ends. Returns the side that ran out, if any."""
    user, foe = teams[0].active, teams[1].active
    resolve(user, foe, ENDURE, arena)
    resolve(foe, user, HUGE_HIT, arena)
    return battle._end_of_turn(1, teams, field, arena, random.Random(0), [])
