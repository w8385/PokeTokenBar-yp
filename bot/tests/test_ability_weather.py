import random
from dataclasses import replace

import pytest
from attacks import attack
from status_moves import resolve
from test_ability_damage import facing, hit
from test_battle import mon

from ypoke import battle, move_power
from ypoke.battle import (
    AbilityAct,
    AbilityTrigger,
    Action,
    BattleResult,
    WeatherDamage,
    WeatherEnd,
    _Arena,
    _Team,
    _Weather,
)
from ypoke.effects import hooks
from ypoke.narration import battle_turns

EMBER, SURF, SOLAR_BEAM, WEATHER_BALL = attack(52), attack(57), attack(76), attack(311)
RAIN_DANCE = attack(240)


def weathered(kind, user_ability=None, foe_ability=None, **user_stats):
    user, foe, arena = facing(user_ability, foe_ability, **user_stats)
    arena.weather = _Weather(kind, 5)
    arena.weather.teams = arena.teams
    return user, foe, arena


@pytest.mark.parametrize(("ability", "chipped"), [("air-lock", False), ("cloud-nine", False), (None, True)])
def test_air_lock_stops_the_sandstorm_chip_while_the_weather_counts_down(ability, chipped):
    holder, foe, arena = weathered("sandstorm", ability)
    events = []
    battle._weather_upkeep(1, (holder, foe), arena.weather, events)
    assert any(isinstance(event, WeatherDamage) for event in events) == chipped
    assert (arena.weather.current, arena.weather.turns_left) == ("sandstorm", 4)
    assert battle._weather_of(foe) == (None if ability else "sandstorm")


@pytest.mark.parametrize(("weather", "foe_ability", "boosted"), [
    ("sun", "air-lock", False), ("sun", None, True), (None, None, False),
])
def test_air_lock_lifts_the_sun_boost_from_a_fire_move(weather, foe_ability, boosted):
    user, foe, arena = weathered(weather, foe_ability=foe_ability)
    resolve(user, foe, EMBER, arena)
    _, plain, plain_arena = weathered(None)
    resolve(plain_arena.teams[0].active, plain, EMBER, plain_arena)
    assert (foe.max_hp - foe.hp > plain.max_hp - plain.hp) == boosted


def primal(ability="desolate-land"):
    holder, foe, arena = weathered(None, ability)
    trigger = hooks.ability(holder, "on_entry", holder, foe, 0, arena.weather)
    return holder, foe, arena, trigger


def test_desolate_land_sets_a_sun_with_no_countdown():
    holder, foe, arena, trigger = primal()
    assert trigger == AbilityTrigger(0, "사용자", "desolate-land", weather="sun")
    assert (arena.weather.current, arena.weather.lasting) == ("sun", True)
    battle._weather_upkeep(1, (holder, foe), arena.weather, [])
    assert arena.weather.current == "sun"


def test_desolate_land_makes_water_moves_fail_and_the_ai_drops_them():
    holder, foe, arena, _ = primal()
    action = resolve(foe, holder, SURF, arena)
    assert action.failed and action.weather == "sun" and holder.hp == holder.max_hp
    assert battle._move_score(foe, holder, SURF, "sun") == 0.0


def test_a_plain_sun_only_weakens_water_moves():
    holder, foe, arena = weathered("sun")
    action = resolve(foe, holder, SURF, arena)
    assert not action.failed and holder.hp < holder.max_hp
    assert battle._move_score(foe, holder, SURF, "sun") > 0


def test_primordial_sea_makes_fire_moves_fail():
    holder, foe, arena, _ = primal("primordial-sea")
    assert arena.weather.current == "rain"
    assert resolve(foe, holder, EMBER, arena).failed


def test_air_lock_lets_water_moves_through_desolate_land():
    holder, foe, arena, _ = primal()
    foe.combatant = replace(foe.combatant, ability="air-lock")
    assert not resolve(foe, holder, SURF, arena).failed


def test_rain_dance_and_drizzle_cannot_replace_desolate_land():
    holder, foe, arena, _ = primal()
    action = resolve(foe, holder, RAIN_DANCE, arena)
    assert action.failed and action.weather == "sun"
    foe.combatant = replace(foe.combatant, ability="drizzle")
    assert hooks.ability(foe, "on_entry", foe, holder, 1, arena.weather) is None
    assert arena.weather.current == "sun"


@pytest.mark.parametrize(("holder_out", "ends"), [(True, False), (False, True)])
def test_desolate_land_ends_once_its_holder_is_gone(holder_out, ends):
    holder, _, arena, _ = primal()
    holder.hp = holder.hp if holder_out else 0
    events = []
    battle._calm_winds(1, arena.teams, arena.weather, events)
    assert (events == [WeatherEnd(1, "sun")]) == ends
    assert arena.weather.current == (None if ends else "sun")


@pytest.mark.parametrize(("ability", "weather", "healed"), [
    ("rain-dish", "rain", True), ("rain-dish", "sun", False), ("ice-body", "snow", True), ("ice-body", "hail", True),
    ("ice-body", "rain", False), (None, "rain", False),
])
def test_a_weather_heal_ability_heals_a_sixteenth_in_its_weather(ability, weather, healed):
    holder, foe, _ = weathered(weather, ability)
    holder.hp = holder.max_hp // 2
    before, events = holder.hp, []
    battle._ability_upkeep(1, (holder, foe), events, random.Random(0))
    assert holder.hp - before == (holder.max_hp // 16 if healed else 0)
    assert [type(event) for event in events] == ([AbilityAct] if healed else [])


@pytest.mark.parametrize(("ability", "chipped"), [("ice-body", False), (None, True)])
def test_ice_body_takes_no_hail_chip(ability, chipped):
    holder, _, _ = weathered("hail", ability)
    assert battle._chipped_by(holder, "hail") == chipped


@pytest.mark.parametrize(("status", "foe_ability", "share"), [
    ("sleep", None, 8), ("paralysis", None, 0), (None, None, 0), ("sleep", "magic-guard", 0),
])
def test_bad_dreams_hurts_a_sleeping_foe_an_eighth(status, foe_ability, share):
    holder, foe, _ = facing("bad-dreams", foe_ability)
    foe.status = status
    events = []
    battle._ability_upkeep(1, (holder, foe), events, random.Random(0))
    assert foe.max_hp - foe.hp == (foe.max_hp // share if share else 0)
    assert bool(events) == bool(share)


def test_bad_dreams_can_knock_the_last_foe_out_and_says_so():
    _, foe, arena = facing("bad-dreams")
    foe.status, foe.hp = "sleep", 1
    events = []
    assert battle._end_of_turn(1, arena.teams, arena.weather, arena, random.Random(0), events) == 1
    [act] = [event for event in events if isinstance(event, AbilityAct)]
    assert (act.foe, act.foe_hp, act.foe_fainted) == ("상대", 0, True)


def test_mega_sol_powers_fire_moves_as_in_sun_even_in_the_rain():
    assert hit(EMBER, "mega-sol", weather="rain") == pytest.approx(hit(EMBER, weather="rain") * 3, rel=0.05)
    assert hit(SURF, "mega-sol") == pytest.approx(hit(SURF) * 0.5, rel=0.05)
    assert hit(SOLAR_BEAM, "mega-sol", weather="rain") == pytest.approx(hit(SOLAR_BEAM, weather="rain") * 2, rel=0.05)


def test_mega_sol_turns_weather_ball_into_a_fire_move():
    holder, _, _ = facing("mega-sol")
    plain, _, _ = facing()
    assert move_power.typed(WEATHER_BALL, None, holder).type == "fire"
    assert move_power.typed(WEATHER_BALL, None, plain).type == "normal"


@pytest.mark.parametrize(("ability", "charges"), [("mega-sol", False), (None, True)])
def test_mega_sol_fires_solar_beam_at_once(ability, charges):
    holder, foe, arena = facing(ability)
    action = resolve(holder, foe, SOLAR_BEAM, arena)
    assert bool(action.effect) == charges and (foe.hp == foe.max_hp) == charges


def paradox(ability, field, **base):
    arena = _Arena()
    holder = replace(mon("사용자", ("normal",), **base), ability=ability)
    arena.teams = (_Team((holder,), arena=arena), _Team((mon("상대", ("normal",)),), arena=arena, side=1))
    arena.weather.teams = arena.teams
    if field == "electric-terrain":
        arena.terrain, arena.terrain_turns = field, 5
    else:
        arena.weather.kind = field
    return arena.teams[0].active


@pytest.mark.parametrize(("ability", "field", "base", "stat", "boost"), [
    ("protosynthesis", "sun", {"attack": 150}, "attack", 5325 / 4096),
    ("protosynthesis", "sun", {"speed": 150}, "speed", 1.5),
    ("quark-drive", "electric-terrain", {"special_defense": 150}, "special_defense", 5325 / 4096),
    ("protosynthesis", None, {"attack": 150}, "attack", 1.0),
    ("protosynthesis", "electric-terrain", {"attack": 150}, "attack", 1.0),
    ("quark-drive", "sun", {"attack": 150}, "attack", 1.0),
])
def test_a_paradox_ability_raises_the_highest_stat_in_its_field(ability, field, base, stat, boost):
    holder = paradox(ability, field, **base)
    before = holder.stat(stat)
    act = hooks.ability(holder, "on_update", holder, 0, 1)
    assert holder.stat(stat) == pytest.approx(before * boost)
    assert act == (AbilityAct(1, 0, "사용자", ability, effect="paradox", detail=stat) if boost != 1.0 else None)


def test_protosynthesis_fades_with_the_sun_and_wakes_again_when_it_returns():
    holder = paradox("protosynthesis", "sun", attack=150)
    act = hooks.ability(holder, "on_update", holder, 0, 1)
    [(_, lines)] = battle_turns(BattleResult(winner=0, turns=1, events=[Action(1, 0, "사용자", "상대", "몸통박치기"), act]))
    assert lines[-1].endswith("공격 강화")
    holder.arena.weather.kind = None
    assert hooks.ability(holder, "on_update", holder, 0, 2) is None
    assert holder.stat("attack") == holder.stat("attack", staged=False)
    holder.arena.weather.kind = "sun"
    assert hooks.ability(holder, "on_update", holder, 0, 3) == replace(act, turn=3)
