from attacks import attack, duel
from test_attack_two_turn import act, armed

from ypoke import battle
from ypoke.battle import Change

FEINT, HYPERSPACE_HOLE, HYPER_DRILL, PHANTOM_FORCE = attack(364), attack(593), attack(887), attack(566)
TACKLE, QUICK_ATTACK = attack(33), attack(98)
LIFTED = "guard-lifted"


def test_feint_hits_through_protect_and_lifts_it():
    user, foe, arena = duel()
    armed(user, TACKLE, FEINT)
    foe.volatiles["protect"] = True
    assert act(user, foe, arena).blocked == "protect"
    feint = act(user, foe, arena, index=1)
    assert feint.defender_hp < 100 and Change(1, foe.combatant.name, LIFTED) in feint.changes
    assert "protect" not in foe.volatiles


def test_feint_on_an_unguarded_foe_lifts_nothing():
    user, foe, arena = duel()
    armed(user, FEINT)
    assert not [change for change in act(user, foe, arena).changes if change.kind == LIFTED]


def test_hyper_drill_passes_protect_without_lifting_it():
    user, foe, arena = duel()
    armed(user, HYPER_DRILL)
    foe.volatiles["kings-shield"] = True
    drill = act(user, foe, arena)
    assert drill.defender_hp < 100 and not drill.blocked and LIFTED not in {change.kind for change in drill.changes}
    assert "kings-shield" in foe.volatiles


def test_feint_passes_quick_guard_that_stops_other_priority_attacks():
    user, foe, arena = duel()
    armed(user, QUICK_ATTACK, FEINT)
    foe.volatiles["quick-guard"] = True
    assert act(user, foe, arena).blocked == "quick-guard"
    assert act(user, foe, arena, index=1).defender_hp < 100 and "quick-guard" not in foe.volatiles


def test_hyperspace_hole_passes_a_substitute_and_feint_does_not():
    user, foe, arena = duel()
    armed(user, HYPERSPACE_HOLE, FEINT)
    foe.volatiles["substitute"] = foe.max_hp
    assert act(user, foe, arena, index=1).defender_hp == 100
    assert act(user, foe, arena).defender_hp < 100 and foe.volatiles["substitute"] < foe.max_hp


def test_phantom_force_strikes_through_a_guard_raised_while_it_hid():
    user, foe, arena = duel(foe_types=("psychic",))
    armed(user, PHANTOM_FORCE)
    assert act(user, foe, arena).defender_hp == 100
    foe.volatiles["protect"] = True
    strike = act(user, foe, arena, turn=2)
    assert strike.defender_hp < 100 and Change(1, foe.combatant.name, LIFTED) in strike.changes


def test_the_chooser_scores_a_guard_breaker_against_a_guarded_foe():
    user, foe, arena = duel()
    foe.volatiles["protect"] = True
    assert battle._move_score(user, foe, TACKLE, None) == 0.0 < battle._move_score(user, foe, FEINT, None)
