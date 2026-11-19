import random
from dataclasses import replace
from types import SimpleNamespace

from status_moves import data_move, put, resolve, weather
from test_battle import TACKLE, mon

from ypoke import abilities, battle, narration
from ypoke.battle import (
    AbilityTrigger,
    Action,
    Change,
    Move,
    StatusDamage,
    WeatherDamage,
    _Arena,
    _Team,
    simulate,
)
from ypoke.effects import hooks

ENDURE, ENDEAVOR, GROWL = (data_move(move_id) for move_id in (203, 283, 45))
HUGE_HIT = Move("큰기술", "normal", 250, physical=True, accuracy=100)
SANDACONDA = replace(mon("사다이사", ("ground",), hp=72, attack=107, defense=125, special_attack=65,
                         special_defense=70, speed=71, moves=(ENDURE, ENDEAVOR)), ability="sand-spit", pokemon_id=844)
BRUTE = mon("상대", ("normal",), attack=200, speed=50, moves=(HUGE_HIT,))


def test_sand_spit_starts_a_sandstorm_when_a_damaging_move_hits_the_holder():
    arena = _Arena()
    holder, foe = put(SANDACONDA, arena), put(BRUTE, arena, 1)
    resolve(foe, holder, GROWL, arena)
    assert arena.weather.kind is None
    resolve(foe, holder, TACKLE, arena)
    assert arena.weather.kind == "sandstorm" and arena.weather.turns_left == battle.WEATHER_TURNS
    assert arena.log == [AbilityTrigger(0, "사다이사", "sand-spit", weather="sandstorm")]
    assert narration._entry_segment(arena.log[0]) == "🔵 사다이사 [모래뿜기] 🏜️"


def test_sand_spit_does_nothing_through_a_substitute_or_in_a_sandstorm_already_up():
    arena = _Arena()
    holder, foe = put(SANDACONDA, arena), put(BRUTE, arena, 1)
    holder.volatiles["substitute"] = holder.max_hp
    resolve(foe, holder, TACKLE, arena)
    assert arena.weather.kind is None
    del holder.volatiles["substitute"]
    arena.log.clear()
    arena.weather = weather("sandstorm")
    arena.weather.turns_left = 2
    resolve(foe, holder, TACKLE, arena)
    assert arena.weather.turns_left == 2 and not arena.log


def test_sand_veil_makes_moves_miss_more_in_a_sandstorm_and_spares_its_holder_the_chip():
    veiled = replace(mon("보호", ("normal",)), ability="sand-veil")
    arena = _Arena()
    holder, foe = put(veiled, arena), put(BRUTE, arena, 1)
    assert hooks.ability(holder, "accuracy_as_target", TACKLE, holder, default=1.0) == 1.0
    assert battle._weather_chip(holder, "sandstorm") == 0 < battle._weather_chip(foe, "sandstorm")
    seed = next(seed for seed in range(100) if 0.8 <= random.Random(seed).random())
    assert not resolve(foe, holder, TACKLE, arena, seed=seed).missed
    arena.weather = weather("sandstorm")
    assert hooks.ability(holder, "accuracy_as_target", TACKLE, holder, default=1.0) == 0.8
    assert resolve(foe, holder, TACKLE, arena, seed=seed).missed


def test_shed_skin_cures_its_holder_at_the_end_of_a_turn_one_time_in_three():
    arena = _Arena()
    holder, foe = put(replace(SANDACONDA, ability="shed-skin"), arena), put(BRUTE, arena, 1)
    holder.status = "toxic"
    events = []
    battle._cure_upkeep(1, (holder, foe), events, SimpleNamespace(random=lambda: 0.5))
    assert holder.status == "toxic" and not events
    battle._cure_upkeep(1, (holder, foe), events, SimpleNamespace(random=lambda: 0.1))
    assert holder.status is None
    assert events == [AbilityTrigger(0, "사다이사", "shed-skin", change=Change(0, "사다이사", "cure"))]
    assert narration._entry_segment(events[0]) == "🔵 사다이사 [탈피] 자신 상태 회복"


def test_shed_skin_cures_before_the_status_hurts_at_the_end_of_the_turn():
    arena = _Arena()
    arena.teams = teams = (_Team((replace(SANDACONDA, ability="shed-skin"),), arena=arena),
                           _Team((BRUTE,), arena=arena, side=1))
    holder = teams[0].active
    holder.status = "toxic"
    events = []
    seed = next(seed for seed in range(100) if random.Random(seed).random() < abilities.SHED_SKIN_CHANCE)
    battle._end_of_turn(1, teams, weather(None), arena, random.Random(seed), events)
    assert holder.status is None and holder.hp == holder.max_hp
    assert not any(isinstance(event, StatusDamage) for event in events)


def test_sandaconda_endures_the_hit_that_starts_its_sand_then_endeavors_and_the_sand_finishes_the_foe():
    result = simulate(((SANDACONDA, mon("후속", ("rock",))), (BRUTE,)), seed=0)
    acts = [event for event in result.events if isinstance(event, Action) and event.side == 0]
    assert acts[0].turn == 1 and acts[0].effect == "endure"
    assert AbilityTrigger(0, "사다이사", "sand-spit", weather="sandstorm") in result.events
    assert acts[1].turn == 2 and acts[1].move == ENDEAVOR.name and acts[1].defender_hp == 1
    assert WeatherDamage(2, 1, "상대", 0, True, "sandstorm") in result.events and result.winner == 0
