"""Battle abilities by PokéAPI name ("huge-power"), from `data/battle/abilities.json`. An ability that runs none of
`EFFECT_KEYS` does nothing."""

from ypoke import battle_data

EFFECT_KEYS = frozenset({
    "pinch-type-boost", "intimidate", "type-immunity", "attack-doubled", "type-resist", "technician", "sturdy",
    "adaptability", "guts", "weather-speed", "weather-on-entry", "contact-ailment", "ailment-block", "sand-force",
    "weather-chip-immune", "gale-wings", "supreme-overlord",
})
LOW_HP_FRACTION = 3
LOW_HP_BOOSTED_TYPE = battle_data.args("abilities", "pinch-type-boost", "type")
LOW_HP_BOOST = 1.5
TECHNICIAN_MAX_POWER = 60
TECHNICIAN_BOOST = 1.5
ADAPTABILITY_STAB = 2.0
GUTS_BOOST = 1.5
ATTACK_DOUBLED = tuple(battle_data.with_key("abilities", "attack-doubled"))
SAND_FORCE_TYPES = ("rock", "ground", "steel")
SAND_FORCE_BOOST = 1.3
SUPREME_OVERLORD_STEP = 0.1
SUPREME_OVERLORD_MAX_FALLEN = 5
WEATHER_CHIP_IMMUNE = battle_data.args("abilities", "weather-chip-immune", "weather")
WEATHER_DOUBLES_SPEED = battle_data.args("abilities", "weather-speed", "weather")
WEATHER_ON_ENTRY = battle_data.args("abilities", "weather-on-entry", "weather")
RESISTED_TYPES = battle_data.args("abilities", "type-resist", "types")
IMMUNE_TYPE = battle_data.args("abilities", "type-immunity", "type")
AILMENT_BLOCKED = battle_data.args("abilities", "ailment-block", "ailments")
CONTACT_AILMENT = battle_data.args("abilities", "contact-ailment", "ailment")
CONTACT_CHANCE = 0.3

NAMES = battle_data.bot_names("abilities")


def entry_trigger(ability: str | None) -> bool:
    return ability == "intimidate" or ability in WEATHER_ON_ENTRY


def power_multiplier(ability: str | None, move_type: str | None, power: float, low_hp: bool,
                     weather: str | None = None, fallen_allies: int = 0) -> float:
    if ability == "supreme-overlord":
        return 1 + SUPREME_OVERLORD_STEP * min(fallen_allies, SUPREME_OVERLORD_MAX_FALLEN)
    if ability == "sand-force" and weather == "sandstorm" and move_type in SAND_FORCE_TYPES:
        return SAND_FORCE_BOOST
    if ability == "technician" and power <= TECHNICIAN_MAX_POWER:
        return TECHNICIAN_BOOST
    if low_hp and move_type is not None and LOW_HP_BOOSTED_TYPE.get(ability) == move_type:
        return LOW_HP_BOOST
    return 1.0


def stat_multiplier(ability: str | None, stat: str, weather: str | None, statused: bool) -> float:
    if stat == "attack":
        if ability in ATTACK_DOUBLED:
            return 2.0
        if ability == "guts" and statused:
            return GUTS_BOOST
    if stat == "speed" and weather is not None and WEATHER_DOUBLES_SPEED.get(ability) == weather:
        return 2.0
    return 1.0


def stab(ability: str | None) -> float | None:
    return ADAPTABILITY_STAB if ability == "adaptability" else None


def damage_taken_multiplier(ability: str | None, move_type: str | None) -> float:
    return 0.5 if move_type in RESISTED_TYPES.get(ability, ()) else 1.0


def blocks_ailment(ability: str | None, ailment: str | None) -> bool:
    return ailment in AILMENT_BLOCKED.get(ability, ())


def ignores_weather_chip(ability: str | None, weather: str | None) -> bool:
    return weather is not None and WEATHER_CHIP_IMMUNE.get(ability) == weather


def priority_bonus(ability: str | None, move_type: str | None, full_hp: bool) -> int:
    """Gale Wings: a Flying move goes +1 while the user is at full HP."""
    return int(ability == "gale-wings" and move_type == "flying" and full_hp)


def grants_immunity(ability: str | None, move_type: str | None) -> bool:
    return move_type is not None and IMMUNE_TYPE.get(ability) == move_type
