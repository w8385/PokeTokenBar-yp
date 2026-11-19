"""Battle abilities by PokéAPI name ("huge-power"), from `data/battle/abilities.json`: the numbers their handlers
(`ypoke.effects.abilities`) use. An ability that runs none of `EFFECT_KEYS` does nothing."""

from ypoke import battle_data
from ypoke.effects import hooks

EFFECT_KEYS = frozenset({
    "pinch-type-boost", "intimidate", "type-immunity", "attack-doubled", "type-resist", "technician", "sturdy",
    "adaptability", "guts", "weather-speed", "weather-on-entry", "contact-ailment", "ailment-block", "sand-force",
    "weather-chip-immune", "gale-wings", "supreme-overlord", "terrain-on-entry", "field-stat", "screen-cleaner",
    "infiltrator", "airborne", "long-reach",
})
LOW_HP_FRACTION = 3
LOW_HP_BOOSTED_TYPE = battle_data.args("abilities", "pinch-type-boost", "type")
LOW_HP_BOOST = 1.5
TECHNICIAN_MAX_POWER = 60
TECHNICIAN_BOOST = 1.5
ADAPTABILITY_STAB = 2.0
GUTS_BOOST = 1.5
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
TERRAIN_ON_ENTRY = battle_data.args("abilities", "terrain-on-entry", "terrain")
FIELD_STAT_STATE = battle_data.args("abilities", "field-stat", "field")
FIELD_STAT_STAT = battle_data.args("abilities", "field-stat", "stat")
FIELD_STAT_MULTIPLIER = battle_data.args("abilities", "field-stat", "multiplier")

NAMES = battle_data.bot_names("abilities")


def power_multiplier(ability: str | None, move_type: str | None, power: float, low_hp: bool,
                     weather: str | None = None, fallen_allies: int = 0) -> float:
    return hooks.call("abilities", ability, "modify_power", move_type, power, low_hp, weather, fallen_allies,
                      default=1.0)
