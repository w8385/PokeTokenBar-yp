from dataclasses import replace

import pytest
from attacks import attack
from status_moves import data_move, pair, put, resolve
from test_battle import mon

from ypoke.battle import Change, _Arena
from ypoke.effects import hooks
from ypoke.effects.stats import boost_wanted

CLOSE_COMBAT, SNARL, DARK_PULSE = attack(370), attack(555), attack(399)
GROWL, SWORDS_DANCE, NASTY_PLOT, MIST = data_move(45), data_move(14), data_move(417), data_move(54)
STAGES_OF = {None: 1, "contrary": -1}


def duel(user_ability=None, foe_ability=None):
    arena = _Arena()
    user = put(mon("사용자", ("normal",), moves=(DARK_PULSE,)), arena, ability=user_ability)
    foe = put(mon("상대", ("normal",), hp=255, defense=255, special_defense=255), arena, 1, ability=foe_ability)
    return user, foe, arena


def stage_changes(action, side):
    return [(change.kind, change.stages) for change in action.changes if change.side == side]


@pytest.mark.parametrize("ability", [None, "contrary"])
def test_contrary_turns_a_self_drop_into_a_rise(ability):
    user, foe, arena = duel(user_ability=ability)
    action = resolve(user, foe, CLOSE_COMBAT, arena)
    sign = STAGES_OF[ability]
    assert stage_changes(action, 0) == [("defense", -sign), ("special_defense", -sign)]
    assert (user.stages["defense"], user.stages["special_defense"]) == (-sign, -sign)


@pytest.mark.parametrize("ability", [None, "contrary"])
@pytest.mark.parametrize("move", [SNARL, GROWL])
def test_contrary_turns_a_foes_drop_into_a_rise(move, ability):
    user, foe, arena = duel(foe_ability=ability)
    resolve(user, foe, move, arena)
    key = "special_attack" if move is SNARL else "attack"
    assert foe.stages[key] == -STAGES_OF[ability]


@pytest.mark.parametrize("ability", [None, "contrary"])
def test_contrary_turns_intimidate_into_an_attack_rise(ability):
    user, foe, arena = duel(user_ability="intimidate", foe_ability=ability)
    trigger = hooks.ability(user, "on_entry", user, foe, 0, arena.weather)
    assert trigger.change == Change(1, "상대", "attack", -STAGES_OF[ability])
    assert foe.stages["attack"] == -STAGES_OF[ability]


@pytest.mark.parametrize("ability", [None, "contrary"])
@pytest.mark.parametrize(("move", "key"), [(SWORDS_DANCE, "attack"), (NASTY_PLOT, "special_attack")])
def test_contrary_turns_a_boost_into_a_drop(move, key, ability):
    user, foe, arena = duel(user_ability=ability)
    action = resolve(user, foe, move, arena)
    assert stage_changes(action, 0) == [(key, 2 * STAGES_OF[ability])]


@pytest.mark.parametrize("ability", [None, "contrary"])
def test_mist_stops_a_drop_but_not_one_contrary_turned_into_a_rise(ability):
    user, foe, arena = duel(foe_ability=ability)
    resolve(foe, user, MIST, arena)
    resolve(user, foe, GROWL, arena)
    resolve(user, foe, SNARL, arena)
    rises = (1, 1) if ability else (0, 0)
    assert (foe.stages["attack"], foe.stages["special_attack"]) == rises


@pytest.mark.parametrize(("ability", "wanted"), [(None, True), ("contrary", False)])
def test_the_move_chooser_does_not_boost_a_contrary_user_into_a_drop(ability, wanted):
    user, foe, _ = duel(user_ability=ability)
    assert boost_wanted((("special_attack", 2),), user, foe, None) is wanted
    teams, arena = pair((SWORDS_DANCE, CLOSE_COMBAT))
    teams[0].active.combatant = replace(teams[0].active.combatant, ability=ability)
    assert hooks.move(SWORDS_DANCE, "wanted", teams[0], teams[1], 0, arena, None, default=False) is wanted


@pytest.mark.parametrize(("ability", "wanted"), [(None, True), ("contrary", False)])
def test_the_move_chooser_does_not_lower_a_contrary_foes_stat_into_a_rise(ability, wanted):
    teams, arena = pair((GROWL, CLOSE_COMBAT), foe_moves=(CLOSE_COMBAT,))
    teams[1].active.combatant = replace(teams[1].active.combatant, ability=ability)
    assert hooks.move(GROWL, "wanted", teams[0], teams[1], 0, arena, None, default=False) is wanted
