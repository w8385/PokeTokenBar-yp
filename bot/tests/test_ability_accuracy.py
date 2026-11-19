import random

import pytest
from attacks import attack
from status_moves import data_move
from test_ability_damage import SWIFT, TACKLE, facing, hit

from ypoke import battle
from ypoke.battle import AbilityAct, _Weather
from ypoke.effects import hooks

THUNDER_WAVE, SHADOW_BALL = data_move(86), attack(247)


def foe_evasive(user, foe, arena):
    foe.stages["evasion"] = 2


def confused(user, foe, arena):
    foe.volatiles["confusion"] = 2


def sandstorm(user, foe, arena):
    arena.weather = _Weather("sandstorm", 5)


def snow(user, foe, arena):
    arena.weather = _Weather("snow", 5)


def hail(user, foe, arena):
    arena.weather = _Weather("hail", 5)


@pytest.mark.parametrize(("ability", "on_foe", "move", "prep", "expected"), [
    ("compound-eyes", False, TACKLE, None, 1.3), ("victory-star", False, TACKLE, None, 1.1),
    ("keen-eye", False, TACKLE, foe_evasive, 5 / 3), ("keen-eye", False, TACKLE, None, 1.0),
    ("minds-eye", False, TACKLE, foe_evasive, 5 / 3), ("unaware", False, TACKLE, foe_evasive, 5 / 3),
    ("tangled-feet", True, TACKLE, confused, 0.5), ("tangled-feet", True, TACKLE, None, 1.0),
    ("sand-veil", True, TACKLE, sandstorm, 0.8), ("sand-veil", True, TACKLE, None, 1.0),
    ("snow-cloak", True, TACKLE, sandstorm, 1.0), ("snow-cloak", True, TACKLE, snow, 0.8),
    ("snow-cloak", True, TACKLE, hail, 0.8), ("sand-veil", True, TACKLE, hail, 1.0),
    ("wonder-skin", True, THUNDER_WAVE, None, 50 / 90), ("wonder-skin", True, TACKLE, None, 1.0),
])
def test_the_ability_scales_accuracy_only_where_it_applies(ability, on_foe, move, prep, expected):
    abilities = (None, ability) if on_foe else (ability, None)
    assert accuracy(move, *abilities, prep=prep) / accuracy(move, prep=prep) == pytest.approx(expected)


def accuracy(move, user_ability=None, foe_ability=None, prep=None):
    user, foe, arena = facing(user_ability, foe_ability)
    if prep:
        prep(user, foe, arena)
    return battle._accuracy(user, foe, move)


def test_keen_eye_keeps_accuracy_from_a_foe_and_lets_other_stats_drop():
    keen, foe, arena = facing("keen-eye")
    assert battle.shift_stage(keen, 0, "accuracy", -1, by=foe) is None
    assert [type(event) for event in arena.log] == [AbilityAct] and arena.log[0].effect == "guard"
    assert battle.shift_stage(keen, 0, "attack", -1, by=foe) is not None


def test_scrappy_hits_ghosts_with_normal_and_fighting_moves_only():
    _, ghost, _ = facing("scrappy", foe_types=("ghost",))
    assert battle._multiplier(TACKLE, ghost) == 1.0
    _, ghost, _ = facing(foe_types=("ghost",))
    assert battle._multiplier(TACKLE, ghost) == 0.0
    assert battle._multiplier(SHADOW_BALL, ghost) == 2.0


def test_scrappy_shrugs_off_intimidate_and_says_so():
    scared, scrappy, arena = facing("intimidate", "scrappy")
    events = battle._enter_battle((scared, scrappy), arena.weather, random.Random(0))
    assert scrappy.stages["attack"] == 0
    assert [(event.ability, getattr(event, "effect", "")) for event in events] == [
        ("intimidate", ""), ("scrappy", "guard")]
    scared, plain, arena = facing("intimidate", "keen-eye")
    battle._enter_battle((scared, plain), arena.weather, random.Random(0))
    assert plain.stages["attack"] == -1


def test_crit_abilities_raise_force_or_block_critical_hits():
    lucky, poisoned, _ = facing("super-luck", "battle-armor")
    plain, _, _ = facing()
    assert hooks.ability(lucky, "crit_stage", default=0) == 1 and hooks.ability(plain, "crit_stage", default=0) == 0
    assert hooks.ability(poisoned, "guards_crit", default=False) and not hooks.ability(plain, "guards_crit", default=False)
    cruel, foe, _ = facing("merciless")
    assert not hooks.ability(cruel, "always_crits", foe, default=False)
    foe.status = "toxic"
    assert hooks.ability(cruel, "always_crits", foe, default=False)


def test_no_guard_makes_moves_hit_both_ways():
    guarded, foe, _ = facing("no-guard")
    assert battle._sure_hit(guarded, foe) and battle._sure_hit(foe, guarded)
    plain, foe, _ = facing()
    assert not battle._sure_hit(plain, foe)


def boosted(user, foe, arena):
    user.stages["attack"] = user.stages["special_attack"] = 2


def foe_walled(user, foe, arena):
    foe.stages["defense"] = 2


@pytest.mark.parametrize(("user_ability", "foe_ability", "prep", "expected"), [
    (None, "unaware", boosted, 1.0), ("unaware", None, foe_walled, 1.0),
    ("unaware", None, boosted, 2.0), (None, "unaware", foe_walled, 0.5),
])
def test_unaware_ignores_the_foes_stages_but_not_its_own(user_ability, foe_ability, prep, expected):
    assert hit(TACKLE, user_ability, foe_ability, prep=prep) / hit(TACKLE) == pytest.approx(expected, rel=0.02)
    assert hit(SWIFT, foe_ability=foe_ability) == hit(SWIFT)
