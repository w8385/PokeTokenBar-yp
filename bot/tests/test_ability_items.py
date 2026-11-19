import random
from dataclasses import replace

import pytest
from attacks import attack
from status_moves import resolve
from test_battle import TACKLE, mon
from test_held_items_more import FixedRng

from ypoke import battle
from ypoke.battle import AbilityAct, ItemHeal, _Arena, _Team
from ypoke.effects import hooks

SITRUS, LUM, CHILAN, LEFTOVERS = "sitrus-berry", "lum-berry", "chilan-berry", "leftovers"
KNOCK_OFF, THIEF, TRICK, BUG_BITE, CORROSIVE_GAS, INCINERATE = (
    attack(282), attack(168), attack(271), attack(450), attack(810), attack(510))


def holding(ability=None, item=None, foe_ability=None, foe_item=None):
    arena = _Arena(turn=1)
    user = replace(mon("사용자", ("normal",)), ability=ability, item=item)
    foe = replace(mon("상대", ("normal",)), ability=foe_ability, item=foe_item)
    arena.teams = (_Team((user,), arena=arena), _Team((foe,), arena=arena, side=1))
    arena.weather.teams = arena.teams
    return arena.teams[0].active, arena.teams[1].active, arena


def ate_sitrus(ability, hp_share=2):
    holder, _, arena = holding(ability, SITRUS)
    holder.hp = holder.max_hp // hp_share
    event = hooks.item(holder, "on_update", holder, 0, 1)
    return holder, arena, event


@pytest.mark.parametrize(("ability", "heals"), [
    ("cheek-pouch", lambda max_hp: max_hp // 4 + max_hp // 3), ("ripen", lambda max_hp: max_hp // 4 * 2),
    (None, lambda max_hp: max_hp // 4),
])
def test_cheek_pouch_and_ripen_add_to_the_sitrus_heal(ability, heals):
    holder, arena, event = ate_sitrus(ability, hp_share=4)
    assert isinstance(event, ItemHeal) and holder.item is None and holder.ate_berry
    assert holder.hp == holder.max_hp // 4 + heals(holder.max_hp)
    assert [type(logged) for logged in arena.log] == ([AbilityAct] if ability == "cheek-pouch" else [])


def test_cheek_pouch_does_nothing_at_full_hp():
    holder, _, arena = holding("cheek-pouch", LUM)
    holder.status = "burn"
    hooks.item(holder, "on_update", holder, 0, 1)
    assert holder.status is None and holder.hp == holder.max_hp and arena.log == []


@pytest.mark.parametrize("ability", ["ripen", None])
def test_ripen_quarters_the_hit_a_resist_berry_meets(ability):
    def taken(berry):
        holder, foe, arena = holding(ability, berry)
        resolve(foe, holder, TACKLE, arena)
        return holder.max_hp - holder.hp

    assert taken(CHILAN) == pytest.approx(taken(None) * (0.25 if ability else 0.5), abs=1)


def test_cud_chew_eats_its_berry_again_at_the_end_of_the_next_turn_only():
    holder, _, _ = ate_sitrus("cud-chew", hp_share=4)
    after_first = holder.hp
    assert hooks.ability(holder, "end_of_turn", holder, 0, 1, random.Random(0)) is None
    act, heal = hooks.ability(holder, "end_of_turn", holder, 0, 2, random.Random(0))
    assert act == AbilityAct(2, 0, "사용자", "cud-chew", effect="chew", detail=SITRUS)
    assert isinstance(heal, ItemHeal) and holder.hp == after_first + holder.max_hp // 4
    assert hooks.ability(holder, "end_of_turn", holder, 0, 3, random.Random(0)) is None
    assert holder.item is None


def test_cud_chew_skips_a_berry_eaten_from_the_foes_hand():
    holder, foe, arena = holding("cud-chew", foe_item=SITRUS)
    holder.hp = holder.max_hp // 4
    resolve(holder, foe, BUG_BITE, arena)
    assert foe.item is None and holder.ate_berry
    assert hooks.ability(holder, "end_of_turn", holder, 0, 2, random.Random(0)) is None


@pytest.mark.parametrize(("weather", "draw", "lost", "grows"), [
    (None, 0.4, False, True), (None, 0.6, False, False), ("sun", 0.9, False, True), ("sun", 0.1, True, False),
])
def test_harvest_grows_an_eaten_berry_back(weather, draw, lost, grows):
    holder, arena, _ = ate_sitrus("harvest")
    arena.weather.kind, holder.item_lost = weather, lost
    act = hooks.ability(holder, "end_of_turn", holder, 0, 1, FixedRng(draw))
    assert (holder.item == SITRUS) == grows
    assert act == (AbilityAct(1, 0, "사용자", "harvest", effect="harvest", detail=SITRUS) if grows else None)


def test_harvest_needs_an_eaten_berry():
    holder, _, _ = holding("harvest", LEFTOVERS)
    holder.item = None
    assert hooks.ability(holder, "end_of_turn", holder, 0, 1, FixedRng(0.0)) is None


@pytest.mark.parametrize(("ability", "healed"), [("klutz", False), (None, True)])
def test_klutz_idles_the_holders_item(ability, healed):
    holder, foe, _ = holding(ability, LEFTOVERS)
    holder.hp = holder.max_hp // 2
    events = []
    battle._item_upkeep(1, (holder, foe), events, random.Random(0))
    assert (holder.hp > holder.max_hp // 2) == healed


@pytest.mark.parametrize(("move", "foe_item"), [
    (KNOCK_OFF, LEFTOVERS), (THIEF, LEFTOVERS), (TRICK, LEFTOVERS), (BUG_BITE, SITRUS), (CORROSIVE_GAS, LEFTOVERS),
    (INCINERATE, SITRUS),
])
@pytest.mark.parametrize(("foe_ability", "user_ability", "kept"), [
    ("sticky-hold", None, True), (None, None, False), ("sticky-hold", "mold-breaker", False),
])
def test_sticky_hold_keeps_the_item_from_every_foe(move, foe_item, foe_ability, user_ability, kept):
    user, foe, arena = holding(user_ability, None if move is not TRICK else "choice-scarf", foe_ability, foe_item)
    resolve(user, foe, move, arena)
    assert (foe.item == foe_item) == kept


def test_knock_off_keeps_its_boost_against_sticky_hold():
    def dealt(foe_ability):
        user, foe, arena = holding(None, None, foe_ability, LEFTOVERS)
        resolve(user, foe, KNOCK_OFF, arena)
        return foe.max_hp - foe.hp

    assert dealt("sticky-hold") == dealt(None)


def test_a_trick_user_with_sticky_hold_still_gives_its_item():
    user, foe, arena = holding("sticky-hold", "choice-scarf", None, LEFTOVERS)
    resolve(user, foe, TRICK, arena)
    assert (user.item, foe.item) == (LEFTOVERS, "choice-scarf")
