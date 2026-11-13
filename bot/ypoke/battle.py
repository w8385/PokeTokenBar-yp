"""Automatic one-on-one battle: base stats, level (capped at 50), IVs, natures, type effectiveness and
level-up moves with PP, priority, critical-hit stages, multi-hit, drain and recoil, the major statuses
(burn, paralysis, poison, toxic, sleep, freeze), confusion, stat stages and five-turn weather. No items,
abilities or switching."""

import random
from dataclasses import dataclass, field

from ypoke.type_chart import effectiveness

STAB_MULTIPLIER = 1.5
CRITICAL_MULTIPLIER = 1.5
CRITICAL_CHANCES = (1 / 24, 1 / 8, 1 / 2, 1.0)
BURN_DAMAGE_FRACTION = 16
POISON_DAMAGE_FRACTION = 8
TOXIC_DAMAGE_FRACTION = 16
FULL_PARALYSIS_CHANCE = 0.25
STRUGGLE_RECOIL_FRACTION = 4
MAX_STAGE = 6
TURN_LIMIT = 300
BATTLE_LEVEL = 50
BATTLE_STATS = ("attack", "defense", "special_attack", "special_defense", "speed")
WEATHER_TURNS = 5
WEATHER_CHIP_FRACTION = 16
WEATHER_MOVE_BOOST = {
    "sun": {"fire": 1.5, "water": 0.5},
    "rain": {"water": 1.5, "fire": 0.5},
}
WEATHER_CHIP_IMMUNE_TYPES = {"sandstorm": {"rock", "ground", "steel"}, "hail": {"ice"}}
SPECIAL_DEFENSE_BOOSTED_TYPE = {"sandstorm": "rock"}
DEFENSE_BOOSTED_TYPE = {"snow": "ice"}
WEATHER_SWING_MIN = 1.3
WEATHER_CHIP_SWING = 1.5
FREEZE_THAW_CHANCE = 0.2
CONFUSION_SELF_HIT_CHANCE = 1 / 3
CONFUSION_SELF_HIT_POWER = 40
SLEEP_TURNS = (1, 3)
CONFUSION_TURNS = (2, 5)
MULTI_HIT_ODDS = {2: 35, 3: 35, 4: 15, 5: 15}
AILMENT_IMMUNE_TYPES = {
    "burn": ("fire",), "paralysis": ("electric",), "poison": ("poison", "steel"), "toxic": ("poison", "steel"),
    "freeze": ("ice",), "sleep": (), "confusion": (),
}
RESIDUAL_FRACTIONS = {"burn": BURN_DAMAGE_FRACTION, "poison": POISON_DAMAGE_FRACTION}
_NATURE_ORDER = ("attack", "defense", "speed", "special_attack", "special_defense")
_NATURE_NAMES = (
    "hardy lonely brave adamant naughty bold docile relaxed impish lax timid hasty serious jolly naive "
    "modest mild quiet bashful rash calm gentle sassy careful quirky"
).split()
NATURE_MODIFIERS = {
    name: (_NATURE_ORDER[index // 5], _NATURE_ORDER[index % 5]) for index, name in enumerate(_NATURE_NAMES)
    if index // 5 != index % 5
}


@dataclass(frozen=True)
class BaseStats:
    hp: int
    attack: int
    defense: int
    special_attack: int
    special_defense: int
    speed: int


@dataclass(frozen=True)
class Move:
    name: str
    type: str | None
    power: int
    physical: bool
    accuracy: int | None = None
    pp: int = 20
    crit_stage: int = 0
    ailment: str | None = None
    ailment_chance: int = 0
    stat_changes: tuple[tuple[str, int], ...] = ()
    stat_on_user: bool = False
    stat_chance: int = 0
    priority: int = 0
    weather: str | None = None
    always_hits_in: tuple[str, ...] = ()
    drain: int = 0
    min_hits: int = 1
    max_hits: int = 1

    @property
    def expected_hits(self) -> float:
        if (self.min_hits, self.max_hits) == (2, 5):
            return sum(hits * odds for hits, odds in MULTI_HIT_ODDS.items()) / 100
        return (self.min_hits + self.max_hits) / 2


STRUGGLE = Move("발버둥", None, 50, physical=True)
CONFUSION_HIT = Move("혼란", None, CONFUSION_SELF_HIT_POWER, physical=True)


@dataclass(frozen=True)
class Combatant:
    name: str
    level: int
    types: tuple[str, ...]
    base: BaseStats
    ivs: BaseStats
    shiny: bool = False
    moves: tuple[Move, ...] = ()
    rental: bool = False
    nature: str | None = None

    @property
    def label(self) -> str:
        return f"{self.name}{'✨' if self.shiny else ''} Lv{self.level}"


@dataclass(frozen=True)
class Change:
    """An effect that landed: a status (`AILMENT_IMMUNE_TYPES` key), "thaw", or a `BATTLE_STATS` key with `stages`."""

    side: int
    pokemon: str
    kind: str
    stages: int = 0


@dataclass(frozen=True)
class Action:
    """One Pokémon's turn. `move` is "" when it could not act; `blocked` says why ("paralysis", "sleep", "freeze"
    or "confusion", the last one meaning it hurt itself and `attacker_hp` is its HP share).
    `recovered` lists what ended before it acted ("sleep", "freeze", "confusion"). `hits` counts a multi-hit
    move's hits; `drained` means the user healed from the damage."""

    turn: int
    side: int
    attacker: str
    defender: str
    move: str
    missed: bool = False
    multiplier: float = 1.0
    critical: bool = False
    changes: tuple[Change, ...] = ()
    recoil: bool = False
    defender_hp: int = 100
    knockout: bool = False
    attacker_fainted: bool = False
    weather: str | None = None
    failed: bool = False
    blocked: str = ""
    recovered: tuple[str, ...] = ()
    hits: int = 1
    drained: bool = False
    attacker_hp: int = 100


@dataclass(frozen=True)
class StatusDamage:
    """End-of-turn damage from `kind` ("burn", "poison" or "toxic")."""

    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool
    kind: str = "burn"


@dataclass(frozen=True)
class WeatherDamage:
    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool
    weather: str


@dataclass(frozen=True)
class WeatherEnd:
    turn: int
    weather: str


Event = Action | StatusDamage | WeatherDamage | WeatherEnd


@dataclass
class BattleResult:
    winner: int
    turns: int
    events: list[Event] = field(default_factory=list)


def simulate(sides: tuple[Combatant, Combatant], seed: int) -> BattleResult:
    """Fight until one Pokémon faints or `TURN_LIMIT` turns pass; then the higher HP share wins.

    Each turn a Pokémon picks its move with the highest expected damage that still has PP, or Struggle.
    The higher move priority acts first, then the faster Pokémon; a full tie is a coin flip from the seed.
    A weather move is picked when it swings the exchange by `WEATHER_SWING_MIN`; the weather lasts `WEATHER_TURNS` turns.
    """
    rng = random.Random(seed)
    fighters = (_Fighter.enter(sides[0]), _Fighter.enter(sides[1]))
    events: list[Event] = []
    weather = _Weather()
    turn = 0
    loser: int | None = None
    while loser is None and turn < TURN_LIMIT:
        turn += 1
        choices = (
            _best_move(fighters[0], fighters[1], weather.kind), _best_move(fighters[1], fighters[0], weather.kind),
        )
        for side in _turn_order(fighters, choices, rng):
            action = _act(turn, side, fighters, choices[side], weather, rng)
            events.append(action)
            if action.knockout:
                loser = 1 - side
            elif action.attacker_fainted:
                loser = side
            if loser is not None:
                break
        for side in (0, 1):
            fighter = fighters[side]
            if loser is None and fighter.status in ("burn", "poison", "toxic"):
                fighter.hp = max(0, fighter.hp - fighter.residual_damage())
                events.append(
                    StatusDamage(turn, side, fighter.combatant.name, fighter.hp_percent, fighter.hp == 0, fighter.status)
                )
                if fighter.hp == 0:
                    loser = side
        if loser is None:
            loser = _weather_upkeep(turn, fighters, weather, events)
    if loser is None:
        loser = 1 if fighters[0].hp / fighters[0].max_hp >= fighters[1].hp / fighters[1].max_hp else 0
    return BattleResult(winner=1 - loser, turns=turn, events=events)


@dataclass
class _Weather:
    kind: str | None = None
    turns_left: int = 0


@dataclass
class _Fighter:
    combatant: Combatant
    max_hp: int
    hp: int
    stats: dict[str, int]
    pp: list[int]
    stages: dict[str, int] = field(default_factory=lambda: dict.fromkeys(BATTLE_STATS, 0))
    status: str | None = None
    sleep_left: int = 0
    toxic_ticks: int = 0
    confusion_left: int = 0

    @classmethod
    def enter(cls, combatant: Combatant) -> "_Fighter":
        base, ivs, level = combatant.base, combatant.ivs, combatant.level
        max_hp = 1 if base.hp == 1 else (2 * base.hp + ivs.hp) * level // 100 + level + 10
        stats = {key: _other_stat(getattr(base, key), getattr(ivs, key), level) for key in BATTLE_STATS}
        if combatant.nature in NATURE_MODIFIERS:
            up, down = NATURE_MODIFIERS[combatant.nature]
            stats[up] = stats[up] * 110 // 100
            stats[down] = stats[down] * 90 // 100
        return cls(combatant, max_hp, max_hp, stats, [move.pp for move in combatant.moves])

    @property
    def hp_percent(self) -> int:
        return 0 if self.hp <= 0 else max(1, round(self.hp * 100 / self.max_hp))

    def residual_damage(self) -> int:
        if self.status == "toxic":
            self.toxic_ticks += 1
            return max(1, self.max_hp * self.toxic_ticks // TOXIC_DAMAGE_FRACTION)
        return max(1, self.max_hp // RESIDUAL_FRACTIONS[self.status])

    def stat(self, key: str) -> float:
        stage = self.stages[key]
        value = self.stats[key] * ((2 + stage) / 2 if stage >= 0 else 2 / (2 - stage))
        if key == "speed" and self.status == "paralysis":
            value /= 2
        return value


def _turn_order(fighters: tuple[_Fighter, _Fighter], choices: tuple[int | None, int | None],
                rng: random.Random) -> tuple[int, int]:
    keys = [
        (0 if choice is None else fighter.combatant.moves[choice].priority, fighter.stat("speed"))
        for fighter, choice in zip(fighters, choices)
    ]
    if keys[0] != keys[1]:
        return (0, 1) if keys[0] > keys[1] else (1, 0)
    return (0, 1) if rng.random() < 0.5 else (1, 0)


def _weather_upkeep(turn: int, fighters: tuple[_Fighter, _Fighter], weather: _Weather,
                    events: list[Event]) -> int | None:
    """Chip damage, then the countdown. Returns the side that fainted, if any."""
    if weather.kind is None:
        return None
    for side, fighter in enumerate(fighters):
        if _chipped_by(fighter, weather.kind):
            fighter.hp = max(0, fighter.hp - max(1, fighter.max_hp // WEATHER_CHIP_FRACTION))
            events.append(WeatherDamage(
                turn, side, fighter.combatant.name, fighter.hp_percent, fighter.hp == 0, weather.kind,
            ))
            if fighter.hp == 0:
                return side
    weather.turns_left -= 1
    if weather.turns_left == 0:
        events.append(WeatherEnd(turn, weather.kind))
        weather.kind = None
    return None


def _chipped_by(fighter: _Fighter, weather: str | None) -> bool:
    immune = WEATHER_CHIP_IMMUNE_TYPES.get(weather)
    return immune is not None and not immune.intersection(fighter.combatant.types)


def _act(turn: int, side: int, fighters: tuple[_Fighter, _Fighter], index: int | None, weather: _Weather,
         rng: random.Random) -> Action:
    attacker, defender = fighters[side], fighters[1 - side]
    names = (attacker.combatant.name, defender.combatant.name)
    move = STRUGGLE if index is None else attacker.combatant.moves[index]
    recovered, blocked = _start_of_action(attacker, move, rng)
    if blocked:
        if blocked == "confusion":
            attacker.hp = max(0, attacker.hp - _damage(attacker, attacker, CONFUSION_HIT, 1.0, False, None, rng))
        return Action(
            turn, side, *names, move="", defender_hp=defender.hp_percent, blocked=blocked, recovered=recovered,
            attacker_hp=attacker.hp_percent, attacker_fainted=attacker.hp == 0,
        )
    if index is not None:
        attacker.pp[index] -= 1
    if move.weather:
        if weather.kind == move.weather:
            return Action(turn, side, *names, move.name, failed=True, recovered=recovered,
                          defender_hp=defender.hp_percent)
        weather.kind, weather.turns_left = move.weather, WEATHER_TURNS
        return Action(turn, side, *names, move.name, weather=move.weather, recovered=recovered,
                      defender_hp=defender.hp_percent)
    multiplier = _multiplier(move, defender)
    if move.accuracy is not None and weather.kind not in move.always_hits_in and rng.random() * 100 >= move.accuracy:
        return Action(turn, side, *names, move.name, missed=True, multiplier=multiplier, recovered=recovered,
                      defender_hp=defender.hp_percent)
    if multiplier == 0:
        return Action(turn, side, *names, move.name, multiplier=0, recovered=recovered, defender_hp=defender.hp_percent)
    critical, hits, dealt = False, 0, 0
    for _ in range(_hit_count(move, rng)):
        hit_critical = rng.random() < CRITICAL_CHANCES[min(move.crit_stage, len(CRITICAL_CHANCES) - 1)]
        damage = min(defender.hp, _damage(attacker, defender, move, multiplier, hit_critical, weather.kind, rng))
        defender.hp -= damage
        critical, hits, dealt = critical or hit_critical, hits + 1, dealt + damage
        if defender.hp == 0:
            break
    changes = () if defender.hp == 0 else _secondary_effects(side, move, attacker, defender, rng)
    recoil, drained = move is STRUGGLE, move.drain > 0
    if recoil:
        attacker.hp = max(0, attacker.hp - max(1, attacker.max_hp // STRUGGLE_RECOIL_FRACTION))
    elif move.drain < 0:
        attacker.hp = max(0, attacker.hp - max(1, dealt * -move.drain // 100))
        recoil = True
    elif drained:
        attacker.hp = min(attacker.max_hp, attacker.hp + max(1, dealt * move.drain // 100))
    return Action(
        turn, side, *names, move.name, multiplier=multiplier, critical=critical, changes=changes, recoil=recoil,
        defender_hp=defender.hp_percent, knockout=defender.hp == 0, attacker_fainted=attacker.hp == 0,
        recovered=recovered, hits=hits, drained=drained, attacker_hp=attacker.hp_percent,
    )


def _start_of_action(attacker: _Fighter, move: Move, rng: random.Random) -> tuple[tuple[str, ...], str]:
    """What ended before the Pokémon acts, and what stops it from using its move ("" if nothing)."""
    recovered: list[str] = []
    if attacker.status == "sleep":
        if attacker.sleep_left > 0:
            attacker.sleep_left -= 1
            return (), "sleep"
        attacker.status = None
        recovered.append("sleep")
    elif attacker.status == "freeze":
        thawed = rng.random() < FREEZE_THAW_CHANCE or move.type == "fire"
        if not thawed:
            return (), "freeze"
        attacker.status = None
        recovered.append("freeze")
    if attacker.confusion_left > 0:
        attacker.confusion_left -= 1
        if attacker.confusion_left == 0:
            recovered.append("confusion")
        elif rng.random() < CONFUSION_SELF_HIT_CHANCE:
            return tuple(recovered), "confusion"
    if attacker.status == "paralysis" and rng.random() < FULL_PARALYSIS_CHANCE:
        return tuple(recovered), "paralysis"
    return tuple(recovered), ""


def _hit_count(move: Move, rng: random.Random) -> int:
    if move.max_hits <= 1:
        return 1
    if (move.min_hits, move.max_hits) == (2, 5):
        return rng.choices(list(MULTI_HIT_ODDS), weights=list(MULTI_HIT_ODDS.values()))[0]
    return rng.randint(move.min_hits, move.max_hits)


def _damage(attacker: _Fighter, defender: _Fighter, move: Move, multiplier: float, critical: bool,
            weather: str | None, rng: random.Random) -> int:
    damage = _unrolled_damage(attacker, defender, move, multiplier, weather)
    damage *= (CRITICAL_MULTIPLIER if critical else 1.0) * rng.randint(85, 100) / 100
    return max(1, int(damage))


def _unrolled_damage(attacker: _Fighter, defender: _Fighter, move: Move, multiplier: float,
                     weather: str | None) -> float:
    attack, defense = _stats_for(attacker, defender, move.physical, weather)
    level = attacker.combatant.level
    damage = ((2 * level // 5 + 2) * move.power * attack / max(1, defense)) // 50 + 2
    return damage * _stab(attacker, move) * multiplier * _weather_boost(move, weather)


def _secondary_effects(side: int, move: Move, attacker: _Fighter, defender: _Fighter,
                       rng: random.Random) -> tuple[Change, ...]:
    changes: list[Change] = []
    if _ailment_lands(move, defender, rng):
        changes.append(_inflict(move.ailment, defender, 1 - side, rng))
    if defender.status == "freeze" and move.type == "fire":
        defender.status = None
        changes.append(Change(1 - side, defender.combatant.name, "thaw"))
    if move.stat_changes and rng.random() * 100 < move.stat_chance:
        target, target_side = (attacker, side) if move.stat_on_user else (defender, 1 - side)
        for key, stages in move.stat_changes:
            before = target.stages[key]
            target.stages[key] = max(-MAX_STAGE, min(MAX_STAGE, before + stages))
            if target.stages[key] != before:
                changes.append(Change(target_side, target.combatant.name, key, target.stages[key] - before))
    return tuple(changes)


def _ailment_lands(move: Move, defender: _Fighter, rng: random.Random) -> bool:
    if move.ailment not in AILMENT_IMMUNE_TYPES:
        return False
    if any(kind in defender.combatant.types for kind in AILMENT_IMMUNE_TYPES[move.ailment]):
        return False
    occupied = defender.confusion_left > 0 if move.ailment == "confusion" else defender.status is not None
    return not occupied and rng.random() * 100 < move.ailment_chance


def _inflict(ailment: str, defender: _Fighter, side: int, rng: random.Random) -> Change:
    if ailment == "confusion":
        defender.confusion_left = rng.randint(*CONFUSION_TURNS)
    else:
        defender.status = ailment
        defender.toxic_ticks = 0
        if ailment == "sleep":
            defender.sleep_left = rng.randint(*SLEEP_TURNS)
    return Change(side, defender.combatant.name, ailment)


def _best_move(attacker: _Fighter, defender: _Fighter, weather: str | None) -> int | None:
    """Index of the move to use; None means Struggle.

    The damaging move with PP left and the highest score, unless a weather move swings the exchange and no
    damaging move is sure to finish the foe.
    """
    best, best_score = None, -1.0
    for index, move in enumerate(attacker.combatant.moves):
        if attacker.pp[index] <= 0 or move.weather:
            continue
        score = _move_score(attacker, defender, move, weather)
        if score > best_score:
            best, best_score = index, score
    if best is not None and _surely_finishes(attacker, defender, attacker.combatant.moves[best], weather):
        return best
    setter = _best_weather_move(attacker, defender, weather)
    return best if setter is None else setter


def _surely_finishes(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None) -> bool:
    """Whether a hit with the lowest damage roll that cannot miss knocks the defender out."""
    never_misses = move.accuracy in (None, 100) or weather in move.always_hits_in
    damage = _unrolled_damage(attacker, defender, move, _multiplier(move, defender), weather)
    return never_misses and damage * 0.85 >= defender.hp


def _best_weather_move(attacker: _Fighter, defender: _Fighter, weather: str | None) -> int | None:
    best, best_swing = None, WEATHER_SWING_MIN
    for index, move in enumerate(attacker.combatant.moves):
        if attacker.pp[index] > 0 and move.weather and move.weather != weather:
            swing = _weather_swing(attacker, defender, weather, move.weather)
            if swing >= best_swing:
                best, best_swing = index, swing
    return best


def _weather_swing(attacker: _Fighter, defender: _Fighter, now: str | None, new: str) -> float:
    """How much better the exchange gets for `attacker` if `new` replaces `now`: damage ratio × chip damage asymmetry."""
    mine = _best_score(attacker, defender, new) / max(1.0, _best_score(attacker, defender, now))
    theirs = max(1.0, _best_score(defender, attacker, now)) / max(1.0, _best_score(defender, attacker, new))
    chip = (_chipped_by(defender, new) - _chipped_by(defender, now)) - (_chipped_by(attacker, new) - _chipped_by(attacker, now))
    return mine * theirs * WEATHER_CHIP_SWING ** chip


def _best_score(attacker: _Fighter, defender: _Fighter, weather: str | None) -> float:
    scores = [
        _move_score(attacker, defender, move, weather)
        for index, move in enumerate(attacker.combatant.moves)
        if attacker.pp[index] > 0 and not move.weather
    ]
    return max(scores, default=0.0)


def _move_score(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None) -> float:
    """Power × STAB × type × weather × accuracy × attack/defense."""
    attack, defense = _stats_for(attacker, defender, move.physical, weather)
    accuracy = 100 if move.accuracy is None or weather in move.always_hits_in else move.accuracy
    return (
        move.power * move.expected_hits * _stab(attacker, move) * _multiplier(move, defender)
        * _weather_boost(move, weather)
        * accuracy * attack / max(1, defense)
    )


def _weather_boost(move: Move, weather: str | None) -> float:
    return WEATHER_MOVE_BOOST.get(weather, {}).get(move.type, 1.0)


def _stab(attacker: _Fighter, move: Move) -> float:
    return STAB_MULTIPLIER if move.type in attacker.combatant.types else 1.0


def _multiplier(move: Move, defender: _Fighter) -> float:
    return 1.0 if move.type is None else effectiveness(move.type, defender.combatant.types)


def _stats_for(attacker: _Fighter, defender: _Fighter, physical: bool,
               weather: str | None = None) -> tuple[float, float]:
    boosted = (DEFENSE_BOOSTED_TYPE if physical else SPECIAL_DEFENSE_BOOSTED_TYPE).get(weather)
    boost = 1.5 if boosted in defender.combatant.types else 1.0
    if physical:
        burned = 0.5 if attacker.status == "burn" else 1.0
        return attacker.stat("attack") * burned, defender.stat("defense") * boost
    return attacker.stat("special_attack"), defender.stat("special_defense") * boost


def _other_stat(base: int, iv: int, level: int) -> int:
    return (2 * base + iv) * level // 100 + 5
