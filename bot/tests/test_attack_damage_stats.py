from attacks import attack, duel, first_seed
from status_moves import put
from test_attack_two_turn import act, armed
from test_battle import TACKLE, mon

from ypoke import battle

PSYSHOCK, FOUL_PLAY, BODY_PRESS, SHELL_SIDE_ARM = attack(473), attack(492), attack(776), attack(801)
SACRED_SWORD, SUNSTEEL_STRIKE = attack(533), attack(713)


def damage(user, foe, move):
    return battle._unrolled_damage(user, foe, move, 1.0, None)


def test_psyshock_hits_the_targets_defense_not_its_special_defense():
    user, foe, arena = duel()
    before = damage(user, foe, PSYSHOCK)
    foe.stages["special_defense"] = 2
    assert damage(user, foe, PSYSHOCK) == before
    foe.stages["defense"] = 2
    assert damage(user, foe, PSYSHOCK) < before
    user.status = "burn"
    assert damage(user, foe, PSYSHOCK) == damage(user, foe, battle.replace(PSYSHOCK, id=0))


def test_foul_play_uses_the_targets_attack_and_the_chooser_sees_it():
    user, foe, arena = duel()
    before, score = damage(user, foe, FOUL_PLAY), battle._move_score(user, foe, FOUL_PLAY, None)
    user.stages["attack"] = 2
    assert damage(user, foe, FOUL_PLAY) == before
    foe.stages["attack"] = 2
    raised = damage(user, foe, FOUL_PLAY)
    assert raised > before and battle._move_score(user, foe, FOUL_PLAY, None) > score
    user.status = "burn"
    assert damage(user, foe, FOUL_PLAY) < raised


def test_body_press_uses_the_users_defense():
    user, foe, arena = duel()
    before = damage(user, foe, BODY_PRESS)
    user.stages["attack"] = 2
    assert damage(user, foe, BODY_PRESS) == before
    user.stages["defense"] = 2
    assert damage(user, foe, BODY_PRESS) > before


def test_shell_side_arm_takes_the_class_that_deals_more_and_a_burn_halves_only_the_physical_one():
    user, foe, arena = duel()
    foe.stages["defense"] = -2
    assert battle.hooks.move(SHELL_SIDE_ARM, "stat_source", user, foe, None)[1:] == ("attack", "defense")
    physical = damage(user, foe, SHELL_SIDE_ARM)
    user.status = "burn"
    assert damage(user, foe, SHELL_SIDE_ARM) < physical
    foe.stages["defense"], foe.stages["special_defense"] = 0, -2
    assert battle.hooks.move(SHELL_SIDE_ARM, "stat_source", user, foe, None)[1:] == ("special_attack",
                                                                                      "special_defense")
    assert damage(user, foe, SHELL_SIDE_ARM) == physical


def test_sacred_sword_ignores_the_targets_defense_and_evasion_stages_but_not_the_users_attack():
    user, foe, arena = duel()
    before = damage(user, foe, SACRED_SWORD)
    foe.stages["defense"], foe.stages["evasion"] = 6, 6
    assert damage(user, foe, SACRED_SWORD) == before
    assert battle._accuracy_stages(user, foe, SACRED_SWORD) == 1.0 > battle._accuracy_stages(user, foe, TACKLE)
    user.stages["attack"] = 2
    assert damage(user, foe, SACRED_SWORD) > before


def test_sunsteel_strike_breaks_through_sturdy_but_a_contact_ability_still_acts():
    user, foe, arena = duel(attack=255)
    armed(user, SUNSTEEL_STRIKE)
    sturdy = put(mon("상대", ("normal",), hp=5), arena, 1, ability="sturdy")
    sturdy.combatant = battle.replace(sturdy.combatant, moves=(TACKLE,))
    assert act(user, sturdy, arena).knockout and sturdy.ability == "sturdy"
    armed(user, TACKLE)
    sturdy.hp = sturdy.max_hp
    assert not act(user, sturdy, arena).knockout
    armed(user, SUNSTEEL_STRIKE)
    static = put(mon("상대", ("normal",), defense=255, hp=255), arena, 1, ability="static")

    def paralyzed(seed):
        user.status, static.hp = None, static.max_hp
        act(user, static, arena, seed=seed)
        return user.status == "paralysis"

    assert paralyzed(first_seed(paralyzed)) and not static.ability_ignored


def test_the_chooser_and_the_hit_both_pass_an_ability_that_would_make_the_target_immune():
    user, foe, arena = duel()
    grounded = battle.replace(SUNSTEEL_STRIKE, type="ground")
    floating = put(mon("상대", ("normal",)), arena, 1, ability="levitate")
    armed(user, grounded)
    assert battle._move_score(user, floating, grounded, None) > 0 and act(user, floating, arena).defender_hp < 100
    assert battle._move_score(user, floating, battle.replace(grounded, id=0), None) == 0
