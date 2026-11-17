import pytest

from ypoke import gym_battle, items
from ypoke.gym_battle import GymBattles

STATS = {"hp": 60, "attack": 60, "defense": 60, "special_attack": 60, "special_defense": 60, "speed": 60}


class Reached(Exception):
    pass


class FakePokeAPI:
    def __init__(self, can_evolve):
        self._can_evolve = can_evolve

    def pokemon(self, pokemon_id):
        return {"name_ko": f"#{pokemon_id}", "types": ["normal"], "base": STATS}

    def attacking_moves(self, pokemon_id, level, machine_ids=()):
        return []

    def can_evolve(self, pokemon_id):
        if isinstance(self._can_evolve, Exception):
            raise self._can_evolve
        return self._can_evolve


def player_sent_in(monkeypatch, held_item, can_evolve):
    seen = []

    def capture(sides, seed, starts, finale):
        seen.extend(sides[0])
        raise Reached

    monkeypatch.setattr(gym_battle, "simulate", capture)
    member = {"pokemon_id": 10, "level": 50, "ivs": {}, "shiny": False, "held_item": held_item}
    with pytest.raises(Reached):
        GymBattles(FakePokeAPI(can_evolve)).battle("kanto-1", [member])
    return seen[0]


def test_an_eviolite_holder_that_can_still_evolve_enters_a_gym_battle_as_one(monkeypatch):
    fighter = player_sent_in(monkeypatch, items.EVIOLITE, True)
    assert fighter.can_evolve is True
    assert items.stat_multiplier(fighter.item, "defense", fighter.can_evolve) > 1


def test_a_fully_evolved_eviolite_holder_gets_no_boost(monkeypatch):
    assert player_sent_in(monkeypatch, items.EVIOLITE, False).can_evolve is False


def test_a_failed_evolution_lookup_counts_as_fully_evolved(monkeypatch):
    assert player_sent_in(monkeypatch, items.EVIOLITE, OSError("offline")).can_evolve is False


def test_no_evolution_lookup_happens_for_any_other_item(monkeypatch):
    assert player_sent_in(monkeypatch, items.ASSAULT_VEST, OSError("must not be asked")).can_evolve is False
