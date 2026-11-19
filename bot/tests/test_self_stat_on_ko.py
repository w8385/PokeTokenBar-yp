from attacks import attack
from test_ability_contact import MISSES, struck

from ypoke.battle import BattleResult, Change
from ypoke.narration import battle_turns

CLOSE_COMBAT, FLAME_CHARGE, ROCK_TOMB = attack(370), attack(488), attack(317)


def test_close_combat_lowers_its_users_defenses_even_when_it_knocks_the_foe_out():
    action, user, _ = struck(CLOSE_COMBAT, foe_hp=1, draw=MISSES)
    name = user.combatant.name
    assert action.knockout
    assert action.changes == (Change(0, name, "defense", -1), Change(0, name, "special_defense", -1))
    assert user.stages["defense"] == user.stages["special_defense"] == -1
    [(_, lines)] = battle_turns(BattleResult(winner=0, turns=1, events=[action]))
    assert lines[0].endswith("💥 효과 굉장 자신 방어↓")


def test_flame_charge_raises_its_users_speed_when_it_knocks_the_foe_out():
    action, user, _ = struck(FLAME_CHARGE, foe_hp=1, draw=MISSES)
    assert action.knockout and action.changes == (Change(0, user.combatant.name, "speed", 1),)


def test_a_knockout_does_not_lower_the_fainted_foes_stats():
    action, _, foe = struck(ROCK_TOMB, foe_hp=1, draw=MISSES)
    assert action.knockout and action.changes == () and foe.stages["speed"] == 0
