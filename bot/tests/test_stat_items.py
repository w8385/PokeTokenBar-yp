import random
from dataclasses import replace

import pytest
from status_moves import data_move
from test_battle import TACKLE, mon

from ypoke import battle, items, tera_forms
from ypoke.battle import FormShift, _Fighter, _turn_order
from ypoke.effects import hooks

EARTHQUAKE, QUICK_ATTACK, IRON_HEAD = data_move(89), data_move(98), data_move(442)
SPEED_HALVERS = ("iron-ball", "macho-brace", "power-anklet", "power-band", "power-belt", "power-bracer", "power-lens",
                 "power-weight")


def held(item, types=("normal",), ability=None, moves=(TACKLE,), speed=80, pokemon_id=None):
    combatant = replace(mon("보유", types, moves=moves, speed=speed), item=item, ability=ability, pokemon_id=pokemon_id)
    return _Fighter.enter(combatant)


@pytest.mark.parametrize("item", SPEED_HALVERS)
def test_a_burdening_item_halves_only_its_holders_speed(item):
    holder, plain = held(item), held(None)
    assert holder.stat("speed") == plain.stat("speed") * items.SPEED_HALVED
    assert holder.stat("attack") == plain.stat("attack")


def test_an_iron_ball_grounds_a_flying_or_levitating_holder_against_ground_moves():
    for types, ability in ((("flying",), None), (("normal",), "levitate")):
        holder, plain = held("iron-ball", types, ability), held(None, types, ability)
        assert battle._grounded(holder) and not battle._grounded(plain)
        assert battle._multiplier(EARTHQUAKE, holder) == 1.0 and battle._multiplier(EARTHQUAKE, plain) == 0.0
    assert not hooks.item(held("macho-brace", ("flying",)), "grounds")


@pytest.mark.parametrize("item", ["lagging-tail", "full-incense"])
def test_a_lagging_item_moves_its_faster_holder_last_in_its_bracket_only(item):
    fast = held(item, moves=(TACKLE, QUICK_ATTACK), speed=200)
    slow = held(None, speed=10)
    assert _turn_order((fast, slow), (0, 0), random.Random(0)) == (1, 0)
    assert _turn_order((fast, slow), (1, 0), random.Random(0)) == (0, 1)
    assert _turn_order((held(None, speed=200), slow), (0, 0), random.Random(0)) == (0, 1)


@pytest.mark.parametrize(("item", "species", "stats"), [
    (slug, species, stats) for slug, stats in sorted(items.SPECIES_STATS.items())
    for species in sorted(items.SPECIES_ITEMS[slug])])
def test_a_species_item_doubles_its_stats_on_its_own_species_until_it_transforms(item, species, stats):
    holder, plain = held(item, pokemon_id=species), held(None, pokemon_id=species)
    for stat in ("attack", "defense", "special_attack", "special_defense", "speed"):
        factor = items.SPECIES_STAT_MULTIPLIER if stat in stats else 1.0
        assert holder.stat(stat) == plain.stat(stat) * factor
    holder.volatiles["transform"] = True
    assert all(holder.stat(stat) == plain.stat(stat) for stat in stats)
    assert tera_forms.usable_item(item, species) == item and tera_forms.usable_item(item, 143) is None


@pytest.mark.parametrize("item", ["stick", "lucky-punch"])
def test_a_species_crit_item_adds_two_stages_on_its_own_species_only(item):
    species = min(items.SPECIES_ITEMS[item])
    assert hooks.item(held(item, pokemon_id=species), "crit_stage", default=0) == 2
    assert tera_forms.usable_item(item, species) == item and tera_forms.usable_item(item, 143) is None


@pytest.mark.parametrize(("item", "species", "boosted", "plain"), [
    ("adamant-orb", 483, "steel", "fire"), ("lustrous-orb", 484, "water", "fire"),
    ("griseous-orb", 487, "ghost", "fire"), ("soul-dew", 380, "psychic", "fire"), ("soul-dew", 381, "dragon", "steel"),
])
def test_an_orb_or_the_soul_dew_boosts_its_species_types_and_nothing_else(item, species, boosted, plain):
    assert items.damage_multiplier(item, boosted, 1.0) == items.BOOST_MULTIPLIER
    assert items.damage_multiplier(item, plain, 1.0) == 1.0
    assert tera_forms.usable_item(item, species) == item and tera_forms.usable_item(item, 25) is None


@pytest.mark.parametrize(("item", "boosted"), sorted(items.INCENSES.items()))
def test_an_incense_boosts_its_type_only(item, boosted):
    other = "fire" if boosted != "fire" else "water"
    assert items.damage_multiplier(item, boosted, 1.0) == items.BOOST_MULTIPLIER
    assert items.damage_multiplier(item, other, 1.0) == 1.0


def test_lax_incense_lowers_the_accuracy_of_moves_aimed_at_its_holder():
    assert hooks.item(held("lax-incense"), "accuracy_as_target") == items.BRIGHT_POWDER_ACCURACY
    assert hooks.item(held(None), "accuracy_as_target") is None


@pytest.mark.parametrize(("item", "species", "crowned"), [("rusted-sword", 888, 781), ("rusted-shield", 889, 782)])
def test_a_rusted_item_turns_iron_head_into_its_behemoth_move_until_the_holder_leaves(item, species, crowned):
    holder = held(item, moves=(TACKLE, IRON_HEAD), pokemon_id=species)
    shift = hooks.item(holder, "on_entry_form", holder, 0, 1)
    assert isinstance(shift, FormShift)
    assert [move.id for move in holder.combatant.moves] == [TACKLE.id, crowned]
    assert holder.combatant.moves[1].power == 100 and holder.pp[1] == holder.combatant.moves[1].pp
    holder.leave()
    assert [move.id for move in holder.combatant.moves] == [TACKLE.id, IRON_HEAD.id]
    plain = held(item, moves=(TACKLE,), pokemon_id=species)
    hooks.item(plain, "on_entry_form", plain, 0, 1)
    assert plain.combatant.moves == (TACKLE,) and plain.entered_as is None
