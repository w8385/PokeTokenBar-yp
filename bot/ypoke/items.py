"""Held items: PokéAPI item slugs the battle simulation understands (`data/battle/items.json`) and the numbers their
handlers (`ypoke.effects.items`) use. Anything else is ignored."""

from ypoke import battle_data
from ypoke.effects import hooks

LEFTOVERS = "leftovers"
CHOICE_SCARF = "choice-scarf"
CHOICE_BAND = "choice-band"
CHOICE_SPECS = "choice-specs"
FOCUS_SASH = "focus-sash"
FOCUS_BAND = "focus-band"
LIFE_ORB = "life-orb"
EXPERT_BELT = "expert-belt"
ASSAULT_VEST = "assault-vest"
EVIOLITE = "eviolite"
ROCKY_HELMET = "rocky-helmet"
SITRUS_BERRY = "sitrus-berry"
LUM_BERRY = "lum-berry"
WHITE_HERB = "white-herb"
BLACK_SLUDGE = "black-sludge"
SHELL_BELL = "shell-bell"
BIG_ROOT = "big-root"
MUSCLE_BAND = "muscle-band"
WISE_GLASSES = "wise-glasses"
SCOPE_LENS = "scope-lens"
RAZOR_CLAW = "razor-claw"
QUICK_CLAW = "quick-claw"
BRIGHT_POWDER = "bright-powder"
WIDE_LENS = "wide-lens"
WEAKNESS_POLICY = "weakness-policy"
FLAME_ORB = "flame-orb"
TOXIC_ORB = "toxic-orb"
CHARCOAL = "charcoal"
STELLAR_CRYSTAL = "stellar-crystal"
PUNCHING_GLOVE = "punching-glove"
EFFECT_KEYS = frozenset({
    LEFTOVERS, CHOICE_SCARF, CHOICE_BAND, CHOICE_SPECS, FOCUS_SASH, FOCUS_BAND, LIFE_ORB, EXPERT_BELT, ASSAULT_VEST,
    EVIOLITE, ROCKY_HELMET, SITRUS_BERRY, LUM_BERRY, WHITE_HERB, BLACK_SLUDGE, SHELL_BELL, BIG_ROOT, MUSCLE_BAND,
    WISE_GLASSES, SCOPE_LENS, RAZOR_CLAW, QUICK_CLAW, BRIGHT_POWDER, WIDE_LENS, WEAKNESS_POLICY, PUNCHING_GLOVE,
    "type-boost", "resist-berry", "plate", "origin-boost", "weather-rock", "status-orb",
})

TYPE_ORDER = ("fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground", "flying", "psychic", "bug",
              "rock", "ghost", "dragon", "dark", "steel", "normal", "fairy")


def _in_type_order(by_item: dict[str, str]) -> dict[str, str]:
    return dict(sorted(by_item.items(), key=lambda pair: TYPE_ORDER.index(pair[1])))


TYPE_BOOST_ITEMS = _in_type_order(battle_data.args("items", "type-boost", "type"))
# Halves one hit of the type, then is used up. All but Chilan wait for a super-effective hit.
RESIST_BERRIES = _in_type_order(battle_data.args("items", "resist-berry", "type"))
PLATES = _in_type_order(battle_data.args("items", "plate", "type"))
# The types an origin item boosts; it works only on its own species (`tera_forms.usable_item`).
ORIGIN_BOOSTS = battle_data.args("items", "origin-boost", "types")
WEATHER_ROCKS = battle_data.args("items", "weather-rock", "weathers")
OGERPON_MASKS = tuple(battle_data.with_key("items", "ogerpon-mask"))
ORB_AILMENTS = battle_data.args("items", "status-orb", "ailment")
ITEM_NAMES = battle_data.bot_names("items", unless="mega-stone")
LEFTOVERS_FRACTION = 16
BLACK_SLUDGE_HURT_FRACTION = 8
LIFE_ORB_RECOIL_FRACTION = 10
ROCKY_HELMET_FRACTION = 6
SITRUS_THRESHOLD_FRACTION = 2
SITRUS_HEAL_FRACTION = 4
SHELL_BELL_FRACTION = 8
FOCUS_BAND_CHANCE = 0.1
QUICK_CLAW_CHANCE = 0.2
CHOICE_MULTIPLIER = 1.5
VEST_MULTIPLIER = 1.5
LIFE_ORB_MULTIPLIER = 1.3
BOOST_MULTIPLIER = 1.2
BAND_MULTIPLIER = 1.1
BIG_ROOT_MULTIPLIER = 1.3
RESIST_BERRY_MULTIPLIER = 0.5
BRIGHT_POWDER_ACCURACY = 0.9
WIDE_LENS_ACCURACY = 1.1
ROCK_WEATHER_TURNS = 8


def known(item: str | None) -> str | None:
    return item if item in ITEM_NAMES else None


def stat_multiplier(item: str | None, key: str, can_evolve: bool = False) -> float:
    return hooks.call("items", item, "modify_stat", key, None, False, can_evolve, default=1.0)


def damage_multiplier(item: str | None, move_type: str | None, effectiveness: float, physical: bool = True,
                      punch: bool = False) -> float:
    return hooks.call("items", item, "modify_damage", move_type, effectiveness, physical, punch, default=1.0)


def weather_turns(item: str | None, weather: str, default: int) -> int:
    return hooks.call("items", item, "weather_turns", weather, default, default=default)
