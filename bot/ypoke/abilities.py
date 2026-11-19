"""Battle abilities by PokéAPI name ("huge-power"), from `data/battle/abilities.json`: the numbers their handlers
(`ypoke.effects.abilities`) use. An ability that runs none of `EFFECT_KEYS` does nothing."""

from ypoke import battle_data

EFFECT_KEYS = frozenset({
    "pinch-type-boost", "intimidate", "type-immunity", "attack-doubled", "type-resist", "technician", "sturdy",
    "adaptability", "guts", "weather-speed", "weather-on-entry", "contact-ailment", "ailment-block", "sand-force",
    "weather-chip-immune", "gale-wings", "supreme-overlord", "terrain-on-entry", "field-stat", "screen-cleaner",
    "infiltrator", "airborne", "imposter", "protean",
    "flag-power", "type-power", "ate", "normalize", "liquid-voice", "reckless", "sheer-force", "serene-grace",
    "shield-dust", "analytic", "stakeout", "status-power", "stat-boost", "hustle", "choice-lock", "status-stat",
    "solar-power", "defeatist", "slow-start", "damage-dealt", "super-taken", "full-hp-taken", "taken", "heatproof",
    "aura", "aura-break", "ruin", "parental-bond", "skill-link", "weight", "rock-head", "long-reach", "guard-piercing",
    "accuracy-boost", "stat-guard", "ignores-evasion", "scrappy", "intimidate-immune", "tangled-feet",
    "weather-evasion", "wonder-skin", "super-luck", "merciless", "crit-guard", "no-guard", "unaware",
    "absorb-heal", "absorb-boost", "flash-fire", "dry-skin", "move-block", "good-as-gold", "priority-block",
    "wonder-guard", "weatherproof", "magic-bounce", "liquid-ooze",
    "ko-boost", "beast-boost", "soul-heart", "stat-answer", "entry-boost", "supersweet-syrup", "download", "hit-boost",
    "rattled", "half-hp-boost", "anger-point", "charge-on-hit", "tailwind-charge", "tailwind-boost", "cotton-down",
    "speed-boost", "moody", "contrary", "simple", "mirror-armor", "guard-dog", "opportunist", "steadfast", "unnerve",
    "weather-on-hit", "terrain-on-hit", "hazard-on-hit",
    "prankster", "triage", "stall", "quick-draw", "mycelium-might", "unburden", "truant", "pressure", "damp", "dancer",
    "synchronize", "shed-skin", "hydration", "natural-cure", "poison-heal", "magic-guard", "comatose", "leaf-guard",
    "flower-veil", "corrosion", "early-bird", "regenerator",
})
POWER_FLAG = battle_data.args("abilities", "flag-power", "flag")
FLAG_POWER = battle_data.args("abilities", "flag-power", "power")
POWER_TYPE = battle_data.args("abilities", "type-power", "type")
TYPE_POWER = battle_data.args("abilities", "type-power", "power")
ATE_TYPE = battle_data.args("abilities", "ate", "type")
ATE_POWER = 1.2
RECKLESS_POWER = 1.2
SHEER_FORCE_POWER = 5325 / 4096
ANALYTIC_POWER = 5325 / 4096
STATUS_POWER_PHYSICAL = battle_data.args("abilities", "status-power", "physical")
POWER_STATUSES = battle_data.args("abilities", "status-power", "statuses")
STATUS_POWER = 1.5
BOOSTED_STAT = battle_data.args("abilities", "stat-boost", "stat")
STAT_BOOST = battle_data.args("abilities", "stat-boost", "boost")
HUSTLE_ACCURACY = 0.8
STATUS_STAT_KEY = battle_data.args("abilities", "status-stat", "stat")
STATUS_STAT = 1.5
SOLAR_POWER_BOOST = 1.5
SOLAR_POWER_CHIP = 8
SLOW_START_TURNS = 5
DEALT_WHEN = battle_data.args("abilities", "damage-dealt", "when")
DEALT_MULTIPLIER = battle_data.args("abilities", "damage-dealt", "dealt")
SUPER_TAKEN = 0.75
TAKEN = battle_data.args("abilities", "taken", "taken")
AURA_TYPE = battle_data.args("abilities", "aura", "type")
AURA_POWER = 5448 / 4096
AURA_BROKEN = 3072 / 4096
RUINED_STAT = battle_data.args("abilities", "ruin", "stat")
RUIN = 0.75
PARENTAL_BOND_SECOND = 0.25
WEIGHT_MULTIPLIER = battle_data.args("abilities", "weight", "weight")
ACCURACY_BOOST = battle_data.args("abilities", "accuracy-boost", "accuracy")
GUARDED_STATS = battle_data.args("abilities", "stat-guard", "stats")
SCRAPPY_TYPES = ("normal", "fighting")
TANGLED_FEET_ACCURACY = 0.5
EVASION_WEATHER = battle_data.args("abilities", "weather-evasion", "weather")
WEATHER_EVASION_ACCURACY = 0.8
WONDER_SKIN_ACCURACY = 50
ABSORBED = {**battle_data.args("abilities", "absorb-heal", "absorbs"),
            **battle_data.args("abilities", "absorb-boost", "absorbs"),
            **battle_data.args("abilities", "flash-fire", "absorbs")}
ABSORB_RAISES = battle_data.args("abilities", "absorb-boost", "raises")
ABSORB_HEAL_FRACTION = 4
FLASH_FIRE_POWER = 1.5
DRY_SKIN_FIRE_POWER = 1.25
DRY_SKIN_SHARE = 8
BLOCKED_MOVES = battle_data.args("abilities", "move-block", "blocks")
KO_RAISES = battle_data.args("abilities", "ko-boost", "raises")
SOUL_HEART_RAISES = (("special_attack", 1),)
ANSWER_RAISES = battle_data.args("abilities", "stat-answer", "raises")
ENTRY_RAISES = battle_data.args("abilities", "entry-boost", "raises")
HIT_RAISES = {**battle_data.args("abilities", "hit-boost", "raises"),
              **battle_data.args("abilities", "rattled", "raises")}
HIT_TYPES = battle_data.args("abilities", "hit-boost", "types")
HIT_PHYSICAL = battle_data.args("abilities", "hit-boost", "physical")
HALF_HP_RAISES = battle_data.args("abilities", "half-hp-boost", "raises")
CHARGE_FLAG = battle_data.args("abilities", "charge-on-hit", "flag")
CHARGE_STATE = "charge"
CHARGE_TURNS = 2
TAILWIND = "tailwind"
TAILWIND_RAISES = battle_data.args("abilities", "tailwind-boost", "raises")
STEADFAST_BAN = "flinch"
WEATHER_ON_HIT = battle_data.args("abilities", "weather-on-hit", "weather")
TERRAIN_ON_HIT = battle_data.args("abilities", "terrain-on-hit", "terrain")
HAZARD_ON_HIT = battle_data.args("abilities", "hazard-on-hit", "hazard")
PRANKSTER_PRIORITY = 1
PRANKSTER_FOILED_TYPE = "dark"
TRIAGE_PRIORITY = 3
TRIAGE_FLAG = "heal"
QUICK_DRAW_CHANCE = 0.3
DAMP_MOVES = battle_data.args("abilities", "damp", "moves")
DANCE_FLAG = "dance"
MAJOR_AILMENTS = frozenset({"burn", "freeze", "paralysis", "poison", "toxic", "sleep"})
POISONS = frozenset({"poison", "toxic"})
SYNCED_AILMENTS = battle_data.args("abilities", "synchronize", "ailments")
POISON_HEAL_SHARE = 8
REGENERATOR_SHARE = 3
COMATOSE_STATUS = "sleep"
FLOWER_VEIL_TYPE = "grass"
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
SHED_SKIN_CHANCE = 0.33

NAMES = battle_data.bot_names("abilities")


def low_hp(fighter) -> bool:
    return fighter.hp * LOW_HP_FRACTION <= fighter.max_hp


def in_weather(weather: str | None, wanted: str) -> bool:
    """Snow abilities count hail too, the older games' snow."""
    return weather is not None and (weather == wanted or wanted == "snow" and weather == "hail")


# A foe's move or ability that ignores abilities (Mold Breaker, Sunsteel Strike) leaves these out.
BREAKABLE = frozenset(name for name, entry in battle_data.table("abilities").items()
                      if "breakable" in entry.get("flags", ()))
# Neutralizing Gas leaves these on.
UNSUPPRESSED = frozenset({
    "as-one-glastrier", "as-one-spectrier", "battle-bond", "comatose", "commander", "disguise", "gulp-missile",
    "ice-face", "multitype", "neutralizing-gas", "power-construct", "rks-system", "schooling", "shields-down",
    "stance-change", "tera-shift", "zen-mode", "zero-to-hero",
})
