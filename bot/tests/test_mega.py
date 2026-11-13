from dataclasses import replace

import pytest

from ypoke import pokeapi
from ypoke.battle import AbilityTrigger, Action, BaseStats, Combatant, MegaEvolution, MegaForm, Move, simulate
from ypoke.mega_stones import MEGA_STONES, mega_form_id
from ypoke.narration import battle_card, battle_log
from ypoke.pokeapi import PokeAPIService
from ypoke.store import Store

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
MEGA = MegaForm(types=("fire", "dragon"), base=BaseStats(78, 130, 111, 130, 85, 100), ability="단단한발톱")


def mon(name, mega=None, types=("normal",), speed=80):
    return Combatant(
        name=name, level=50, types=types, base=BaseStats(60, 60, 60, 60, 60, speed), ivs=IVS, moves=(TACKLE,), mega=mega,
    )


def test_stone_only_works_on_its_own_pokemon():
    assert mega_form_id("charizardite-x", 6) == 10034
    assert mega_form_id("charizardite-x", 3) is None
    assert mega_form_id("leftovers", 6) is None
    assert mega_form_id(None, 6) is None


def test_every_stone_points_at_a_distinct_mega_form():
    assert len(MEGA_STONES) == 92
    assert len({form for _, form in MEGA_STONES.values()}) == 92


def test_mega_holder_evolves_before_turn_one_and_fights_with_mega_stats():
    holder, plain = mon("리자몽", MEGA), mon("상대")
    result = simulate((holder, plain), seed=3)
    assert result.events[0] == MegaEvolution(1, 0, "리자몽", "단단한발톱")
    assert sum(isinstance(event, MegaEvolution) for event in result.events) == 1
    assert result.winner == 0


def test_a_holder_further_back_evolves_as_it_is_sent_out():
    strong = replace(mon("강함", speed=200), base=BaseStats(100, 255, 100, 255, 100, 200))
    team = (replace(mon("첫째"), level=5), mon("둘째", MEGA))
    events = simulate((team, (strong,)), seed=3).events
    evolutions = [index for index, event in enumerate(events) if isinstance(event, MegaEvolution)]
    assert len(evolutions) == 1
    evolution = events[evolutions[0]]
    assert (evolution.side, evolution.pokemon) == (0, "둘째")
    assert [type(event).__name__ for event in events[evolutions[0] - 1:evolutions[0]]] == ["SendOut"]


def test_only_the_first_holder_of_a_side_evolves():
    strong = replace(mon("강함", speed=200), base=BaseStats(100, 255, 100, 255, 100, 200))
    team = (mon("첫째", MEGA), mon("둘째", MEGA), mon("셋째", MEGA))
    events = simulate((team, (strong,)), seed=3).events
    assert [event.pokemon for event in events if isinstance(event, MegaEvolution)] == ["첫째"]


def test_each_side_gets_its_own_mega_evolution():
    events = simulate(((mon("가", MEGA),), (mon("나", MEGA),)), seed=3).events
    assert sorted((event.side, event.pokemon) for event in events if isinstance(event, MegaEvolution)) == [
        (0, "가"), (1, "나")]


def test_a_mega_ability_fires_when_the_holder_is_sent_out_mid_battle():
    drought = replace(MEGA, ability="가뭄", ability_id="drought")
    strong = replace(mon("강함", speed=200), base=BaseStats(100, 255, 100, 255, 100, 200))
    team = (replace(mon("첫째"), level=5), mon("둘째", drought))
    events = simulate((team, (strong,)), seed=3).events
    triggers = [event for event in events if isinstance(event, AbilityTrigger)]
    assert [(trigger.pokemon, trigger.ability) for trigger in triggers] == [("둘째", "drought")]


def test_mega_swaps_in_the_mega_speed_and_types():
    slow_base = mon("느림", MegaForm(types=("fire",), base=BaseStats(60, 60, 60, 60, 60, 200)), speed=10)
    fast = mon("빠름", speed=100)
    first_mover = next(event for event in simulate((slow_base, fast), seed=1).events if isinstance(event, Action))
    assert first_mover.side == 0
    without = next(event for event in simulate((replace(slow_base, mega=None), fast), seed=1).events if isinstance(event, Action))
    assert without.side == 1


def test_a_known_mega_ability_takes_effect_on_entry():
    drought = replace(MEGA, ability="가뭄", ability_id="drought")
    holder = replace(mon("리자몽", drought), ability="blaze")
    triggers = [event for event in simulate((holder, mon("상대")), seed=3).events if isinstance(event, AbilityTrigger)]
    assert [(trigger.ability, trigger.weather) for trigger in triggers] == [("drought", "sun")]


def test_an_unknown_mega_ability_replaces_the_base_one_with_nothing():
    tough_claws = replace(MEGA, ability_id="tough-claws")
    holder = replace(mon("리자몽", tough_claws), ability="intimidate")
    events = simulate((holder, mon("상대")), seed=3).events
    assert not any(isinstance(event, AbilityTrigger) for event in events)


def test_missing_mega_ability_data_keeps_the_base_ability():
    holder = replace(mon("리자몽", replace(MEGA, ability=None)), ability="intimidate")
    events = simulate((holder, mon("상대")), seed=3).events
    assert any(isinstance(event, AbilityTrigger) and event.ability == "intimidate" for event in events)


def test_without_a_stone_the_battle_is_unchanged():
    sides = (mon("가"), mon("나"))
    assert not any(isinstance(event, MegaEvolution) for event in simulate(sides, seed=9).events)


def test_narration_announces_the_mega_evolution():
    holder, plain = mon("리자몽", MEGA), mon("상대")
    result = simulate((holder, plain), seed=3)
    assert battle_log(result)[0].splitlines()[1] == "🔵 리자몽 메가진화 [단단한발톱]"
    assert battle_card(("<@UA>", "<@UB>"), ((holder,), (plain,)), result).columns[0].splitlines()[1].startswith("리자몽(메가)")
    no_ability = replace(MEGA, ability=None)
    assert battle_log(simulate((replace(holder, mega=no_ability), plain), seed=3))[0].splitlines()[1] == "🔵 리자몽 메가진화"


@pytest.fixture
def service(tmp_path, monkeypatch):
    fetched = []
    body = {
        "name": "charizard-mega-x", "species": {"url": "https://pokeapi.co/api/v2/pokemon-species/6/"},
        "types": [{"slot": 2, "type": {"name": "dragon"}}, {"slot": 1, "type": {"name": "fire"}}],
        "stats": [{"stat": {"name": name}, "base_stat": value} for name, value in
                  (("hp", 78), ("attack", 130), ("defense", 111), ("special-attack", 130), ("special-defense", 85), ("speed", 100))],
        "abilities": [{"is_hidden": True, "ability": {"name": "hidden", "url": "https://pokeapi.co/api/v2/ability/1/"}},
                      {"is_hidden": False, "ability": {"name": "tough-claws", "url": "https://pokeapi.co/api/v2/ability/181/"}}],
    }

    def get_json(url):
        fetched.append(url)
        if "pokemon-species" in url:
            return {"names": [{"language": {"name": "ko"}, "name": "리자몽"}]}
        if "/ability/" in url:
            return {"name": "tough-claws", "names": [{"language": {"name": "ko"}, "name": "단단한발톱"}]}
        return body

    monkeypatch.setattr(pokeapi, "_get_json", get_json)
    return PokeAPIService(Store(str(tmp_path / "ypoke.db"))), fetched


def test_mega_form_reads_stats_types_and_the_visible_ability_once(service):
    api, fetched = service
    form = api.mega_form(10034)
    assert form["types"] == ["fire", "dragon"]
    assert form["base"]["attack"] == 130
    assert form["ability"] == "단단한발톱"
    assert form["ability_id"] == "tough-claws"
    calls = len(fetched)
    assert api.mega_form(10034) == form
    assert len(fetched) == calls
