"""Ability handlers by effect key (`data/battle/abilities.json`). Their numbers and per-ability arguments live in
`ypoke.abilities`; `fighter` and `foe` are `battle._Fighter`s."""

from ypoke import abilities, battle
from ypoke.effects import Handler, hooks, register
from ypoke.effects.callers import transform, transformable
from ypoke.effects.changers import reshape

PROTEAN = "protean"


@register("abilities", "intimidate")
class Intimidate(Handler):
    def on_entry(self, name, fighter, foe, side, weather):
        lowers = hooks.ability(foe, "stage_factor", default=1) > 0
        if lowers and battle._stats_guarded(foe):
            return None
        answer = hooks.ability(foe, "answers_intimidate", foe, 1 - side)
        if answer is not None:
            battle._announce(foe, answer)
            return battle.AbilityTrigger(side, fighter.combatant.name, name)
        if lowers and foe.stages["attack"] <= -battle.MAX_STAGE:
            return None
        change = battle.shift_stage(foe, 1 - side, "attack", -1, by=fighter)
        battle._announce(foe, hooks.ability(foe, "after_intimidate", foe, 1 - side))
        return battle.AbilityTrigger(side, fighter.combatant.name, name, change=change)


@register("abilities", "weather-on-entry")
class WeatherOnEntry(Handler):
    def on_entry(self, name, fighter, foe, side, weather):
        kind = abilities.WEATHER_ON_ENTRY[name]
        if not _start_weather(weather, kind, fighter):
            return None
        return battle.AbilityTrigger(side, fighter.combatant.name, name, weather=kind, cleared_by=weather.cleared_by)

    def keeps_weather(self, name, kind):
        return kind == battle.STRONG_WINDS and abilities.WEATHER_ON_ENTRY[name] == kind


@register("abilities", "primal-weather")
class PrimalWeather(Handler):
    """Desolate Land, Primordial Sea: entering starts `args.weather` with no countdown. Only strong winds or the other
    one replace it, it ends once no holder is out, and damaging moves of the type it douses fail."""

    def on_entry(self, name, fighter, foe, side, weather):
        kind = abilities.PRIMAL_WEATHER[name]
        if not _start_weather(weather, kind, fighter, lasting=True):
            return None
        return battle.AbilityTrigger(side, fighter.combatant.name, name, weather=kind, cleared_by=weather.cleared_by)

    def keeps_weather(self, name, kind):
        return abilities.PRIMAL_WEATHER[name] == kind


@register("abilities", "weather-on-hit")
class WeatherOnHit(Handler):
    """Sand Spit: a damaging move that hits the holder starts `args.weather`."""

    def after_hit(self, name, hit):
        holder, kind = hit.target, abilities.WEATHER_ON_HIT[name]
        if hit.shielded or holder.arena is None or not _start_weather(holder.arena.weather, kind, holder):
            return None
        return battle.AbilityTrigger(holder.side, holder.combatant.name, name, weather=kind,
                                     cleared_by=holder.arena.weather.cleared_by)


@register("abilities", "unnerve")
class Unnerve(Handler):
    def unnerves(self, name):
        return True


@register("abilities", "gale-wings")
class GaleWings(Handler):
    def modify_priority(self, name, move, fighter):
        return int(move.type == "flying" and fighter.hp == fighter.max_hp)


@register("abilities", "attack-doubled")
class AttackDoubled(Handler):
    def modify_stat(self, name, stat, weather, fighter):
        return 2.0 if stat == "attack" else 1.0


@register("abilities", "guts")
class Guts(Handler):
    def modify_stat(self, name, stat, weather, fighter):
        return abilities.GUTS_BOOST if stat == "attack" and fighter.status is not None else 1.0

    def ignores_burn(self, name):
        return True


@register("abilities", "weather-speed")
class WeatherSpeed(Handler):
    def modify_stat(self, name, stat, weather, fighter):
        doubled = stat == "speed" and abilities.in_weather(weather, abilities.WEATHER_DOUBLES_SPEED[name])
        return 2.0 if doubled else 1.0


@register("abilities", "type-immunity")
class TypeImmunity(Handler):
    def immune_to(self, name, move, holder):
        return move.type is not None and abilities.IMMUNE_TYPE[name] == move.type


@register("abilities", "supreme-overlord")
class SupremeOverlord(Handler):
    def modify_power(self, name, move, power, user, target, weather):
        return 1 + abilities.SUPREME_OVERLORD_STEP * min(user.fallen_allies, abilities.SUPREME_OVERLORD_MAX_FALLEN)


@register("abilities", "sand-force")
class SandForce(Handler):
    def modify_power(self, name, move, power, user, target, weather):
        boosted = weather == "sandstorm" and move.type in abilities.SAND_FORCE_TYPES
        return abilities.SAND_FORCE_BOOST if boosted else 1.0


@register("abilities", "technician")
class Technician(Handler):
    def modify_power(self, name, move, power, user, target, weather):
        return abilities.TECHNICIAN_BOOST if power <= abilities.TECHNICIAN_MAX_POWER else 1.0


@register("abilities", "pinch-type-boost")
class PinchTypeBoost(Handler):
    def modify_power(self, name, move, power, user, target, weather):
        boosted = (abilities.low_hp(user) and move.type is not None
                   and abilities.LOW_HP_BOOSTED_TYPE[name] == move.type)
        return abilities.LOW_HP_BOOST if boosted else 1.0


@register("abilities", "adaptability")
class Adaptability(Handler):
    def modify_stab(self, name):
        return abilities.ADAPTABILITY_STAB


@register("abilities", "type-resist")
class TypeResist(Handler):
    def modify_damage_taken(self, name, move, multiplier, holder, user):
        return 0.5 if move.type in abilities.RESISTED_TYPES[name] else 1.0


@register("abilities", "sturdy")
class Sturdy(Handler):
    def endures(self, name, fighter, from_full, rng):
        return from_full

    def blocks_ohko(self, name):
        return True


@register("abilities", "ailment-block")
class AilmentBlock(Handler):
    def blocks_ailment(self, name, ailment, holder):
        return ailment in abilities.AILMENT_BLOCKED[name]


@register("abilities", "contact-ailment")
class ContactAilment(Handler):
    def on_contact(self, name, side, move, user, holder, rng):
        ailment = abilities.CONTACT_AILMENT[name]
        if not battle.makes_contact(user, move) or battle._blocks_ailment(user, ailment):
            return None
        if not battle._open_to(ailment, user, True) or rng.random() >= abilities.CONTACT_CHANCE:
            return None
        return battle._inflict(ailment, user, side, rng, holder)


@register("abilities", "weather-chip-immune")
class WeatherChipImmune(Handler):
    def blocks_weather_chip(self, name, weather):
        return abilities.in_weather(weather, abilities.WEATHER_CHIP_IMMUNE[name])


@register("abilities", "long-reach")
class LongReach(Handler):
    def drops_contact(self, name):
        return True


@register("abilities", "imposter")
class Imposter(Handler):
    """Entering transforms the holder into the foe, as the move Transform does."""

    def on_entry(self, name, fighter, foe, side, weather):
        if foe.hp == 0 or not transformable(fighter, foe):
            return None
        transform(fighter, foe)
        return battle.AbilityTransform(side, fighter.combatant.name, name, into=foe.combatant.name,
                                       form_id=foe.form_id or foe.combatant.pokemon_id,
                                       own_form_id=fighter.combatant.pokemon_id)


@register("abilities", "protean")
class Protean(Handler):
    """Protean, Libero: the first move after each entry turns the holder into the move's type, unless it is
    Terastallized or already only that type."""

    def before_move(self, name, move, attacker, side, turn):
        if not self.retypes_for(name, move, attacker):
            return None
        attacker.memory[PROTEAN] = True
        reshape(attacker, types=(move.type,))
        return battle.AbilityRetype(side, attacker.combatant.name, name, into=move.type)

    def retypes_for(self, name, move, attacker):
        return not (PROTEAN in attacker.memory or not move.type or attacker.combatant.tera
                    or attacker.combatant.types == (move.type,) or hooks.move(move, "hits_later", default=False))


def _start_weather(weather, kind, setter, lasting=False) -> bool:
    """Starts `kind` for the turns the setter's item gives. The same weather keeps it out, and held weather (strong
    winds, Desolate Land's) keeps out all but strong winds and another `lasting` one."""
    if (weather.current == kind and weather.lasting == lasting
            or weather.held and not lasting and kind != battle.STRONG_WINDS):
        return False
    weather.kind, weather.lasting = kind, lasting
    default = battle.WEATHER_TURNS
    weather.turns_left = hooks.item(setter, "weather_turns", kind, default, default=default)
    return True
