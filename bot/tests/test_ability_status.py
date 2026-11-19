import random
from dataclasses import replace

import pytest
from attacks import attack
from status_moves import data_move, resolve
from test_ability_damage import TACKLE, facing, hit
from test_battle import mon
from test_held_items_more import FixedRng

from ypoke import battle
from ypoke.battle import (
    AbilityAct,
    Action,
    BattleResult,
    Change,
    StatusDamage,
    _Arena,
    _Fighter,
    _Team,
)
from ypoke.effects.conditions import hurts
from ypoke.narration import battle_turns

THUNDER_WAVE, SPORE, TOXIC, TAUNT = data_move(86), data_move(147), data_move(92), data_move(269)
HEX, DREAM_EATER, DOUBLE_EDGE = attack(506), attack(138), attack(38)
WEAK = {"attack": 10, "special_attack": 10}


@pytest.mark.parametrize(("ability", "ailment", "blocked"), [
    ("vital-spirit", "sleep", True), ("vital-spirit", "paralysis", False), ("sweet-veil", "sleep", True),
    ("magma-armor", "freeze", True), ("pastel-veil", "poison", True), ("pastel-veil", "toxic", True),
    ("pastel-veil", "burn", False), ("comatose", "burn", True), ("comatose", "confusion", False),
])
def test_the_ability_keeps_its_ailments_off_the_holder(ability, ailment, blocked):
    holder, _, _ = facing(ability)
    assert battle._blocks_ailment(holder, ailment) == blocked


@pytest.mark.parametrize(("weather", "ailment", "blocked"), [
    ("sun", "paralysis", True), ("sun", "sleep", True), ("sun", "confusion", False), (None, "paralysis", False),
])
def test_leaf_guard_keeps_a_status_off_only_in_sun(weather, ailment, blocked):
    holder, _, arena = facing("leaf-guard")
    arena.weather.kind = weather
    assert battle._blocks_ailment(holder, ailment) == blocked


@pytest.mark.parametrize(("types", "guarded"), [(("grass",), True), (("fairy",), False)])
def test_flower_veil_guards_a_grass_holder_only(types, guarded):
    holder, foe, _ = facing("flower-veil", user_types=types)
    assert battle._blocks_ailment(holder, "burn") == guarded
    assert (battle.shift_stage(holder, 0, "attack", -1, by=foe) is None) == guarded


@pytest.mark.parametrize(("ability", "blocked"), [("aroma-veil", "aroma-veil"), (None, "")])
def test_aroma_veil_stops_taunt(ability, blocked):
    user, foe, arena = facing(None, ability)
    assert resolve(user, foe, TAUNT, arena).blocked == blocked


def test_synchronize_gives_a_foes_paralysis_back_to_it():
    user, foe, arena = facing(None, "synchronize")
    resolve(user, foe, THUNDER_WAVE, arena)
    assert (foe.status, user.status) == ("paralysis", "paralysis")
    [act] = arena.log
    assert (act.side, act.ability, act.changes) == (1, "synchronize", (Change(0, "사용자", "paralysis"),))


@pytest.mark.parametrize(("move", "foe_ability", "user_status"), [
    (SPORE, "synchronize", None), (THUNDER_WAVE, None, None), (TOXIC, "synchronize", "toxic"),
])
def test_synchronize_passes_only_burn_paralysis_and_poison(move, foe_ability, user_status):
    user, foe, arena = facing(None, foe_ability)
    resolve(user, foe, move, arena)
    assert user.status == user_status


def test_synchronize_does_not_bounce_between_two_holders():
    user, foe, arena = facing("synchronize", "synchronize")
    resolve(user, foe, THUNDER_WAVE, arena)
    assert (foe.status, user.status, len(arena.log)) == ("paralysis", "paralysis", 1)


@pytest.mark.parametrize(("ability", "draw", "cured"), [
    ("shed-skin", 0.1, True), ("shed-skin", 0.5, False), (None, 0.1, False),
])
def test_shed_skin_may_cure_before_the_poison_hurts(ability, draw, cured):
    holder, _, arena = facing(ability)
    holder.status = "poison"
    events = []
    battle._end_of_turn(1, arena.teams, arena.weather, arena, FixedRng(draw), events)
    assert (holder.status is None, holder.hp == holder.max_hp) == (cured, cured)


@pytest.mark.parametrize(("weather", "cured"), [("rain", True), ("sun", False)])
def test_hydration_cures_in_rain(weather, cured):
    holder, _, arena = facing("hydration")
    holder.status = "burn"
    arena.weather.kind = weather
    events = []
    battle._cure_upkeep(1, (holder, arena.teams[1].active), events, random.Random(0))
    assert (holder.status is None) == cured and bool(events) == cured


@pytest.mark.parametrize(("ability", "status", "hp_share", "after"), [
    ("natural-cure", "poison", 2, (None, 50)), ("regenerator", "burn", 2, ("burn", 83)),
    (None, "poison", 2, ("poison", 50)), ("regenerator", None, 1, (None, 100)),
])
def test_the_ability_acts_as_its_holder_switches_out(ability, status, hp_share, after):
    team, arena = bench(ability, status, hp_share)
    leaver = team.fighters[0]
    assert (leaver.status, leaver.hp_percent) == after
    assert len(arena.log) == (after != (status, 100 // hp_share))


@pytest.mark.parametrize(("status", "events", "sign", "share"), [
    ("poison", [AbilityAct], 1, 8), ("burn", [StatusDamage], -1, 16),
])
def test_poison_heal_heals_by_poison_only(status, events, sign, share):
    holder, foe, arena = facing("poison-heal")
    holder.hp, holder.status = holder.max_hp // 2, status
    before, log = holder.hp, []
    battle._status_upkeep(1, arena.teams, (holder, foe), log)
    assert [type(event) for event in log] == events
    assert holder.hp - before == sign * (holder.max_hp // share)


def test_poison_heal_shows_nothing_at_full_hp():
    holder, foe, arena = facing("poison-heal")
    holder.status, log = "toxic", []
    battle._status_upkeep(1, arena.teams, (holder, foe), log)
    assert log == [] and holder.hp == holder.max_hp


@pytest.mark.parametrize(("ability", "spared"), [("magic-guard", True), (None, False)])
def test_magic_guard_spares_its_holder_every_indirect_damage(ability, spared):
    holder, foe, arena = facing(ability)
    holder.status = "poison"
    battle._status_upkeep(1, arena.teams, (holder, foe), [])
    assert (holder.hp == holder.max_hp) == spared
    assert battle._chipped_by(holder, "sandstorm") != spared
    holder.hp = holder.max_hp
    resolve(holder, foe, DOUBLE_EDGE, arena)
    assert (holder.hp == holder.max_hp) == spared


def test_comatose_counts_as_asleep_for_the_foes_moves():
    assert hit(HEX, None, "comatose", foe_types=("psychic",)) > 1.8 * hit(HEX, foe_types=("psychic",))
    user, foe, arena = facing(None, "comatose")
    assert not resolve(user, foe, DREAM_EATER, arena).failed
    user, foe, arena = facing()
    assert resolve(user, foe, DREAM_EATER, arena).failed


@pytest.mark.parametrize(("ability", "status"), [("corrosion", "toxic"), (None, None)])
def test_corrosion_poisons_a_steel_foe(ability, status):
    user, foe, arena = facing(ability, foe_types=("steel",))
    resolve(user, foe, TOXIC, arena)
    assert foe.status == status


@pytest.mark.parametrize(("ability", "sleep_left", "asleep_turns"), [
    ("early-bird", 2, 1), ("early-bird", 1, 0), (None, 2, 2), (None, 1, 1),
])
def test_early_bird_wakes_in_half_the_turns(ability, sleep_left, asleep_turns):
    holder, _, _ = facing(ability)
    holder.status, holder.sleep_left = "sleep", sleep_left
    blocked = [battle._start_of_action(holder, TACKLE, random.Random(0))[1] for _ in range(3)]
    assert blocked.count("sleep") == asleep_turns


@pytest.mark.parametrize(("foe_ability", "ailment", "wanted"), [
    (None, "toxic", True), ("poison-heal", "toxic", False), ("magic-guard", "poison", False),
    ("synchronize", "toxic", False), ("synchronize", "sleep", True),
])
def test_the_chooser_leaves_off_a_status_the_foes_ability_turns_against_it(foe_ability, ailment, wanted):
    user, foe, _ = facing(None, foe_ability)
    assert hurts(ailment, user, foe, None) == wanted


@pytest.mark.parametrize(("event", "line"), [
    (AbilityAct(1, 0, "사용자", "shed-skin", changes=(Change(0, "사용자", "cure"),)), "🔵 사용자 [탈피] 상태 회복"),
    (AbilityAct(1, 0, "사용자", "regenerator", hp=73), "🔵 사용자 [재생력] 73%"),
    (AbilityAct(1, 1, "상대", "synchronize", changes=(Change(0, "사용자", "paralysis"),)), "🔴 상대 [싱크로] → 사용자 ⚡마비"),
])
def test_the_lines_name_the_ability(event, line):
    opening = Action(1, 0, "사용자", "상대", TACKLE.name)
    [(_, lines)] = battle_turns(BattleResult(winner=0, turns=1, events=[opening, event]))
    assert lines[1:] == [line]


def bench(ability, status, hp_share):
    """A two-member team whose first member, holding `ability`, leaves at 1/`hp_share` HP with `status`."""
    arena = _Arena()
    first = replace(mon("사용자", ("normal",), **WEAK), ability=ability)
    team = _Team((first, mon("동료", ("normal",))), arena=arena)
    arena.teams = (team, _Team((mon("상대", ("normal",)),), arena=arena, side=1))
    leaver: _Fighter = team.active
    leaver.hp, leaver.status = leaver.max_hp // hp_share, status
    team.bench_active()
    return team, arena
