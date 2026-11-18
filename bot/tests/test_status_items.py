from dataclasses import replace

from status_moves import choose, data_move, pair, put, resolve
from test_battle import TACKLE, mon

from ypoke import items, tera_forms
from ypoke.battle import ItemEffect, ItemHeal, _Arena, simulate

TRICK, SWITCHEROO, BESTOW, RECYCLE = data_move(271), data_move(415), data_move(516), data_move(278)
CORROSIVE_GAS, TEATIME, STUFF_CHEEKS = data_move(810), data_move(752), data_move(747)
FLAME_ORB, LEFTOVERS, SCARF = "flame-orb", items.LEFTOVERS, "choice-scarf"


def fighters(user_item=None, foe_item=None, user_types=("normal",), foe_types=("normal",)):
    arena = _Arena()
    user = put(mon("사용자", user_types), arena, item=user_item)
    foe = put(mon("상대", foe_types), arena, 1, item=foe_item)
    return user, foe, arena


def test_trick_swaps_the_items_of_the_battle_copies_and_the_saved_party_keeps_its_own():
    user = replace(mon("사용자", ("normal",), moves=(TRICK, TACKLE)), item=FLAME_ORB)
    foe = replace(mon("상대", ("normal",)), item=LEFTOVERS)
    sides = ((user,), (foe,))
    result = simulate(sides, seed=3)
    got = [(event.side, event.item) for event in result.events if isinstance(event, ItemEffect) and event.effect == "got"]
    assert got[:2] == [(0, LEFTOVERS), (1, FLAME_ORB)]
    assert any(isinstance(event, ItemEffect) and event.side == 1 and event.effect == "burn" for event in result.events)
    assert sides == ((user,), (foe,)) and user.item == FLAME_ORB and foe.item == LEFTOVERS
    assert simulate(sides, seed=3) == result


def test_trick_and_switcheroo_fail_without_an_item_or_on_one_the_battle_cannot_move():
    user, foe, arena = fighters()
    assert resolve(user, foe, TRICK, arena).failed
    user, foe, arena = fighters(LEFTOVERS, next(iter(tera_forms.MASKS)))
    assert resolve(user, foe, SWITCHEROO, arena).failed and user.item == LEFTOVERS
    user, foe, arena = fighters(LEFTOVERS)
    foe.combatant = replace(foe.combatant, item="iron-ball")
    assert resolve(user, foe, TRICK, arena).failed


def test_a_swapped_item_stays_through_a_switch_and_ends_the_givers_choice_lock():
    user, foe, arena = fighters(SCARF, LEFTOVERS)
    user.locked = 1
    user.entered_as = user.combatant
    assert resolve(user, foe, TRICK, arena).effect == "trick"
    assert (user.item, foe.item, user.locked) == (LEFTOVERS, SCARF, None)
    user.leave()
    foe.leave()
    assert (user.item, user.combatant.item, foe.combatant.item) == (LEFTOVERS, LEFTOVERS, SCARF)


def test_substitute_stops_trick_but_not_bestow_which_needs_an_empty_handed_foe():
    user, foe, arena = fighters(FLAME_ORB, LEFTOVERS)
    foe.volatiles["substitute"] = foe.max_hp // 4
    assert resolve(user, foe, TRICK, arena).failed
    assert resolve(user, foe, BESTOW, arena).failed
    foe.item = None
    assert resolve(user, foe, BESTOW, arena).effect == "bestow"
    assert (user.item, foe.item) == (None, FLAME_ORB)


def test_recycle_brings_back_an_eaten_berry_but_not_an_item_given_or_melted_away():
    user, foe, arena = fighters()
    user.combatant = replace(user.combatant, item=items.SITRUS_BERRY)
    user.item, user.hp = items.SITRUS_BERRY, 1
    assert resolve(user, foe, TEATIME, arena).effect == "teatime" and user.item is None
    assert resolve(user, foe, RECYCLE, arena).effect == "recycle" and user.item == items.SITRUS_BERRY
    assert resolve(user, foe, RECYCLE, arena).failed
    resolve(user, foe, BESTOW, arena)
    assert resolve(user, foe, RECYCLE, arena).failed
    assert resolve(user, foe, CORROSIVE_GAS, arena).effect == "corrosive-gas" and foe.item is None
    assert resolve(foe, user, RECYCLE, arena).failed


def test_a_berry_received_after_a_knock_off_can_be_recycled_once_eaten():
    user, foe, arena = fighters(foe_item=items.SITRUS_BERRY)
    user.combatant = replace(user.combatant, item=LEFTOVERS)
    user.item_lost = True
    resolve(user, foe, TRICK, arena)
    resolve(user, foe, TEATIME, arena)
    assert resolve(user, foe, RECYCLE, arena).effect == "recycle" and user.item == items.SITRUS_BERRY


def test_corrosive_gas_cannot_melt_an_item_bound_to_a_form():
    user, foe, arena = fighters(foe_item=next(iter(tera_forms.MASKS)))
    assert resolve(user, foe, CORROSIVE_GAS, arena).failed and foe.item is not None


def test_teatime_feeds_every_berry_whatever_it_waits_for_and_an_embargo_keeps_one_uneaten():
    user, foe, arena = fighters(items.LUM_BERRY, items.SITRUS_BERRY)
    resolve(user, foe, TEATIME, arena)
    assert [type(event) for event in arena.log] == [ItemEffect, ItemHeal]
    assert arena.log[0].effect == "eaten" and user.item is None and foe.item is None
    user, foe, arena = fighters(items.LUM_BERRY, items.SITRUS_BERRY)
    foe.volatiles["embargo"] = 5
    resolve(user, foe, TEATIME, arena)
    assert foe.item == items.SITRUS_BERRY and user.item is None
    user, foe, arena = fighters(LEFTOVERS)
    assert resolve(user, foe, TEATIME, arena).failed


def test_stuff_cheeks_eats_the_berry_then_raises_defense_and_fails_without_one():
    user, foe, arena = fighters("occa-berry")
    action = resolve(user, foe, STUFF_CHEEKS, arena)
    assert action.effect == "stuff-cheeks" and user.stages["defense"] == 2 and user.item is None
    assert resolve(user, foe, STUFF_CHEEKS, arena).failed and user.stages["defense"] == 2


def test_the_chooser_tricks_a_burden_onto_the_foe_once_and_never_takes_one():
    teams, arena = pair((TRICK, TACKLE))
    user, foe = teams[0].active, teams[1].active
    user.item, foe.item = FLAME_ORB, LEFTOVERS
    assert choose(teams, arena) == 0
    resolve(user, foe, TRICK, arena)
    assert choose(teams, arena) == 1
    user.item, foe.item = None, FLAME_ORB
    assert choose(teams, arena) == 1
    user.item, foe.item = LEFTOVERS, None
    assert choose(teams, arena) == 1


def test_the_chooser_feeds_berries_and_melts_items_only_when_it_helps():
    teams, arena = pair((TEATIME, CORROSIVE_GAS, TACKLE))
    user, foe = teams[0].active, teams[1].active
    user.item, user.hp = items.SITRUS_BERRY, user.max_hp // 2
    assert choose(teams, arena) == 0
    foe.item, foe.hp = items.SITRUS_BERRY, foe.max_hp // 2
    assert choose(teams, arena) == 1
    foe.item = FLAME_ORB
    user.hp = user.max_hp
    assert choose(teams, arena) == 2


def test_the_chooser_recycles_a_berry_only_when_eating_it_would_help():
    teams, arena = pair((RECYCLE, TACKLE))
    user = teams[0].active
    user.combatant = replace(user.combatant, item=items.SITRUS_BERRY)
    user.item = None
    assert choose(teams, arena) == 1
    user.hp = user.max_hp // 2
    assert choose(teams, arena) == 0
