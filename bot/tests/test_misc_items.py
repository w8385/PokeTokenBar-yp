import random
from dataclasses import replace

import pytest
from attacks import attack, draws, duel
from status_moves import data_move
from test_attack_two_turn import act, armed
from test_battle import mon

from ypoke import battle, items, move_power, narration
from ypoke.battle import FormShift, Hit, ItemEffect, ItemHeal, VolatileEnd, VolatileTick, _Fighter
from ypoke.effects import hooks

BULLET_SEED, DOUBLE_KICK, TRIPLE_AXEL, POPULATION_BOMB = attack(331), attack(24), attack(813), attack(860)
BITE, SWIFT, WRAP, EARTHQUAKE, SHADOW_BALL = attack(44), attack(129), attack(35), attack(89), attack(247)
GROWL, TACKLE = data_move(45), attack(33)
LANDS, NO_CRIT, MISSES = 0.0, 0.99, 0.99


def held(item, types=("normal",), ability=None, pokemon_id=None):
    combatant = replace(mon("보유", types), item=item, ability=ability, pokemon_id=pokemon_id)
    return _Fighter.enter(combatant)


def test_a_zoom_lens_sharpens_its_holders_aim_only_at_a_target_that_already_moved():
    user, foe, _ = duel()
    plain = battle._accuracy(user, foe, BITE)
    user.item = "zoom-lens"
    assert battle._accuracy(user, foe, BITE) == plain
    foe.acted = True
    assert battle._accuracy(user, foe, BITE) == pytest.approx(plain * items.ZOOM_LENS_ACCURACY)


def test_a_metronome_adds_a_fifth_per_use_in_a_row_that_worked_up_to_double():
    user, foe, arena = duel()
    user.item = "metronome"
    armed(user, TACKLE, GROWL)
    boosts = []
    for turn in range(1, 8):
        foe.hp = foe.max_hp
        boosts.append(battle._item_boost(user, TACKLE, 1.0))
        act(user, foe, arena, turn=turn)
    assert boosts == pytest.approx([1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.0])
    act(user, foe, arena, index=1, turn=8)
    assert battle._item_boost(user, TACKLE, 1.0) == 1.0


def test_a_metronome_streak_restarts_after_a_use_that_failed_and_a_plain_holder_gets_nothing():
    user, foe, arena = duel()
    user.item = "metronome"
    hooks.item(user, "after_use", user, TACKLE, True)
    hooks.item(user, "after_use", user, TACKLE, False)
    assert battle._item_boost(user, TACKLE, 1.0) == 1.0
    plain, _, _ = duel()
    plain.memory["metronome"] = (TACKLE.id, True, 3)
    assert battle._item_boost(plain, TACKLE, 1.0) == 1.0


def test_loaded_dice_makes_a_two_to_five_hit_move_hit_four_or_five_times():
    user, _, _ = duel()
    user.item = "loaded-dice"
    counts = {battle._hit_count(BULLET_SEED, user, random.Random(seed)) for seed in range(60)}
    assert counts == {4, 5}
    assert battle._hit_count(DOUBLE_KICK, user, random.Random(0)) == 2
    assert battle._expected_hits(BULLET_SEED, user, 100) == 4.5
    plain, _, _ = duel()
    assert {battle._hit_count(BULLET_SEED, plain, random.Random(seed)) for seed in range(60)} >= {2, 3}


def test_loaded_dice_draws_accuracy_once_for_population_bomb_and_triple_axel():
    user, foe, arena = duel(user_types=("fire",))
    user.item = "loaded-dice"
    counts = {battle._hit_count(POPULATION_BOMB, user, random.Random(seed)) for seed in range(200)}
    assert counts == set(range(4, 11))
    assert _strike(user, foe, TRIPLE_AXEL, arena, draws(LANDS, NO_CRIT, MISSES, NO_CRIT, MISSES)).hits == 3
    assert battle._expected_hits(TRIPLE_AXEL, user, 90) == 3
    assert battle._expected_hits(POPULATION_BOMB, user, 90) == 7
    plain, foe, arena = duel(user_types=("fire",))
    assert _strike(plain, foe, TRIPLE_AXEL, arena, draws(LANDS, NO_CRIT, MISSES)).hits == 1


@pytest.mark.parametrize("item", ["kings-rock", "razor-fang"])
def test_a_flinch_item_may_flinch_a_target_that_has_not_moved_with_a_move_that_cannot_on_its_own(item):
    def flinches(move, user_item=item, foe_item=None, acted=False):
        user, foe, _ = duel()
        user.item, foe.item, foe.acted = user_item, foe_item, acted
        hit = battle.HitResult(damage=10)
        hooks.item(user, "adds_secondary",
                   Hit(0, 1, user, foe, move, battle.MoveResult(move, hits=[hit]), hit, 1.0, draws(0.05)))
        return "flinch" in foe.volatiles

    assert flinches(TACKLE)
    assert not flinches(TACKLE, user_item=None)
    assert not flinches(TACKLE, acted=True)
    assert not flinches(BITE)
    assert not flinches(TACKLE, foe_item="covert-cloak")


def test_a_grip_claw_holds_a_bind_for_seven_turns_and_a_binding_band_takes_a_sixth():
    for item, turns, share in (("grip-claw", 7, 8), ("binding-band", None, 6), (None, None, 8)):
        user, foe, arena = duel()
        user.item = item
        armed(user, WRAP)
        act(user, foe, arena, seed=next(seed for seed in range(200) if random.Random(seed).random() * 100 < 90))
        foe.hp = foe.max_hp
        events = []
        for turn in range(1, 10):
            battle._volatile_upkeep(turn, (user, foe), events, random.Random(0))
        ticks = [event for event in events if isinstance(event, VolatileTick)]
        assert len(ticks) == turns if turns else len(ticks) in (4, 5)
        assert foe.max_hp - foe.hp == len(ticks) * (foe.max_hp // share)
        assert isinstance(events[-1], VolatileEnd)


def test_a_sticky_barb_hurts_its_holder_an_eighth_each_turn():
    holder = held("sticky-barb")
    event = hooks.item(holder, "end_of_turn", holder, 0, 3, random.Random(0))
    assert holder.max_hp - holder.hp == holder.max_hp // items.STICKY_BARB_FRACTION
    assert event == ItemHeal(3, 0, holder.combatant.name, "sticky-barb", holder.hp_percent)
    assert narration._event_lines(event) == [f"🔵 보유 @{items.ITEM_NAMES['sticky-barb']} {event.hp}%"]
    guarded = held("sticky-barb", ability="magic-guard")
    assert hooks.item(guarded, "end_of_turn", guarded, 0, 3, random.Random(0)) is None
    assert guarded.hp == guarded.max_hp


def test_a_sticky_barb_clings_to_an_empty_handed_attacker_that_makes_contact():
    def struck(move, attacker_item=None):
        user, foe, arena = duel()
        user.item, foe.item = attacker_item, "sticky-barb"
        armed(user, move)
        act(user, foe, arena, seed=1)
        return user, foe, arena

    user, foe, arena = struck(TACKLE)
    assert (user.item, foe.item, foe.item_lost) == ("sticky-barb", None, True)
    assert ItemEffect(arena.turn, 0, user.combatant.name, "sticky-barb", "got") in arena.log
    for move, attacker_item in ((SWIFT, None), (TACKLE, "leftovers")):
        user, foe, _ = struck(move, attacker_item)
        assert (user.item, foe.item) == (attacker_item, "sticky-barb")
    assert hooks.call("items", "sticky-barb", "burdens", held(None))


def test_a_float_stone_halves_its_holders_weight():
    holder, plain = held("float-stone"), held(None)
    for fighter in (holder, plain):
        fighter.combatant = replace(fighter.combatant, weight=1300)
    assert battle._weight(holder) == 650 and battle._weight(plain) == 1300


def test_a_ring_target_drops_its_holders_type_immunities_but_not_its_abilitys():
    ghost, flyer, levitating = held("ring-target", ("ghost",)), held("ring-target", ("flying",)), held(
        "ring-target", ability="levitate")
    assert battle._multiplier(TACKLE, ghost) == 1.0 and battle._multiplier(TACKLE, held(None, ("ghost",))) == 0.0
    assert battle._multiplier(EARTHQUAKE, flyer) == 1.0
    assert battle._multiplier(SHADOW_BALL, ghost) == 2.0
    assert battle._multiplier(EARTHQUAKE, levitating) == 0.0


@pytest.mark.parametrize(("item", "species"), sorted(items.FORM_BOUND.items()))
def test_a_drive_or_memory_shows_its_form_on_its_own_species_and_stays_bound_to_it(item, species):
    holder, other = held(item, pokemon_id=species), held(item, pokemon_id=143)
    assert hooks.item(holder, "on_entry_form", holder, 0, 1) == FormShift(1, 0, "보유", item)
    assert hooks.item(other, "on_entry_form", other, 0, 1) is None
    assert not move_power.holds_removable_item(holder) and move_power.holds_removable_item(other)
    caption = narration.FORM_CAPTION[item]
    assert caption == f"{items.ITEM_NAMES[item]} 모습" and caption in narration._form_line(FormShift(1, 0, "보유", item))


def test_the_destiny_knot_is_inert_for_want_of_gender():
    assert items.known("destiny-knot") is None


def test_a_throat_spray_waits_for_a_sound_move_that_worked():
    holder = held("throat-spray")
    hyper_voice = attack(304)
    assert hooks.item(holder, "after_use", holder, hyper_voice, False) is None and holder.item == "throat-spray"
    assert hooks.item(holder, "after_use", holder, hyper_voice, True) is not None and holder.item is None


def _strike(user, foe, move, arena, rng):
    user.hp, foe.hp = user.max_hp, foe.max_hp
    armed(user, move)
    fighters = (user, foe) if user.side == 0 else (foe, user)
    return battle._resolve(1, user.side, fighters, 0, arena.weather, rng, arena)


