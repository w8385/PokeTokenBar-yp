"""Abilities that stop a foe's move on their holder: they absorb it, block it by a flag, its priority or its kind,
or bounce it back. `holder` is a `battle._Fighter`; the numbers live in `ypoke.abilities`."""

from ypoke import abilities, battle
from ypoke.effects import Handler, register
from ypoke.effects.protection import aimed, attacking


class Absorb(Handler):
    """A foe's move of `args.absorbs` (a type, or a move flag such as "wind") aimed at the holder fails, before its
    accuracy draw; `absorbs` says what the holder gets from it."""

    def stops_move(self, name, move, priority, holder, attacker):
        absorbed = abilities.ABSORBED[name]
        return (attacking(move) or aimed(move)) and (move.type == absorbed or move.flagged(absorbed))


@register("abilities", "absorb-heal")
class AbsorbHeal(Absorb):
    """Volt Absorb, Water Absorb, Earth Eater, Dry Skin: heals 1/4 of its max HP."""

    def absorbs(self, name, move, holder, side):
        if holder.hp == holder.max_hp:
            return ()
        holder.hp = min(holder.max_hp, holder.hp + max(1, holder.max_hp // abilities.ABSORB_HEAL_FRACTION))
        return (battle.Change(side, holder.combatant.name, "healed"),)


@register("abilities", "absorb-boost")
class AbsorbBoost(Absorb):
    """Lightning Rod, Storm Drain, Motor Drive, Sap Sipper, Well-Baked Body, Wind Rider: raises `args.raises`."""

    def absorbs(self, name, move, holder, side):
        raised = (battle.shift_stage(holder, side, stat, stages) for stat, stages in abilities.ABSORB_RAISES[name])
        return tuple(change for change in raised if change is not None)


@register("abilities", "flash-fire")
class FlashFire(Absorb):
    """Once a Fire move is absorbed, the holder's Fire moves hit 1.5× until it leaves the field."""

    def absorbs(self, name, move, holder, side):
        if holder.memory.get(name):
            return ()
        holder.memory[name] = True
        return (battle.Change(side, holder.combatant.name, name),)

    def modify_power(self, name, move, power, user, target, weather):
        return abilities.FLASH_FIRE_POWER if move.type == "fire" and user.memory.get(name) else 1.0


@register("abilities", "dry-skin")
class DrySkin(Handler):
    """Fire moves hit the holder 1.25×; it heals 1/8 of its max HP at the end of a turn in rain and loses as much in
    sun."""

    def modify_foe_power(self, name, move, holder):
        return abilities.DRY_SKIN_FIRE_POWER if move.type == "fire" else 1.0

    def end_of_turn(self, name, fighter, side, turn, rng):
        weather = battle._weather_of(fighter)
        share = max(1, fighter.max_hp // abilities.DRY_SKIN_SHARE)
        if weather == "rain" and fighter.hp < fighter.max_hp:
            fighter.hp = min(fighter.max_hp, fighter.hp + share)
        elif weather == "sun" and not battle._chip_free(fighter):
            fighter.hp = max(0, fighter.hp - share)
        else:
            return None
        return battle.AbilityAct(turn, side, fighter.combatant.name, name, hp=fighter.hp_percent,
                                 fainted=fighter.hp == 0)


@register("abilities", "move-block")
class MoveBlock(Handler):
    """Bulletproof, Soundproof, Overcoat, Oblivious: a foe's move aimed at the holder fails when it has a flag or an
    effect key in `args.blocks` (bullet, sound, powder; Taunt)."""

    def stops_move(self, name, move, priority, holder, attacker):
        blocks = abilities.BLOCKED_MOVES[name]
        return (attacking(move) or aimed(move)) and (move.effect in blocks or any(map(move.flagged, blocks)))


@register("abilities", "good-as-gold")
class GoodAsGold(Handler):
    def stops_move(self, name, move, priority, holder, attacker):
        return aimed(move)


@register("abilities", "priority-block")
class PriorityBlock(Handler):
    """Dazzling, Queenly Majesty, Armor Tail: a foe's move with raised priority aimed at the holder fails."""

    def stops_move(self, name, move, priority, holder, attacker):
        return priority > 0 and (attacking(move) or aimed(move))


@register("abilities", "wonder-guard")
class WonderGuard(Handler):
    """Only super-effective attacks hurt the holder."""

    def immune_to(self, name, move, holder):
        return move.damaging and battle.effectiveness(move.type, holder.combatant.types) <= 1


@register("abilities", "weatherproof")
class Weatherproof(Handler):
    """Overcoat: no weather chips the holder."""

    def blocks_weather_chip(self, name, weather):
        return True


@register("abilities", "magic-bounce")
class MagicBounce(Handler):
    """A foe's status move aimed at the holder acts on the foe instead, like Magic Coat that never wears off."""

    def reflects(self, name, move):
        return True


@register("abilities", "liquid-ooze")
class LiquidOoze(Handler):
    def inverts_drain(self, name):
        return True
