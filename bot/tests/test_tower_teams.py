import hashlib
import json
from collections import Counter
from pathlib import Path

import pytest

from tools import tower_balance
from ypoke import abilities, battle_data, foe_moves, tower, tower_teams
from ypoke.battle import NATURE_MODIFIERS
from ypoke.gyms import _related, species_table
from ypoke.move_effects import EFFECTS, STATUS_MOVES, attacks

LEARNSETS = Path(__file__).with_name("tower_learnsets.json")
OWNER_BUILDS = tuple(build for team in tower_teams.OWNER_TEAMS.values() for build in team)
ALL_BUILDS = (*tower_teams.BUILDS, *OWNER_BUILDS)
RUNS = 120
ARCHETYPE_BATTLES = [battle for battle in range(21, 101) if battle not in tower.OWNER_BATTLES]
WEATHER_SETTERS = {"rain": {"drizzle"}, "sun": {"drought", "orichalcum-pulse"}, "sand": {"sand-stream"},
                   "snow": {"snow-warning"}}
WEATHER_ABUSE = {"rain": ({"swift-swim"}, {"water"}), "sun": ({"chlorophyll", "solar-power"}, {"fire"}),
                 "sand": ({"sand-rush", "sand-force"}, {"rock", "ground", "steel"}),
                 "snow": ({"slush-rush", "ice-scales"}, {"ice"})}
RAIN_SURE_HITS = {87, 542}
LEAD_EFFECTS = {"stealth-rock", "spikes", "toxic-spikes", "sticky-web", "reflect", "light-screen", "aurora-veil",
                "yawn", "trick-room"}
SETUP_EFFECTS = {"stages", "swords-dance", "growth"}
CYCLE_EFFECTS = {"pivot", "parting-shot", "heal", "roost", "weather-heal", "wish"}
CYCLE_ABILITIES = {"regenerator", "intimidate", "multiscale", "magic-guard"}
HITTER_ITEMS = {"choice-band", "choice-specs", "choice-scarf", "focus-sash", "life-orb", "expert-belt", "assault-vest"}
ROOM_SPEED = 80
SETS_1_TO_2_DIGEST = "ba05775b72fbcd8fc18dcad428b98f6eddd0aeebe7a82c20eb306c57c1630a8f"


@pytest.mark.parametrize("build", ALL_BUILDS, ids=lambda build: f"{build.species}-{build.item}")
def test_every_build_is_legal_for_the_battle(build):
    learnset = json.loads(LEARNSETS.read_text())[str(build.species)]
    assert build.species in species_table()
    assert 1 <= len(build.moves) <= 4 and len(set(build.moves)) == len(build.moves)
    assert set(build.moves) <= set(learnset["moves"])
    assert all(move_id in STATUS_MOVES or damaging(move_id) for move_id in build.moves)
    assert build.ability in learnset["abilities"] and build.ability in abilities.NAMES
    assert battle_data.keys(battle_data.table("items")[build.item])
    assert build.nature in NATURE_MODIFIERS


@pytest.mark.parametrize("build", ALL_BUILDS, ids=lambda build: f"{build.species}-{build.item}")
def test_every_build_has_what_its_roles_need(build):
    effects = {EFFECTS.get(move_id) for move_id in build.moves}
    types = {move_type(move_id) for move_id in build.moves if damaging(move_id)}
    speed = foe_moves.species(build.species).stats["speed"]
    for role in build.roles:
        kind = role.removesuffix("-setter")
        if role == "hitter":
            assert build.item in HITTER_ITEMS, role
        elif role == "lead":
            assert effects & LEAD_EFFECTS, role
        elif role == "sweeper":
            assert effects & SETUP_EFFECTS, role
        elif role == "pivot":
            assert effects & CYCLE_EFFECTS or build.ability in CYCLE_ABILITIES, role
        elif role == "room-setter":
            assert "trick-room" in effects, role
        elif role == "room-hitter":
            assert speed <= ROOM_SPEED, role
        elif role.endswith("-setter"):
            assert build.ability in WEATHER_SETTERS[kind], role
        else:
            boosted_abilities, boosted_types = WEATHER_ABUSE[role]
            sure_hits = RAIN_SURE_HITS if role == "rain" else set()
            assert build.ability in boosted_abilities or types & boosted_types or sure_hits & set(build.moves), role


def test_the_learnset_table_covers_every_build_and_reference_team_species():
    reference = {member["pokemon_id"] for team in tower_balance.PARTIES.values() for member in team}
    assert set(json.loads(LEARNSETS.read_text())) == {str(species) for species in
                                                       {build.species for build in ALL_BUILDS} | reference}


def test_every_family_role_has_builds_and_room_for_two_legendaries():
    for family, slots in tower_teams.FAMILIES.items():
        assert all(tower_teams._candidates(roles, False) for roles in slots), family
        assert sum(bool(tower_teams._candidates(roles, True)) for roles in slots) >= 2, family


def test_an_archetype_team_is_three_unrelated_species_with_different_items_and_the_sets_ivs():
    table = species_table()
    for run in range(RUNS):
        for battle in ARCHETYPE_BATTLES:
            opponent = tower.opponent(run, battle)
            ids = [member.pokemon_id for member in opponent.members]
            assert len(ids) == tower.TEAM_SIZE, (run, battle)
            assert not any(a == b or _related(a, b, table) for i, a in enumerate(ids) for b in ids[i + 1:])
            assert len({member.item for member in opponent.members}) == tower.TEAM_SIZE, (run, battle)
            assert {member.ivs for member in opponent.members} == {tower.tier(battle)[1]}


def test_every_archetype_fights_from_set_3_and_none_before():
    def families(battles):
        return Counter(tower.opponent(run, battle).family for run in range(RUNS) for battle in battles)

    assert set(families(range(1, 20))) == {None}
    for set_number in (3, 4, 5, 7):
        battles = [battle for battle in range((set_number - 1) * 10 + 1, set_number * 10 + 1)
                   if battle not in tower.OWNER_BATTLES]
        assert set(families(battles)) == set(tower_teams.FAMILIES), set_number


def test_an_archetype_member_could_be_swapped_into_a_rental_team_at_its_battle():
    for run in range(RUNS):
        for battle in ARCHETYPE_BATTLES:
            assert all(tower.rentable(member.pokemon_id, battle) for member in tower.opponent(run, battle).members)


def test_a_trainer_member_brings_its_ability_and_nature_and_a_rental_from_it_fights_without_them():
    member = tower.opponent(0, 50).members[0]
    assert member.battle_member()["ability"] == "flash-fire" and member.battle_member()["nature"] == "timid"
    rental = tower.rental_member(member.pokemon_id, 51, member.moves, member.item).battle_member()
    assert "ability" not in rental and "nature" not in rental and rental["moves"] == list(member.moves)
    assert "ability" not in tower.Member.from_json(member.to_json()).battle_member()


def test_the_owner_fields_its_fixed_archetype_teams_at_iv_31():
    for battle, trophy in tower.OWNER_BATTLES.items():
        owner = tower.opponent(9, battle)
        assert owner.family == tower_teams.OWNER_FAMILIES[trophy]
        assert [(m.pokemon_id, m.moves, m.item, m.ability) for m in owner.members] == [
            (build.species, build.moves, build.item, build.ability) for build in tower_teams.OWNER_TEAMS[trophy]]
        assert {member.ivs for member in owner.members} == {tower.OWNER_IVS}
        assert len({member.item for member in owner.members}) == tower.TEAM_SIZE


def test_sets_1_and_2_and_every_offer_stay_as_they_were_before_archetypes():
    rows = [(run, battle, opponent.sprite, tuple((m.pokemon_id, m.moves, m.item, m.ivs) for m in opponent.members))
            for run in range(5) for battle in range(1, 20) for opponent in (tower.opponent(run, battle),)]
    rows += [tuple((m.pokemon_id, m.moves, m.item, m.ivs) for m in tower.offer(run, battle))
             for run in range(5) for battle in (1, 21, 41)]
    assert hashlib.sha256(repr(rows).encode()).hexdigest() == SETS_1_TO_2_DIGEST


def move_type(move_id):
    return battle_data.table("moves")[str(move_id)]["type"]


def damaging(move_id):
    entry = battle_data.table("moves")[str(move_id)]
    return attacks(move_id, entry["power"], entry["class"])
