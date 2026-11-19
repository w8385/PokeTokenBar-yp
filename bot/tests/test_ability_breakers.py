import random
from dataclasses import replace

import pytest
from attacks import attack
from test_ability_damage import facing
from test_held_items_more import FixedRng

from ypoke import battle, narration
from ypoke.battle import AbilityEntry

TACKLE, EARTHQUAKE, SURF, SELF_DESTRUCT = attack(33), attack(89), attack(57), attack(120)
MISSES = 0.5


@pytest.mark.parametrize(("user_ability", "move", "foe_ability", "hurt"), [
    ("mold-breaker", EARTHQUAKE, "levitate", True), (None, EARTHQUAKE, "levitate", False),
    ("teravolt", SURF, "water-absorb", True), ("turboblaze", SURF, "water-absorb", True),
    (None, SURF, "water-absorb", False),
])
def test_mold_breaker_hits_through_the_targets_breakable_ability(user_ability, move, foe_ability, hurt):
    foe = struck(move, user_ability, foe_ability)
    assert (foe.hp < foe.max_hp) == hurt


def struck(move, user_ability, foe_ability):
    user, foe, arena = facing(user_ability, foe_ability)
    user.combatant = replace(user.combatant, moves=(move,))
    battle._resolve(1, 0, (user, foe), 0, arena.weather, FixedRng(MISSES), arena)
    return foe


@pytest.mark.parametrize(("user_ability", "picked"), [("mold-breaker", 1), (None, 0)])
def test_the_chooser_aims_past_levitate_with_mold_breaker(user_ability, picked):
    user, foe, _ = facing(user_ability, "levitate")
    user.combatant = replace(user.combatant, moves=(TACKLE, EARTHQUAKE))
    user.pp = [TACKLE.pp, EARTHQUAKE.pp]
    assert battle._best_move(user, foe, None) == picked


@pytest.mark.parametrize(("user_ability", "wasted"), [("mold-breaker", False), (None, True)])
def test_the_chooser_knows_mold_breaker_explodes_past_damp(user_ability, wasted):
    user, foe, _ = facing(user_ability, "damp")
    assert battle._wasted_on(user, foe, SELF_DESTRUCT) == wasted


@pytest.mark.parametrize(("foe_ability", "lowered"), [("neutralizing-gas", 0), (None, -1)])
def test_neutralizing_gas_keeps_the_foes_entry_ability_quiet(foe_ability, lowered):
    scared, gas, arena = facing("intimidate", foe_ability)
    battle._enter_battle((scared, gas), arena.weather, random.Random(0))
    assert gas.stages["attack"] == lowered


@pytest.mark.parametrize(("ability", "kept"), [("levitate", None), ("zen-mode", "zen-mode")])
def test_neutralizing_gas_spares_the_form_abilities(ability, kept):
    holder, _, _ = facing(ability, "neutralizing-gas")
    assert holder.ability == kept


@pytest.mark.parametrize(("foe_ability", "copied", "lowered"), [
    ("intimidate", "intimidate", -1), ("zen-mode", "trace", 0), (None, "trace", 0),
])
def test_trace_copies_the_foes_ability_and_runs_its_entry(foe_ability, copied, lowered):
    tracer, foe, arena = facing("trace", foe_ability)
    events = battle._enter_battle((tracer, foe), arena.weather, random.Random(0), entering=(0,))
    assert tracer.combatant.ability == copied
    assert foe.stages["attack"] == lowered
    if copied == "intimidate":
        assert [event.ability for event in events] == ["trace", "intimidate"]


@pytest.mark.parametrize(("event", "line"), [
    (AbilityEntry(0, "사용자", "mold-breaker", effect="breaks"), "🔵 사용자 [틀깨기] 상대 특성을 무시한다"),
    (AbilityEntry(1, "상대", "neutralizing-gas", effect="gas"), "🔴 상대 [화학변화가스] 상대 특성이 사라졌다"),
    (AbilityEntry(0, "사용자", "trace", effect="trace", detail="intimidate"), "🔵 사용자 [트레이스] 위협 복사"),
])
def test_the_entry_lines_name_the_ability(event, line):
    assert narration._entry_segment(event) == line
