import random
from dataclasses import replace

import pytest
from test_ability_items import holding
from test_battle import EMBER, FLAMETHROWER, TACKLE
from status_moves import resolve

from ypoke import battle, items
from ypoke.battle import ItemEffect, ItemHeal, _quick_claws
from ypoke.effects import hooks, item_moves
from ypoke.narration import battle_log

WATER_GUN = battle.Move("물대포", "water", 40, physical=False, accuracy=100)


def at_share(berry, share, ability=None, foe_ability=None, nature=None):
    holder, foe, arena = holding(ability, berry, foe_ability)
    if nature:
        holder.combatant = replace(holder.combatant, nature=nature)
    holder.hp = holder.max_hp // share
    return holder, foe, arena


def update(holder):
    return hooks.item(holder, "on_update", holder, 0, 1)


@pytest.mark.parametrize(("berry", "stat"), sorted(items.STAT_BERRIES.items()))
def test_a_stat_berry_raises_its_stat_at_a_quarter_hp_only(berry, stat):
    holder, _, _ = at_share(berry, 4)
    event = update(holder)
    assert holder.stages[stat] == 1 and holder.item is None and holder.ate_berry
    assert event.changes == (battle.Change(0, holder.combatant.name, stat, 1),)
    above, _, _ = at_share(berry, 3)
    assert update(above) is None and above.item == berry and above.stages[stat] == 0


@pytest.mark.parametrize(("ability", "share", "eaten"), [("gluttony", 2, True), (None, 2, False), ("gluttony", 1, False)])
def test_gluttony_eats_a_pinch_berry_at_half_hp(ability, share, eaten):
    holder, _, _ = at_share("liechi-berry", share, ability)
    update(holder)
    assert (holder.item is None) == eaten


def test_ripen_doubles_a_stat_berry():
    holder, _, _ = at_share("salac-berry", 4, "ripen")
    update(holder)
    assert holder.stages["speed"] == 2


def test_unnerve_keeps_a_pinch_berry_in_hand_and_the_chooser_does_not_count_on_it():
    holder, _, _ = at_share("figy-berry", 4, foe_ability="unnerve")
    assert update(holder) is None and holder.item == "figy-berry"
    assert not item_moves.craves(holder)
    free, _, _ = at_share("figy-berry", 4)
    assert item_moves.craves(free)


def test_starf_sharply_raises_a_stat_that_can_still_rise():
    holder, _, _ = at_share("starf-berry", 4)
    for key in battle.BATTLE_STATS[1:]:
        holder.stages[key] = battle.MAX_STAGE
    event = update(holder)
    assert holder.stages["attack"] == items.STARF_STAGES and event.changes[0].kind == "attack"
    maxed, _, _ = at_share("starf-berry", 4)
    maxed.stages.update(dict.fromkeys(battle.BATTLE_STATS, battle.MAX_STAGE))
    assert update(maxed).changes == () and maxed.item is None


def test_lansat_raises_the_critical_hit_stage_and_micle_the_next_moves_accuracy():
    lansat, foe, _ = at_share("lansat-berry", 4)
    update(lansat)
    assert sum(battle._field(lansat, "crit_stage")) == 2
    micle, foe, arena = at_share("micle-berry", 4)
    plain = battle._accuracy(micle, foe, TACKLE)
    update(micle)
    assert battle._accuracy(micle, foe, TACKLE) == pytest.approx(plain * items.MICLE_ACCURACY)
    resolve(micle, foe, TACKLE, arena)
    assert battle._accuracy(micle, foe, TACKLE) == pytest.approx(plain)


@pytest.mark.parametrize(("share", "first"), [(4, True), (3, False)])
def test_custap_moves_its_holder_first_in_a_pinch(share, first):
    holder, foe, _ = at_share("custap-berry", share)
    holder.stats["speed"], events = 1, []
    claws = _quick_claws(1, (holder, foe), (0, 0), None, random.Random(0), events)
    assert claws[0] == first and (holder.item is None) == first
    assert [(event.item, event.effect) for event in events] == ([("custap-berry", "first")] if first else [])


@pytest.mark.parametrize(("nature", "confused"), [("modest", True), ("adamant", False), (None, False)])
def test_a_flavor_berry_heals_a_third_and_confuses_a_nature_that_dislikes_it(nature, confused):
    holder, _, _ = at_share("figy-berry", 4, nature=nature)
    before = holder.hp
    update(holder)
    assert holder.hp == before + holder.max_hp // items.FLAVOR_HEAL_FRACTION
    assert (holder.confusion_left > 0) == confused


@pytest.mark.parametrize(("ability", "share", "healed"), [(None, 2, 10), ("ripen", 2, 20), (None, 1, 0)])
def test_oran_heals_ten_hp_at_half_hp(ability, share, healed):
    holder, _, _ = at_share("oran-berry", share, ability)
    before = holder.hp
    update(holder)
    assert holder.hp - before == healed


def test_leppa_gives_pp_back_to_a_move_that_ran_out():
    holder, _, _ = at_share("leppa-berry", 1)
    assert update(holder) is None
    holder.pp[0] = 0
    event = update(holder)
    assert holder.pp[0] == min(TACKLE.pp, items.LEPPA_PP) and event.effect == "pp" and holder.item is None


@pytest.mark.parametrize(("berry", "cures"), sorted(items.CURE_BERRIES.items()))
def test_a_cure_berry_cures_its_own_status_only(berry, cures):
    holder, _, _ = at_share(berry, 1)
    other = "burn" if "burn" not in cures else "paralysis"
    holder.status = other
    assert update(holder) is None and holder.item == berry
    holder.status = None
    if cures == ("confusion",):
        holder.confusion_left = 3
    else:
        holder.status = cures[0]
    assert update(holder).effect == "cure"
    assert holder.status is None and holder.confusion_left == 0 and holder.item is None


@pytest.mark.parametrize(("move", "healed"), [(WATER_GUN, True), (TACKLE, False)])
def test_enigma_heals_a_quarter_after_a_super_effective_hit_only(move, healed):
    holder, foe, arena = holding(None, "enigma-berry")
    holder.combatant = replace(holder.combatant, types=("fire",))
    action = resolve(foe, holder, move, arena)
    assert (action.defender_item == "enigma-berry") == healed and (holder.item is None) == healed


@pytest.mark.parametrize(("berry", "move", "hurt"), [
    ("jaboca-berry", TACKLE, True), ("jaboca-berry", EMBER, False),
    ("rowap-berry", EMBER, True), ("rowap-berry", TACKLE, False),
])
def test_a_recoil_berry_hurts_an_attacker_of_its_move_class(berry, move, hurt):
    holder, foe, arena = holding(None, berry)
    resolve(foe, holder, move, arena)
    lost = foe.max_hp // items.RECOIL_BERRY_FRACTION if hurt else 0
    assert foe.hp == foe.max_hp - lost and (holder.item is None) == hurt


def test_a_recoil_berry_acts_even_as_its_holder_faints():
    holder, foe, arena = holding(None, "jaboca-berry")
    holder.hp = 1
    action = resolve(foe, holder, TACKLE, arena)
    assert action.knockout and action.defender_item == "jaboca-berry" and foe.hp < foe.max_hp


@pytest.mark.parametrize(("berry", "move", "stat"), [
    ("kee-berry", TACKLE, "defense"), ("kee-berry", FLAMETHROWER, None),
    ("maranga-berry", FLAMETHROWER, "special_defense"), ("maranga-berry", TACKLE, None),
])
def test_a_guard_berry_raises_the_defense_a_hit_of_its_class_meets(berry, move, stat):
    holder, foe, arena = holding(None, berry)
    resolve(foe, holder, move, arena)
    raised = {key for key, stage in holder.stages.items() if stage > 0}
    assert raised == ({stat} if stat else set())


def test_harvest_grows_back_a_pinch_berry_and_cheek_pouch_adds_its_heal():
    holder, _, _ = at_share("liechi-berry", 4, "harvest")
    update(holder)
    hooks.ability(holder, "end_of_turn", holder, 0, 1, random.Random(0))
    assert holder.item is None or holder.item == "liechi-berry"
    pouch, _, arena = at_share("liechi-berry", 4, "cheek-pouch")
    before = pouch.hp
    update(pouch)
    assert pouch.hp > before and arena.log


def test_the_battle_log_shows_a_berry_and_the_stat_it_raised():
    event = ItemEffect(1, 0, "피카츄", "liechi-berry", "eaten", (battle.Change(0, "피카츄", "attack", 1),))
    heal = ItemHeal(1, 0, "피카츄", "oran-berry", 40)
    log = "".join(battle_log(battle.BattleResult(0, 1, (event, heal), ((50,), (0,)))))
    assert "피카츄 @치리열매 먹음 공격↑" in log and "피카츄 @오랭열매 40%" in log
