import json
from pathlib import Path

import pytest
from fixed_clock import fixed_now
from test_commands import CHANNEL, handler, lineups, member
from test_gym_api import FULL
from test_gym_api import FakePokeAPI as GymPokeAPI

from ypoke import entry_rules
from ypoke.combatants import combatant
from ypoke.commands import BATTLE_COMMAND, result_blocks
from ypoke.gym_battle import GymBattles
from ypoke.store import Store

ETERNATUS, ROTOM, ROTOM_WASH, SNORLAX, PIKACHU, SQUIRTLE = 890, 479, 10009, 143, 25, 7


@pytest.fixture
def store(tmp_path):
    return Store(tmp_path / "ypoke.sqlite3", fixed_now)


@pytest.fixture
def fought(monkeypatch):
    """Every member dict a battle built a fighter from, in order."""
    members = []

    def spy(pokeapi, member):
        members.append(member)
        return combatant(pokeapi, member)

    for module in ("commands", "gym_battle"):
        monkeypatch.setattr(f"ypoke.{module}.combatant", spy)
        monkeypatch.setattr(f"ypoke.{module}.ThreadPoolExecutor", SerialPool)
    return members


class SerialPool:
    """Builds fighters one by one, so `fought` keeps the battle's order."""

    def __init__(self, max_workers=None):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def map(self, function, items):
        return map(function, items)


def holding(pokemon_id, item=None, level=50, shiny=False):
    return {**member(pokemon_id, level), "shiny": shiny, **({"held_item": item} if item else {})}


def six_eternatus():
    return [holding(ETERNATUS, "black-sludge", shiny=True)] + [holding(ETERNATUS) for _ in range(5)]


def context_lines(reply):
    return [element["text"] for element in result_blocks(reply)[0]["elements"]]


def test_six_eternatus_send_one_and_the_card_says_why(store, fought):
    store.issue_token("UA")
    store.save_party("UA", six_eternatus())
    store.issue_token("UB")
    store.save_party("UB", [member(species, 50) for species in (25, 26, 172, 417, 587)])
    reply = handler(store).handle("UA", "<@UB> 6")
    assert [len(side) for side in lineups(reply)] == [1, 5]
    assert " · 1:5 · " in reply.summary
    assert [m["pokemon_id"] for m in fought[:1]] == [ETERNATUS] and fought[0]["held_item"] == "black-sludge"
    assert f"<@UA>: {entry_rules.SPECIES_NOTE}" in context_lines(reply)
    assert not any("<@UB>" in line for line in context_lines(reply))


def test_forms_of_one_species_count_once(store, fought):
    store.issue_token("UA")
    store.save_party("UA", [member(ROTOM_WASH, 50), member(ROTOM, 50), member(PIKACHU, 50)])
    store.issue_token("UB")
    store.save_party("UB", [member(SQUIRTLE, 50)])
    reply = handler(store).handle("UA", "<@UB> 3")
    assert [m["pokemon_id"] for m in fought[:2]] == [ROTOM_WASH, PIKACHU]
    assert " · 2:1 · " in reply.summary


@pytest.mark.parametrize("pokemon_id, species", [(10100, 26), (10190, ETERNATUS), (10999, 10999), (PIKACHU, PIKACHU)])
def test_a_form_id_maps_to_its_species_and_an_unknown_one_to_itself(pokemon_id, species):
    assert entry_rules.species_id(pokemon_id) == species


def test_every_female_variety_the_app_uploads_maps_to_its_species():
    varieties = json.loads((Path(__file__).resolve().parents[2] / "data/gender-differences.json").read_text())
    assert varieties["femaleVarieties"]
    for variety in varieties["femaleVarieties"]:
        assert entry_rules.species_id(variety["pokemonID"]) == variety["speciesID"], variety["name"]


def test_a_later_holder_of_the_same_item_fights_without_it(store, fought):
    store.issue_token("UA")
    store.save_party("UA", [holding(SNORLAX, "leftovers"), holding(PIKACHU, "leftovers")])
    store.issue_token("UB")
    store.save_party("UB", [member(SQUIRTLE, 50)])
    reply = handler(store).handle("UA", "<@UB> 2")
    assert [m.get("held_item") for m in fought[:2]] == ["leftovers", None]
    assert f"<@UA>: {entry_rules.ITEM_NOTE}" in context_lines(reply)
    assert f"<@UA>: {entry_rules.SPECIES_NOTE}" not in context_lines(reply)


def test_a_clean_party_fights_as_uploaded_with_no_note(store, fought):
    party = [holding(SNORLAX, "leftovers"), holding(PIKACHU, "light-ball"), holding(SQUIRTLE)]
    assert entry_rules.lineup(party) == entry_rules.Lineup(tuple(party), (0, 1, 2), ())
    store.issue_token("UA")
    store.save_party("UA", party)
    store.issue_token("UB")
    store.save_party("UB", [member(SQUIRTLE, 50)])
    reply = handler(store).handle("UA", "<@UB> 3")
    assert fought[:3] == party
    assert reply.card.rules == ()


def test_a_duplicate_past_the_asked_size_is_no_news(store):
    store.issue_token("UA")
    store.save_party("UA", [member(ETERNATUS, 50), member(PIKACHU, 50), member(ETERNATUS, 50)])
    store.issue_token("UB")
    store.save_party("UB", [member(SQUIRTLE, 50)])
    reply = handler(store).handle("UA", "<@UB> 2")
    assert " · 2:1 · " in reply.summary
    assert reply.card.rules == ()


def test_practice_rematch_and_pending_battles_apply_the_rules(store, fought):
    store.issue_token("UA")
    store.save_party("UA", six_eternatus())
    bot = handler(store)
    practice = bot.handle("UA", "<@UBOT> 6", BATTLE_COMMAND)
    assert [len(side) for side in lineups(practice)] == [1, 1]
    rematch = bot.rematch("UA", "UA:UBOT:6", CHANNEL, "9.9")
    assert [len(side) for side in lineups(rematch)] == [1, 1]
    bot.handle("UA", "<@UB> 6", BATTLE_COMMAND, CHANNEL)
    store.issue_token("UB")
    store.save_party("UB", [member(SQUIRTLE, 50)] * 2)
    [delivery] = bot.run_pending("UB")
    assert [len(side) for side in lineups(delivery.reply)] == [1, 1]
    assert {f"<@UA>: {entry_rules.SPECIES_NOTE}", f"<@UB>: {entry_rules.SPECIES_NOTE}"} <= set(context_lines(delivery.reply))
    assert delivery.reply.card.note is not None


def test_the_gym_api_benches_a_species_duplicate_and_keeps_the_team_length(fought):
    team = [holding(ETERNATUS, "leftovers", level=5), holding(ETERNATUS), holding(SNORLAX, "leftovers")]
    body = GymBattles(GymPokeAPI(), new_seed=lambda: 1).battle("kanto-1", team)
    assert [member["hp"] for member in body["player_team"]][:2] == [0, None]
    assert len(body["player_team"]) == 3
    assert [m.get("held_item") for m in fought[:3]] == ["leftovers", None, None]
    switched = [event["member"] for event in body["events"] if event["type"] == "switch" and event["side"] == 0]
    assert switched[:2] == [0, 2]


def test_a_hideout_step_carries_a_benched_duplicate_as_it_came(fought):
    team = [holding(ETERNATUS), holding(ETERNATUS), holding(SNORLAX)]
    carried = [FULL, {"hp": 40, "status": None}, FULL]
    body = GymBattles(GymPokeAPI(), new_seed=lambda: 1).battle("kanto-hideout-1", team, carried)
    assert body["won"] and [member["hp"] for member in body["player_team"]] == [0, None, 22]
    assert body["carry"][1] == {"hp": 40, "status": None}
    assert [m["pokemon_id"] for m in fought[:3]] == [ETERNATUS, ETERNATUS, SNORLAX]


def test_a_hideout_step_whose_only_standing_member_is_benched_is_refused():
    team = [holding(ETERNATUS), holding(ETERNATUS)]
    with pytest.raises(Exception, match="no member can still fight"):
        GymBattles(GymPokeAPI(), new_seed=lambda: 1).battle("kanto-hideout-2", team, [{"hp": 0, "status": None}, FULL])
