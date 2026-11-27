from pathlib import Path

import pytest

from ypoke import tower
from ypoke.gyms import QUASI_LEGENDARY, _related, species_table

TRAINER_ART = Path(__file__).resolve().parents[2] / "assets/trainers"


def legendary(pokemon_id):
    species = species_table()[pokemon_id]
    return species.excluded or pokemon_id in QUASI_LEGENDARY


def normal_battles(sets):
    return [battle for battle in range(1, sets * tower.SET_SIZE + 1) if battle not in tower.OWNER_BATTLES]


def test_an_opponent_is_the_same_for_the_same_run_and_battle_and_differs_across_runs():
    assert tower.opponent(7, 3) == tower.opponent(7, 3)
    assert {tower.opponent(run, 3).members for run in range(20)} != {tower.opponent(7, 3).members}


@pytest.mark.parametrize("battle", normal_battles(7))
def test_every_trainer_fields_three_unrelated_species_at_the_tiers_ivs(battle):
    team = tower.opponent(11, battle).members
    ids = [member.pokemon_id for member in team]
    assert len(ids) == tower.TEAM_SIZE
    assert not any(_related(a, b, species_table()) or a == b for i, a in enumerate(ids) for b in ids[i + 1:])
    assert {member.ivs for member in team} == {tower.tier(battle)[1]}
    assert all(member.moves and member.item for member in team)


def test_no_legendary_before_set_five_and_at_least_one_in_every_battle_from_it():
    for run in range(5):
        for battle in normal_battles(8):
            legends = [m for m in tower.opponent(run, battle).members if legendary(m.pokemon_id)]
            if tower.set_of(battle) < tower.LEGEND_SET:
                assert legends == [], (run, battle)
            else:
                assert 1 <= len(legends) <= 2, (run, battle)


def test_opponents_get_stronger_each_set():
    def mean_total(set_number):
        battles = [b for b in range((set_number - 1) * 10 + 1, set_number * 10 + 1) if b not in tower.OWNER_BATTLES]
        totals = [species_table()[m.pokemon_id].total for run in range(10) for b in battles
                  for m in tower.opponent(run, b).members]
        return sum(totals) / len(totals)

    means = [mean_total(set_number) for set_number in range(1, 8)]
    assert means == sorted(means)
    assert [tower.tier(battle)[1] for battle in (1, 11, 21, 31, 41, 51, 61, 200)] == [12, 16, 20, 24, 28, 31, 31, 31]


def test_the_owner_stands_at_battles_20_and_50_only_with_silver_then_gold():
    owners = {battle: tower.opponent(3, battle) for battle in range(1, 121) if tower.opponent(3, battle).trophy}
    assert {battle: owner.trophy for battle, owner in owners.items()} == {20: "silver", 50: "gold"}
    assert {owner.sprite for owner in owners.values()} == {tower.OWNER_ID}
    assert not any(legendary(m.pokemon_id) for m in owners[20].members)
    assert sum(legendary(m.pokemon_id) for m in owners[50].members) == 2
    assert {m.ivs for owner in owners.values() for m in owner.members} == {31}


def test_an_offer_is_six_unrelated_rentals_of_the_battles_tier_that_a_team_may_bring():
    for battle in (1, 41):
        offer = tower.offer(5, battle)
        ids = [member.pokemon_id for member in offer]
        assert len(set(ids)) == tower.OFFER_SIZE
        assert not any(_related(a, b, species_table()) for i, a in enumerate(ids) for b in ids[i + 1:])
        assert {member.ivs for member in offer} == {tower.tier(battle)[1]}
        assert all(tower.rentable(pokemon_id, battle) for pokemon_id in ids)
    assert any(legendary(member.pokemon_id) for member in tower.offer(5, 41))


def test_a_legendary_rental_is_not_rentable_before_set_five():
    assert not tower.rentable(150, 40)
    assert tower.rentable(150, 41)


def test_a_rental_keeps_its_moves_and_item_and_takes_the_ivs_of_the_battle_it_fights():
    member = tower.rental_member(149, 41, (200, 89), "life-orb")
    assert member.battle_member() == {
        "pokemon_id": 149, "level": 50, "learned_at": 100, "shiny": False, "ivs": dict.fromkeys(
            ("hp", "attack", "defense", "special_attack", "special_defense", "speed"), 28),
        "moves": [200, 89], "held_item": "life-orb",
    }


def test_bp_climbs_by_set_and_the_owner_pays_more():
    assert [tower.bp_for(battle) for battle in (1, 10, 11, 21, 31, 41, 51, 61, 300)] == [1, 1, 2, 3, 3, 4, 4, 5, 5]
    assert (tower.bp_for(20), tower.bp_for(50)) == (10, 20)


def test_every_tower_trainer_has_art():
    sprites = {f"tower-{index}" for index in range(1, len(tower.TRAINERS) + 1)} | {tower.OWNER_ID}
    assert {sprite for sprite in sprites if not (TRAINER_ART / f"{sprite}.png").exists()} == set()
