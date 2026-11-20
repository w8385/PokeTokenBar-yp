from dataclasses import replace

import pytest
from status_moves import resolve
from test_ability_weather import weathered
from test_battle import SANDSTORM, TACKLE, mon
from test_sandaconda import BRUTE, HUGE_HIT, SANDACONDA
from test_status_switching import CHILLY_RECEPTION, act, squad

from ypoke import gym_battle
from ypoke.battle import WeatherDamage, simulate
from ypoke.narration import ABILITY_NAMES, _event_lines, battle_turns

CLEARERS = ("air-lock", "cloud-nine")
SAND_SETTER = replace(mon("모래", ("rock",), hp=120, defense=150, special_defense=150, moves=(TACKLE,)),
                      ability="sand-stream")


def lines_of(result):
    return [line for _, lines in battle_turns(result) for line in lines]


def chipped(result, side):
    return any(isinstance(event, WeatherDamage) and event.side == side for event in result.events)


@pytest.mark.parametrize("ability", CLEARERS)
def test_a_clearer_facing_sand_spit_says_on_entry_and_on_the_sand_that_the_weather_does_nothing(ability):
    assert chipped(simulate(((SANDACONDA,), (BRUTE,)), seed=0), 1)
    result = simulate(((SANDACONDA,), (replace(BRUTE, ability=ability),)), seed=0)
    name = ABILITY_NAMES[ability]
    assert f"🔴 상대 [{name}] 날씨 효과 없음" in lines_of(result)
    assert f"🔵 사다이사 [모래뿜기] 🏜️ ({name}: 효과 없음)" in lines_of(result)
    assert not chipped(result, 0) and not chipped(result, 1)
    gym_lines = [line["text"] for turn in gym_battle._log(result) for line in turn["lines"]]
    assert f"상대 [{name}] 날씨 효과 없음" in gym_lines


@pytest.mark.parametrize("ability", CLEARERS)
def test_sand_stream_against_a_clearer_on_entry_says_the_sand_does_nothing(ability):
    foe = mon("상대", ("normal",), moves=(TACKLE,))
    assert chipped(simulate(((SAND_SETTER,), (foe,)), seed=0), 1)
    result = simulate(((SAND_SETTER,), (replace(foe, ability=ability),)), seed=0)
    name = ABILITY_NAMES[ability]
    turn_one = battle_turns(result)[0][1]
    assert f"🔵 모래 [모래날림] 🏜️ ({name}: 효과 없음)" in turn_one
    assert f"🔴 상대 [{name}] 날씨 효과 없음" in turn_one
    assert not chipped(result, 1)


def test_a_clearer_sent_out_later_announces_itself_on_its_send_out_line():
    fodder = mon("약함", ("normal",), hp=10, defense=10, special_defense=10, speed=10, moves=(TACKLE,))
    holder = mon("레쿠쟈", ("dragon", "flying"), moves=(TACKLE,))
    setter = replace(SAND_SETTER, moves=(HUGE_HIT,))
    assert chipped(simulate(((setter,), (fodder, holder)), seed=0), 1)
    result = simulate(((setter,), (fodder, replace(holder, ability="air-lock"))), seed=0)
    assert "↪ 🔴 레쿠쟈 등장 [에어록] 날씨 효과 없음" in lines_of(result)
    assert not chipped(result, 1)


@pytest.mark.parametrize(("ability", "note"), [("air-lock", " (에어록: 효과 없음)"), (None, "")])
def test_a_weather_move_under_a_clearer_says_it_does_nothing(ability, note):
    user, foe, arena = weathered(None, foe_ability=ability)
    action = resolve(user, foe, SANDSTORM, arena)
    assert arena.weather.current == "sandstorm"
    assert _event_lines(action) == [f"🔵 사용자 › 모래바람 🏜️{note}"]


@pytest.mark.parametrize(("ability", "note"), [("cloud-nine", " (날씨부정: 효과 없음)"), (None, "")])
def test_chilly_reception_under_a_clearer_says_the_snow_does_nothing(ability, note):
    teams, arena = squad((CHILLY_RECEPTION,))
    foe = teams[1].active
    foe.combatant = replace(foe.combatant, ability=ability)
    arena.weather.teams = teams
    used, _ = act(teams, arena)
    assert arena.weather.current == "snow"
    assert _event_lines(used)[0].endswith(f"물러났다{note}")
