"""Abilities that change their holder's form or type. A form ability acts only on the species it has forms for
(`Combatant.forms`, from `abilities.FORMS`); the others retype any holder. `fighter` and `holder` are
`battle._Fighter`s; a `hit` is a `battle.Hit`."""

from dataclasses import replace

from ypoke import abilities, battle, battle_data
from ypoke.effects import Handler, elsewhere, register
from ypoke.effects.ability_contact import _afflicted
from ypoke.effects.changers import reshape

FORM = "form"
BASE = "base"
MIMICRY = "mimicry"
ITEM_TYPES = battle_data.args("moves", "item-type", "types")


@register("abilities", "zen-mode")
class ZenMode(Handler):
    """At the end of a turn the holder is in Zen Mode at half HP or less and back in its own form above it."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        return _turned(fighter, "zen" if fighter.hp * 2 <= fighter.max_hp else BASE)


@register("abilities", "schooling")
class Schooling(Handler):
    """From level 20, the holder schools as it enters and at the end of a turn while above a quarter of its HP."""

    def on_entry(self, name, fighter, foe, side, weather):
        return _schooled(fighter)

    def end_of_turn(self, name, fighter, side, turn, rng):
        return _schooled(fighter)


def _schooled(fighter):
    schools = (fighter.combatant.level >= abilities.SCHOOLING_LEVEL
               and fighter.hp * abilities.SCHOOLING_FRACTION > fighter.max_hp)
    return _turned(fighter, "school" if schools else BASE)


def _turned(fighter, kind: str):
    """The `FormShift` into the species' form `kind` (BASE: the form it entered in) until it leaves, or None when it is
    in that form already or its species has none."""
    if fighter.memory.get(FORM, BASE) == kind:
        return None
    form = None if kind == BASE else _form(fighter, kind)
    if kind != BASE and form is None:
        return None
    fighter.memory[FORM] = kind
    return battle._take_form(fighter, form)


def _form(fighter, kind: str):
    return next((form for form in fighter.combatant.forms if form.kind == kind), None)


@register("abilities", "stance-change")
class StanceChange(Handler):
    """The holder takes its Blade form to use a damaging move and its own form to use King's Shield."""

    def before_move(self, name, move, attacker, side, turn):
        if move.id == abilities.STANCE_SHIELD_MOVE[name]:
            return _turned(attacker, BASE)
        return _turned(attacker, "blade") if move.damaging else None


@register("abilities", "shields-down")
class ShieldsDown(Handler):
    """Above half HP the holder keeps its shell, which no major status gets through; at half or less, checked as it
    enters and at the end of a turn, its core shows."""

    def on_entry(self, name, fighter, foe, side, weather):
        return _shielded(fighter)

    def end_of_turn(self, name, fighter, side, turn, rng):
        return _shielded(fighter)

    def blocks_ailment(self, name, ailment, holder):
        return (bool(holder.combatant.forms) and holder.memory.get(FORM, BASE) == BASE
                and ailment in abilities.MAJOR_AILMENTS)


def _shielded(fighter):
    return _turned(fighter, BASE if fighter.hp * 2 > fighter.max_hp else "core")


@register("abilities", "power-construct")
class PowerConstruct(Handler):
    """Once a turn ends with the holder at half HP or less, it takes its Complete form for the rest of the battle."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        form = _form(fighter, "complete")
        if form is None or name in fighter.once or fighter.hp * 2 > fighter.max_hp:
            return None
        fighter.once.add(name)
        return battle._take_form(fighter, form, lasting=True)


@register("abilities", "disguise")
class Disguise(Handler):
    """The first hit on the holder breaks its disguise instead, for an eighth of its max HP."""

    def takes_hit(self, name, damage, attacker, defender, move):
        form = _form(defender, "busted")
        if form is None or name in defender.once:
            return False
        defender.once.add(name)
        battle._announce(defender, battle._take_form(defender, form, lasting=True))
        defender.hp = max(0, defender.hp - defender.max_hp // abilities.DISGUISE_SHARE)
        battle._announce(defender, _act(name, defender, effect="disguise", hp=defender.hp_percent))
        return True


def _act(name, holder, changes=(), **details):
    turn = holder.arena.turn if holder.arena is not None else 0
    return battle.AbilityAct(turn, holder.side, holder.combatant.name, name, changes=tuple(changes), **details)


@register("abilities", "ice-face")
class IceFace(Handler):
    """The ice on the holder's head takes the first physical hit; snow freezes a new one."""

    def takes_hit(self, name, damage, attacker, defender, move):
        form = _form(defender, "noice")
        if form is None or not move.physical or name in defender.once:
            return False
        defender.once.add(name)
        battle._announce(defender, battle._take_form(defender, form, lasting=True))
        return True

    def on_update(self, name, fighter, side, turn):
        if name not in fighter.once or not abilities.in_weather(battle._weather_of(fighter), "snow"):
            return None
        fighter.once.discard(name)
        return battle._take_form(fighter, _form(fighter, "ice-face"), lasting=True)


@register("abilities", "gulp-missile")
class GulpMissile(Handler):
    """Surf or Dive catches prey, an Arrokuda above half HP and a Pikachu at half or less; the next hit on the holder
    spits it at the user for a quarter of the user's max HP, lowering its Defense or paralyzing it."""

    def before_move(self, name, move, attacker, side, turn):
        if move.id not in abilities.GULP_MOVES[name] or attacker.memory.get(FORM, BASE) != BASE:
            return None
        return _turned(attacker, "gulping" if attacker.hp * 2 > attacker.max_hp else "gorging")

    def damaging_hit(self, name, hit):
        holder, user = hit.target, hit.user
        caught = holder.memory.get(FORM, BASE)
        if caught == BASE or user.hp == 0:
            return None
        if not battle._chip_free(user):
            user.hp = max(0, user.hp - user.max_hp // abilities.GULP_SHARE)
        change = None
        if user.hp > 0 and caught == "gulping":
            change = battle.shift_stage(user, hit.side, "defense", -1, guarded=battle._stats_guarded(user), by=holder)
        elif user.hp > 0:
            change = _afflicted("paralysis", user, hit.side, hit.rng, holder)
        battle._announce(holder, _act(name, holder, filter(None, (change,)), effect="spit", foe=user.combatant.name,
                                      foe_hp=user.hp_percent, foe_fainted=user.hp == 0))
        return _turned(holder, BASE)


@register("abilities", "hunger-switch")
class HungerSwitch(Handler):
    """Each turn's end flips the holder between its own form and Hangry Mode, where Aura Wheel turns Dark."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        hangry = fighter.memory.get(FORM, BASE) == BASE
        shift = _turned(fighter, "hangry" if hangry else BASE)
        if shift is not None:
            fighter.combatant = replace(fighter.combatant, moves=tuple(
                replace(known, type=abilities.HUNGER_TYPE[name]) if hangry and known.id == abilities.HUNGER_MOVE[name]
                else known for known in fighter.entered_as.moves))
        return shift


@register("abilities", "forecast")
class Forecast(Handler):
    """The holder takes the form, and type, of the sun, rain or snow."""

    def on_update(self, name, fighter, side, turn):
        weather = battle._weather_of(fighter)
        kind = BASE
        if weather in ("sun", "rain"):
            kind = "sunny" if weather == "sun" else "rainy"
        elif abilities.in_weather(weather, "snow"):
            kind = "snowy"
        return _turned(fighter, kind)


@register("abilities", "flower-gift")
class FlowerGift(Handler):
    """In the sun the holder blooms, its `args.stats` 1.5×."""

    def on_update(self, name, fighter, side, turn):
        return _turned(fighter, "sunshine" if battle._weather_of(fighter) == "sun" else BASE)

    def modify_stat(self, name, key, weather, holder):
        bloomed = holder.memory.get(FORM) == "sunshine" and key in abilities.FLOWER_GIFT_STATS[name]
        return abilities.FLOWER_GIFT_BOOST if bloomed else 1.0


@register("abilities", "zero-to-hero")
class ZeroToHero(Handler):
    """Once the holder switched out by its own move, it comes back in its Hero form for the rest of the battle."""

    def on_switch_out(self, name, fighter, side):
        if _form(fighter, "hero") is not None:
            fighter.once.add(name)

    def on_entry(self, name, fighter, foe, side, weather):
        form = _form(fighter, "hero")
        if form is None or name not in fighter.once or fighter.combatant.base == form.base:
            return None
        return battle._take_form(fighter, form, lasting=True)


@register("abilities", "mimicry")
class Mimicry(Handler):
    """The holder takes the terrain's type, and its own back once the terrain is gone."""

    def on_update(self, name, fighter, side, turn):
        terrain = fighter.arena.terrain if fighter.arena is not None else None
        wanted = abilities.TERRAIN_TYPES[name].get(terrain)
        if wanted is not None and fighter.combatant.types != (wanted,):
            fighter.memory.setdefault(MIMICRY, fighter.combatant.types)
            reshape(fighter, types=(wanted,))
            return _act(name, fighter, effect="retype", detail=wanted)
        if wanted is None and MIMICRY in fighter.memory:
            fighter.combatant = replace(fighter.combatant, types=fighter.memory.pop(MIMICRY))
            return _act(name, fighter, effect="retype-back")
        return None


@register("abilities", "color-change")
class ColorChange(Handler):
    """A damaging move that hit the holder turns it into the move's type."""

    def after_move_secondary(self, name, hit):
        holder, kind = hit.target, hit.move.type
        if holder.hp == 0 or hit.on_substitute or not kind or kind in holder.combatant.types:
            return None
        reshape(holder, types=(kind,))
        return _act(name, holder, effect="retype", detail=kind)


@register("abilities", "rks-system")
class RksSystem(Handler):
    """The holder takes the type of its Memory, as Multi-Attack (`args.types_of`) does. A Memory is no battle item
    (`items.known`), so it stays on the `Combatant`."""

    def on_entry(self, name, fighter, foe, side, weather):
        kind = ITEM_TYPES.get(abilities.TYPES_OF_MOVE[name], {}).get(fighter.combatant.item)
        if kind is None or fighter.combatant.types == (kind,):
            return None
        reshape(fighter, types=(kind,))
        return battle.AbilityEntry(side, fighter.combatant.name, name, effect="retype", detail=kind)


@register("abilities", "tera-shell")
class TeraShell(Handler):
    """At full HP every hit on the holder is not very effective."""

    def caps_effectiveness(self, name, multiplier, holder):
        if holder.hp < holder.max_hp:
            return multiplier
        return min(multiplier, abilities.TERA_SHELL_EFFECTIVENESS)

    def lessens_hit(self, name, holder):
        return holder.hp == holder.max_hp


@register("abilities", "teraform-zero")
class TeraformZero(Handler):
    """Terapagos' Stellar form clears the weather and the terrain the first time it enters."""

    def on_entry(self, name, fighter, foe, side, weather):
        arena = fighter.arena
        terrain = arena.terrain if arena is not None else None
        if name in fighter.once or weather.current is None and terrain is None:
            return None
        fighter.once.add(name)
        weather.current, weather.turns_left, weather.lasting = None, 0, False
        if arena is not None:
            arena.terrain, arena.terrain_turns = None, 0
        return battle.AbilityEntry(side, fighter.combatant.name, name, effect="zero")


elsewhere("abilities", "combatants and battle._enter_forms: Terapagos enters in its Terastal form", "tera-shift")
elsewhere("abilities", "combatants: Arceus takes its plate's type, and Judgment with it", "multitype")
elsewhere("abilities", "items: Ogerpon's mask raises its stat as it enters (ogerpon-mask)", "embody-aspect")
