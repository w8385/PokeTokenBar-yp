"""Abilities about the holder's own item: berries, and keeping or idling the item. `fighter` is a `battle._Fighter`."""

from ypoke import abilities, battle
from ypoke.effects import Handler, hooks, register


@register("abilities", "cheek-pouch")
class CheekPouch(Handler):
    """Eating a berry also heals a third of the holder's max HP."""

    def on_berry_eaten(self, name, fighter, berry):
        if fighter.hp in (0, fighter.max_hp):
            return None
        fighter.hp = min(fighter.max_hp, fighter.hp + max(1, fighter.max_hp // abilities.CHEEK_POUCH_SHARE))
        return _act(name, fighter, hp=fighter.hp_percent)


@register("abilities", "cud-chew")
class CudChew(Handler):
    """A berry the holder ate from its own hand is eaten again at the end of the next turn, once."""

    def on_berry_eaten(self, name, fighter, berry):
        if name not in fighter.memory and berry == fighter.combatant.item:
            fighter.memory[name] = (berry, _turn(fighter))

    def end_of_turn(self, name, fighter, side, turn, rng):
        berry, eaten = fighter.memory.get(name, (None, turn))
        if eaten >= turn:
            return None
        held, fighter.item = fighter.item, berry
        event = hooks.call("items", berry, "eaten", fighter, side, turn)
        fighter.item = held
        del fighter.memory[name]
        return battle.AbilityAct(turn, side, fighter.combatant.name, name, effect="chew", detail=berry), event


@register("abilities", "gluttony")
class Gluttony(Handler):
    def pinch_fraction(self, name):
        return abilities.GLUTTONY_PINCH_FRACTION


@register("abilities", "harvest")
class Harvest(Handler):
    """At the end of each turn, a berry the holder ate grows back: half the time, always in sun."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        berry = fighter.combatant.item
        if (fighter.item is not None or fighter.item_lost or not fighter.ate_berry or berry is None
                or not berry.endswith("-berry")):
            return None
        if (battle._weather_of(fighter) != abilities.HARVEST_SURE_WEATHER
                and rng.random() >= abilities.HARVEST_CHANCE):
            return None
        fighter.item = berry
        return battle.AbilityAct(turn, side, fighter.combatant.name, name, effect="harvest", detail=berry)


@register("abilities", "klutz")
class Klutz(Handler):
    def idles_item(self, name):
        return True


@register("abilities", "ripen")
class Ripen(Handler):
    def berry_factor(self, name):
        return abilities.RIPEN_FACTOR


@register("abilities", "sticky-hold")
class StickyHold(Handler):
    def keeps_item(self, name):
        return True


def _act(name, fighter, **details):
    return battle.AbilityAct(_turn(fighter), fighter.side, fighter.combatant.name, name, **details)


def _turn(fighter) -> int:
    return fighter.arena.turn if fighter.arena is not None else 0
