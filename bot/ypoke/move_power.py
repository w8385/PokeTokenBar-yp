"""Moves whose power or type depends on the battle, by the Gen 9 rules. `battle` takes a move's type from `typed`
before it scores or uses the move, and its base power before abilities from `power`; every other move keeps
PokéAPI's. `user` and `target` are `battle._Fighter`s."""

from dataclasses import dataclass, replace

from ypoke import battle_data, items, tera_forms
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
FACADE_KEY = "facade"
HYDRO_STEAM_KEY = "hydro-steam"
IGNORES_BURN = battle_data.ids("moves", FACADE_KEY)
SUN_BOOST = dict.fromkeys(battle_data.ids("moves", HYDRO_STEAM_KEY), 1.5)


def typed(move, weather: str | None):
    """Weather Ball takes the weather's type; any other move comes back as it is."""
    kind = WEATHER_BALL_TYPES.get(weather) if move.id == WEATHER_BALL else None
    return move if kind is None else replace(move, type=kind)


def power(move, user, target, weather: str | None, multiplier: float, hit: int | None = None) -> float:
    """`multiplier` is the type effectiveness on `target`; `hit` the 0-based hit of a multi-hit move, None for the
    mean hit."""
    rule = _RULES.get(move.id)
    if rule is None:
        return move.power
    return rule(move.power, _Scene(user, target, weather, multiplier, hit, move.max_hits))


def holds_removable_item(fighter) -> bool:
    """Knock Off takes any item but one that sets the holder's form (Mega Stone, plate on Arceus, mask, origin item)."""
    if not _holds_item(fighter):
        return False
    item, pokemon_id = fighter.item or fighter.combatant.item, fighter.combatant.pokemon_id
    bound = (item in tera_forms.MASKS or item in tera_forms.ITEM_FORMS or item == items.STELLAR_CRYSTAL
             or pokemon_id == tera_forms.ARCEUS and item in items.PLATES)
    return not bound and (pokemon_id is None or mega_form_id(item, pokemon_id) is None)


@dataclass(frozen=True)
class _Scene:
    user: object
    target: object
    weather: str | None
    multiplier: float
    hit: int | None
    max_hits: int


def _holds_item(fighter) -> bool:
    """An item the battle does not know is never used up, so it is held until Knock Off takes it."""
    held = fighter.combatant.item
    return fighter.item is not None or (held is not None and items.known(held) is None and not fighter.item_lost)


def _doubled(base: int, condition: bool) -> int:
    return base * 2 if condition else base


def _by_hp(base: int, scene: _Scene) -> int:
    return max(1, base * scene.user.hp // scene.user.max_hp)


def _by_boosts(base: int, scene: _Scene) -> int:
    return base + STAT_BOOST_POWER * sum(max(0, stage) for stage in scene.user.stages.values())


def _by_hit(base: int, scene: _Scene) -> float:
    if scene.hit is None:
        return base * (scene.max_hits + 1) / 2
    return base * (scene.hit + 1)


_RULE_BY_KEY = {
    "power-last-respects": lambda base, scene: base + base * scene.user.fallen_allies,
    "power-by-user-hp": _by_hp,
    "power-hex": lambda base, scene: _doubled(base, scene.target.status is not None),
    FACADE_KEY: lambda base, scene: _doubled(base, scene.user.status in FACADE_STATUSES),
    "power-brine": lambda base, scene: _doubled(base, scene.target.hp * 2 <= scene.target.max_hp),
    "power-vs-poisoned": lambda base, scene: _doubled(base, scene.target.status in POISONED),
    "power-acrobatics": lambda base, scene: _doubled(base, not _holds_item(scene.user)),
    "weather-ball": lambda base, scene: _doubled(base, scene.weather in WEATHER_BALL_TYPES),
    "power-stored": _by_boosts,
    "power-rage-fist": lambda base, scene: min(RAGE_FIST_MAX_POWER, base + base * scene.user.times_hit),
    "power-revenge": lambda base, scene: _doubled(base, scene.user.hit_by_foe),
    "power-payback": lambda base, scene: _doubled(base, scene.target.acted),
    "power-moves-first": lambda base, scene: _doubled(base, not scene.target.acted),
    "power-retaliate": lambda base, scene: _doubled(base, scene.user.ally_fell_last_turn),
    "power-after-fail": lambda base, scene: _doubled(base, scene.user.flopped_last),
    "power-lash-out": lambda base, scene: _doubled(base, scene.user.lowered),
    "knock-off": lambda base, scene: base * KNOCK_OFF_BOOST if holds_removable_item(scene.target) else base,
    "power-super-effective": lambda base, scene: base * SUPER_EFFECTIVE_BOOST if scene.multiplier > 1 else base,
    "power-solar": lambda base, scene: base / 2 if scene.weather in SOLAR_WEAK_WEATHERS else base,
    "power-by-hit": _by_hit,
}
_RULES = {move_id: rule for key, rule in _RULE_BY_KEY.items() for move_id in battle_data.with_key("moves", key)}
EFFECT_KEYS = frozenset({*_RULE_BY_KEY, HYDRO_STEAM_KEY})
