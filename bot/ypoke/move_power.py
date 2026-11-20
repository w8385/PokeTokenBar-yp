"""Moves whose power or type depends on the battle, by the Gen 9 rules (their handlers are in `ypoke.effects.moves`).
`battle` takes a move's type from `typed` before it scores or uses the move, and its base power before abilities from
`power`; every other move keeps PokéAPI's. `user` and `target` are `battle._Fighter`s."""

from dataclasses import dataclass, replace

from ypoke import items, tera_forms
from ypoke.effects import hooks
from ypoke.mega_stones import mega_form_id

SOLAR_BEAM = 76
TRIPLE_KICK = 167
FACADE = 263
REVENGE = 279
KNOCK_OFF = 282
ERUPTION = 284
WEATHER_BALL = 311
WATER_SPOUT = 323
BRINE = 362
PAYBACK = 371
AVALANCHE = 419
VENOSHOCK = 474
STORED_POWER = 500
HEX = 506
ACROBATICS = 512
RETALIATE = 514
SOLAR_BLADE = 669
POWER_TRIP = 681
STOMPING_TANTRUM = 707
BOLT_BEAK = 754
FISHIOUS_REND = 755
LASH_OUT = 808
TRIPLE_AXEL = 813
DRAGON_ENERGY = 820
BARB_BARRAGE = 839
LAST_RESPECTS = 854
HYDRO_STEAM = 876
COLLISION_COURSE = 878
ELECTRO_DRIFT = 879
RAGE_FIST = 889
TEMPER_FLARE = 915

WEATHER_BALL_TYPES = {"sun": "fire", "rain": "water", "sandstorm": "rock", "hail": "ice", "snow": "ice"}
SOLAR_WEAK_WEATHERS = ("rain", "sandstorm", "hail", "snow")
FACADE_STATUSES = ("burn", "poison", "toxic", "paralysis")
POISONED = ("poison", "toxic")
STAT_BOOST_POWER = 20
RAGE_FIST_MAX_POWER = 350
KNOCK_OFF_BOOST = 1.5
SUPER_EFFECTIVE_BOOST = 5461 / 4096
HYDRO_STEAM_SUN_BOOST = 1.5
EFFECT_KEYS = frozenset({
    "power-last-respects", "power-by-user-hp", "power-hex", "facade", "power-brine", "power-vs-poisoned",
    "power-acrobatics", "weather-ball", "power-stored", "power-rage-fist", "power-revenge", "power-payback",
    "power-moves-first", "power-retaliate", "power-after-fail", "power-lash-out", "knock-off", "power-super-effective",
    "power-solar", "power-by-hit", "hydro-steam",
})


def typed(move, weather: str | None, user=None):
    """Weather Ball takes the weather's type and Terrain Pulse its grounded `user`'s terrain's; any other move comes
    back as it is. The user's ability may then change its type (Pixilate)."""
    if user is not None:
        weather = hooks.ability(user, "own_weather", weather, default=weather)
    moved = hooks.move(move, "modify_type", weather, user, default=move)
    kind = None if user is None else hooks.ability(user, "retypes", moved)
    return moved if kind is None or kind == moved.type else replace(moved, type=kind)


def power(move, user, target, weather: str | None, multiplier: float, hit: int | None = None) -> float:
    """`multiplier` is the type effectiveness on `target`; `hit` the 0-based hit of a multi-hit move, None for the
    mean hit."""
    scene = Scene(user, target, hooks.ability(user, "own_weather", weather, default=weather), multiplier, hit,
                  move.max_hits)
    return hooks.move(move, "base_power", move.power, scene, default=move.power)


def holds_removable_item(fighter) -> bool:
    """Knock Off takes any item but one that sets the holder's form (Mega Stone, plate on Arceus, mask, origin item,
    drive on Genesect, memory on Silvally)."""
    if not holds_item(fighter):
        return False
    item, pokemon_id = fighter.item or fighter.combatant.item, fighter.combatant.pokemon_id
    bound = (item in tera_forms.MASKS or item in tera_forms.ITEM_FORMS or item == items.STELLAR_CRYSTAL
             or pokemon_id == tera_forms.ARCEUS and item in items.PLATES
             or pokemon_id is not None and items.FORM_BOUND.get(item) == pokemon_id)
    return not bound and (pokemon_id is None or mega_form_id(item, pokemon_id) is None)


def kept(fighter) -> bool:
    """Its ability keeps what it holds from any other Pokémon (Sticky Hold)."""
    return holds_item(fighter) and hooks.ability(fighter, "keeps_item", default=False)


def holds_item(fighter) -> bool:
    """An item the battle does not know is never used up, so it is held until Knock Off takes it."""
    held = fighter.combatant.item
    return fighter.item is not None or (held is not None and items.known(held) is None and not fighter.item_lost)


@dataclass(frozen=True)
class Scene:
    user: object
    target: object
    weather: str | None
    multiplier: float
    hit: int | None
    max_hits: int
