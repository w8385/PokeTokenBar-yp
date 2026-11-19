"""Ability handlers by effect key (`data/battle/abilities.json`). Their numbers and per-ability arguments live in
`ypoke.abilities`; `fighter` and `foe` are `battle._Fighter`s."""

from ypoke import abilities, battle
from ypoke.effects import Handler, hooks, register


@register("abilities", "intimidate")
class Intimidate(Handler):
    def on_entry(self, name, fighter, foe, side, weather):
        if foe.stages["attack"] <= -battle.MAX_STAGE or battle._stats_guarded(foe):
            return None
        foe.stages["attack"] -= 1
        foe.lowered = True
        change = battle.Change(1 - side, foe.combatant.name, "attack", -1)
        return battle.AbilityTrigger(side, fighter.combatant.name, name, change=change)


@register("abilities", "weather-on-entry")
class WeatherOnEntry(Handler):
    def on_entry(self, name, fighter, foe, side, weather):
        kind = abilities.WEATHER_ON_ENTRY[name]
        if weather.kind == kind or weather.kind == battle.STRONG_WINDS and kind != battle.STRONG_WINDS:
            return None
        weather.kind = kind
        default = battle.WEATHER_TURNS
        weather.turns_left = hooks.item(fighter, "weather_turns", kind, default, default=default)
        return battle.AbilityTrigger(side, fighter.combatant.name, name, weather=kind)

    def keeps_weather(self, name, kind):
        return kind == battle.STRONG_WINDS and abilities.WEATHER_ON_ENTRY[name] == kind


@register("abilities", "gale-wings")
class GaleWings(Handler):
    def modify_priority(self, name, move, fighter):
        return int(move.type == "flying" and fighter.hp == fighter.max_hp)


@register("abilities", "attack-doubled")
class AttackDoubled(Handler):
    def modify_stat(self, name, stat, weather, statused, can_evolve):
        return 2.0 if stat == "attack" else 1.0


@register("abilities", "guts")
class Guts(Handler):
    def modify_stat(self, name, stat, weather, statused, can_evolve):
        return abilities.GUTS_BOOST if stat == "attack" and statused else 1.0

    def ignores_burn(self, name):
        return True


@register("abilities", "weather-speed")
class WeatherSpeed(Handler):
    def modify_stat(self, name, stat, weather, statused, can_evolve):
        doubled = stat == "speed" and weather is not None and abilities.WEATHER_DOUBLES_SPEED[name] == weather
        return 2.0 if doubled else 1.0


@register("abilities", "type-immunity")
class TypeImmunity(Handler):
    def immune_to(self, name, move_type):
        return move_type is not None and abilities.IMMUNE_TYPE[name] == move_type


@register("abilities", "supreme-overlord")
class SupremeOverlord(Handler):
    def modify_power(self, name, move_type, power, low_hp, weather, fallen_allies):
        return 1 + abilities.SUPREME_OVERLORD_STEP * min(fallen_allies, abilities.SUPREME_OVERLORD_MAX_FALLEN)


@register("abilities", "sand-force")
class SandForce(Handler):
    def modify_power(self, name, move_type, power, low_hp, weather, fallen_allies):
        boosted = weather == "sandstorm" and move_type in abilities.SAND_FORCE_TYPES
        return abilities.SAND_FORCE_BOOST if boosted else 1.0


@register("abilities", "technician")
class Technician(Handler):
    def modify_power(self, name, move_type, power, low_hp, weather, fallen_allies):
        return abilities.TECHNICIAN_BOOST if power <= abilities.TECHNICIAN_MAX_POWER else 1.0


@register("abilities", "pinch-type-boost")
class PinchTypeBoost(Handler):
    def modify_power(self, name, move_type, power, low_hp, weather, fallen_allies):
        boosted = low_hp and move_type is not None and abilities.LOW_HP_BOOSTED_TYPE[name] == move_type
        return abilities.LOW_HP_BOOST if boosted else 1.0


@register("abilities", "adaptability")
class Adaptability(Handler):
    def modify_stab(self, name):
        return abilities.ADAPTABILITY_STAB


@register("abilities", "type-resist")
class TypeResist(Handler):
    def modify_damage_taken(self, name, move_type):
        return 0.5 if move_type in abilities.RESISTED_TYPES[name] else 1.0


@register("abilities", "sturdy")
class Sturdy(Handler):
    def endures(self, name, fighter, from_full, rng):
        return from_full

    def blocks_ohko(self, name):
        return True


@register("abilities", "ailment-block")
class AilmentBlock(Handler):
    def blocks_ailment(self, name, ailment):
        return ailment in abilities.AILMENT_BLOCKED[name]


@register("abilities", "contact-ailment")
class ContactAilment(Handler):
    def on_contact(self, name, side, move, user, holder, rng):
        ailment = abilities.CONTACT_AILMENT[name]
        if not battle.makes_contact(user, move) or hooks.ability(user, "blocks_ailment", ailment, default=False):
            return None
        if not battle._open_to(ailment, user, True) or rng.random() >= abilities.CONTACT_CHANCE:
            return None
        return battle._inflict(ailment, user, side, rng)


@register("abilities", "weather-chip-immune")
class WeatherChipImmune(Handler):
    def blocks_weather_chip(self, name, weather):
        return weather is not None and abilities.WEATHER_CHIP_IMMUNE[name] == weather


@register("abilities", "long-reach")
class LongReach(Handler):
    def drops_contact(self, name):
        return True
