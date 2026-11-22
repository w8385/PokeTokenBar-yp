"""Held items that change how their holder's moves land, hit, chain or bind, the ones that burden their holder, and the
species forms of Genesect's drives and Silvally's memories. Their numbers live in `ypoke.items`; `fighter`, `holder`
and `target` are `battle._Fighter`s."""

from ypoke import battle, items, move_power
from ypoke.effects import Handler, hooks, register
from ypoke.effects.after_hit import log, turn
from ypoke.effects.item_moves import hold, received, yields
from ypoke.effects.secondary import meta

MULTI_HIT_RANGE = (2, 5)


@register("items", "zoom-lens")
class ZoomLens(Handler):
    """Raises its holder's accuracy against a target that already moved this turn."""

    def accuracy_as_user(self, name, target):
        return items.ZOOM_LENS_ACCURACY if target is not None and target.acted else 1.0


@register("items", "metronome")
class Metronome(Handler):
    """Each use in a row of the same move that worked adds a fifth to its damage, up to double. The streak is kept in
    `memory` as (move id, worked, streak) and ends with the switch."""

    def streak_boost(self, name, holder, move):
        return 1.0 + items.METRONOME_STEP * _streak(holder, name, move)

    def after_use(self, name, fighter, move, worked):
        fighter.memory[name] = (move.id, worked, _streak(fighter, name, move))


def _streak(holder, name, move) -> int:
    last = holder.memory.get(name)
    if last is None or last[0] != move.id or not last[1]:
        return 0
    return min(last[2] + 1, items.METRONOME_MAX_STEPS)


@register("items", "loaded-dice")
class LoadedDice(Handler):
    """A 2–5 hit move hits 4 or 5 times; Population Bomb hits 4 to 10 times; every multi-hit move draws accuracy only
    once."""

    def hit_count(self, name, move, rng):
        if (move.min_hits, move.max_hits) == MULTI_HIT_RANGE:
            return rng.choice(items.LOADED_DICE_HITS)
        if _rolls_each_hit(move) and move.max_hits > max(items.LOADED_DICE_HITS):
            return rng.randint(min(items.LOADED_DICE_HITS), move.max_hits)
        return None

    def expected_hits(self, name, move, expected):
        if (move.min_hits, move.max_hits) == MULTI_HIT_RANGE:
            return sum(items.LOADED_DICE_HITS) / len(items.LOADED_DICE_HITS)
        if _rolls_each_hit(move) and move.max_hits > max(items.LOADED_DICE_HITS):
            return (min(items.LOADED_DICE_HITS) + move.max_hits) / 2
        return expected

    def skips_hit_rolls(self, name):
        return True


def _rolls_each_hit(move) -> bool:
    return hooks.move(move, "rolls_each_hit", default=False)


@register("items", "flinch-item")
class FlinchItem(Handler):
    """King's Rock and Razor Fang: each hit of the holder's damaging move that cannot flinch on its own may flinch a
    target that has not moved."""

    def adds_secondary(self, name, hit):
        target, move = hit.target, hit.move
        if hit.on_substitute or target.hp == 0 or target.acted or meta(move, "flinch_chance") > 0:
            return
        chance = items.FLINCH_ITEM_CHANCE * battle._chance_scale(move, hit.user, target)
        if hit.rng.random() < chance and not battle._blocks_ailment(target, "flinch"):
            target.volatiles["flinch"] = True


@register("items", "grip-claw")
class GripClaw(Handler):
    def bind_turns(self, name):
        return items.GRIP_CLAW_TURNS


@register("items", "binding-band")
class BindingBand(Handler):
    def bind_share(self, name):
        return items.BINDING_BAND_SHARE


@register("items", "sticky-barb")
class StickyBarb(Handler):
    """Hurts its holder 1/8 of its max HP each turn, and clings to an attacker that makes contact and holds nothing."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        if battle._chip_free(fighter):
            return None
        fighter.hp = max(0, fighter.hp - max(1, fighter.max_hp // items.STICKY_BARB_FRACTION))
        return battle.ItemHeal(turn, side, fighter.combatant.name, name, fighter.hp_percent, fighter.hp == 0)

    def damaging_hit(self, name, hit):
        fighter, attacker, move = hit.target, hit.user, hit.move
        if (hit.reached and attacker.hp > 0 and battle.makes_contact(attacker, move)
                and not move_power.holds_item(attacker) and yields(fighter)):
            hold(fighter, None)
            hold(attacker, name)
            log(attacker).extend(received(attacker, attacker.side, turn(attacker)))
        return False

    def burdens(self, name, holder):
        return True


@register("items", "float-stone")
class FloatStone(Handler):
    def modify_weight(self, name):
        return items.FLOAT_STONE_WEIGHT


@register("items", "ring-target")
class RingTarget(Handler):
    def drops_immunities(self, name):
        return True


@register("items", "drive", "memory")
class FormBound(Handler):
    """Genesect enters in its drive's form and Silvally in its memory's; on any other species the item does nothing
    here (Techno Blast and Multi-Attack take its type from `combatants`)."""

    def on_entry_form(self, name, fighter, side, turn):
        if fighter.combatant.pokemon_id != items.FORM_BOUND[name]:
            return None
        return battle.FormShift(turn, side, fighter.combatant.name, name)
