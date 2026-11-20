"""Abilities about the weather and the field, beyond starting them. `fighter` is a `battle._Fighter`."""

from ypoke import abilities, battle
from ypoke.effects import Handler, hooks, register
from ypoke.effects.ability_stats import staged

ENERGIZED = "booster-energy"


@register("abilities", "clears-weather")
class ClearsWeather(Handler):
    """Air Lock, Cloud Nine: the weather does nothing while the holder is out, and keeps counting down."""

    def on_entry(self, name, fighter, foe, side, weather):
        return battle.AbilityEntry(side, fighter.combatant.name, name, effect="clears-weather")

    def clears_weather(self, name):
        return True


@register("abilities", "weather-heal")
class WeatherHeal(Handler):
    """Rain Dish, Ice Body: the holder heals 1/16 of its max HP at the end of a turn in `args.weather`."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        weather = battle._weather_of(fighter)
        if fighter.hp == fighter.max_hp or not abilities.in_weather(weather, abilities.WEATHER_HEAL[name]):
            return None
        fighter.hp = min(fighter.max_hp, fighter.hp + max(1, fighter.max_hp // abilities.WEATHER_HEAL_SHARE))
        return battle.AbilityAct(turn, side, fighter.combatant.name, name, hp=fighter.hp_percent)


@register("abilities", "bad-dreams")
class BadDreams(Handler):
    """A sleeping foe loses 1/8 of its max HP at the end of each turn."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        foe = fighter.arena.foe_of(fighter) if fighter.arena is not None else None
        if foe is None or foe.hp == 0 or battle._status_of(foe) != "sleep" or battle._chip_free(foe):
            return None
        foe.hp = max(0, foe.hp - max(1, foe.max_hp // abilities.BAD_DREAMS_SHARE))
        return battle.AbilityAct(turn, side, fighter.combatant.name, name, foe=foe.combatant.name,
                                 foe_hp=foe.hp_percent, foe_fainted=foe.hp == 0)


@register("abilities", "mega-sol")
class MegaSol(Handler):
    """The holder's own moves act as in harsh sunlight, whatever the weather."""

    def own_weather(self, name, weather):
        return abilities.MEGA_SOL_WEATHER


@register("abilities", "paradox-boost")
class ParadoxBoost(Handler):
    """Protosynthesis, Quark Drive: while `args.field` (sun, Electric Terrain) is up, the holder's highest stat with
    its stages, picked as the field arrives, rises 1.3× (Speed 1.5×)."""

    def on_update(self, name, fighter, side, turn):
        if not _in_field(fighter, name) and not _energized(fighter):
            fighter.memory.pop(name, None)
            return None
        if name in fighter.memory:
            return None
        fighter.memory[name] = best = max(abilities.PARADOX_STATS, key=lambda stat: staged(fighter, stat))
        return battle.AbilityAct(turn, side, fighter.combatant.name, name, effect="paradox", detail=best)

    def modify_stat(self, name, stat, weather, fighter):
        if fighter.memory.get(name) != stat or not (_in_field(fighter, name) or ENERGIZED in fighter.memory):
            return 1.0
        return abilities.PARADOX_SPEED_BOOST if stat == "speed" else abilities.PARADOX_BOOST


def _in_field(fighter, name) -> bool:
    if fighter.arena is None:
        return False
    return abilities.PARADOX_FIELD[name] in (fighter.arena.weather.kind, fighter.arena.terrain)


def _energized(fighter) -> bool:
    """Whether a held item has boosted the holder until it switches out (Booster Energy), using it up now if not
    yet."""
    if ENERGIZED in fighter.memory:
        return True
    item = fighter.item
    if not hooks.item(fighter, "energizes", default=False):
        return False
    fighter.memory[ENERGIZED], fighter.item = True, None
    battle._announce(fighter, battle.ItemEffect(fighter.arena.turn if fighter.arena else 0, fighter.side,
                                                fighter.combatant.name, item, "energized"))
    return True
