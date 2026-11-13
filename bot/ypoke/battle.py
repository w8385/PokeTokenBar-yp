"""Automatic one-on-one battle: base stats, level, IVs, type effectiveness and level-up moves with PP,
critical-hit stages, burn, paralysis and stat stages. No items, abilities, priority or switching."""

import random
from dataclasses import dataclass, field

from ypoke.type_chart import effectiveness

STAB_MULTIPLIER = 1.5
CRITICAL_MULTIPLIER = 1.5
CRITICAL_CHANCES = (1 / 24, 1 / 8, 1 / 2, 1.0)
BURN_DAMAGE_FRACTION = 16
FULL_PARALYSIS_CHANCE = 0.25
STRUGGLE_RECOIL_FRACTION = 4
MAX_STAGE = 6
TURN_LIMIT = 300
BATTLE_STATS = ("attack", "defense", "special_attack", "special_defense", "speed")
AILMENT_IMMUNE_TYPE = {"burn": "fire", "paralysis": "electric"}


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


STRUGGLE = Move("발버둥", None, 50, physical=True)


@dataclass(frozen=True)
class Combatant:
    name: str
    level: int
    types: tuple[str, ...]
    base: BaseStats
    ivs: BaseStats
    shiny: bool = False
    moves: tuple[Move, ...] = ()

    @property
    def label(self) -> str:
        return f"{self.name}{'✨' if self.shiny else ''} Lv{self.level}"


@dataclass(frozen=True)
class Change:
    """A secondary effect that landed: `kind` is "burn", "paralysis" or a `BATTLE_STATS` key with `stages`."""

    side: int
    pokemon: str
    kind: str
    stages: int = 0


@dataclass(frozen=True)
class Action:
    """One Pokémon's turn. `move` is "" when it was fully paralyzed."""

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


@dataclass(frozen=True)
class BurnDamage:
    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool


@dataclass
class BattleResult:
    winner: int
    turns: int
    events: list[Action | BurnDamage] = field(default_factory=list)


def simulate(sides: tuple[Combatant, Combatant], seed: int) -> BattleResult:
    """Fight until one Pokémon faints or `TURN_LIMIT` turns pass; then the higher HP share wins.

    Each turn a Pokémon uses its move with the highest expected damage that still has PP, or Struggle.
    """
    rng = random.Random(seed)
    fighters = (_Fighter.enter(sides[0]), _Fighter.enter(sides[1]))
    events: list[Action | BurnDamage] = []
    turn = 0
    loser: int | None = None
    while loser is None and turn < TURN_LIMIT:
        turn += 1
        for side in _turn_order(fighters, rng):
            action = _act(turn, side, fighters, rng)
            events.append(action)
            if action.knockout:
                loser = 1 - side
            elif action.attacker_fainted:
                loser = side
            if loser is not None:
                break
        for side in (0, 1):
            fighter = fighters[side]
            if loser is None and fighter.status == "burn":
                fighter.hp = max(0, fighter.hp - max(1, fighter.max_hp // BURN_DAMAGE_FRACTION))
                events.append(BurnDamage(turn, side, fighter.combatant.name, fighter.hp_percent, fighter.hp == 0))
                if fighter.hp == 0:
                    loser = side
    if loser is None:
        loser = 1 if fighters[0].hp / fighters[0].max_hp >= fighters[1].hp / fighters[1].max_hp else 0
    return BattleResult(winner=1 - loser, turns=turn, events=events)


@dataclass
class _Fighter:
    combatant: Combatant
    max_hp: int
    hp: int
    stats: dict[str, int]
    pp: list[int]
    stages: dict[str, int] = field(default_factory=lambda: dict.fromkeys(BATTLE_STATS, 0))
    status: str | None = None

    @classmethod
    def enter(cls, combatant: Combatant) -> "_Fighter":
        base, ivs, level = combatant.base, combatant.ivs, combatant.level
        max_hp = 1 if base.hp == 1 else (2 * base.hp + ivs.hp) * level // 100 + level + 10
        stats = {key: _other_stat(getattr(base, key), getattr(ivs, key), level) for key in BATTLE_STATS}
        return cls(combatant, max_hp, max_hp, stats, [move.pp for move in combatant.moves])

    @property
    def hp_percent(self) -> int:
        return 0 if self.hp <= 0 else max(1, round(self.hp * 100 / self.max_hp))

    def stat(self, key: str) -> float:
        stage = self.stages[key]
        value = self.stats[key] * ((2 + stage) / 2 if stage >= 0 else 2 / (2 - stage))
        if key == "speed" and self.status == "paralysis":
            value /= 2
        return value


def _turn_order(fighters: tuple[_Fighter, _Fighter], rng: random.Random) -> tuple[int, int]:
    speeds = (fighters[0].stat("speed"), fighters[1].stat("speed"))
    if speeds[0] != speeds[1]:
        return (0, 1) if speeds[0] > speeds[1] else (1, 0)
    return (0, 1) if rng.random() < 0.5 else (1, 0)


def _act(turn: int, side: int, fighters: tuple[_Fighter, _Fighter], rng: random.Random) -> Action:
    attacker, defender = fighters[side], fighters[1 - side]
    names = (attacker.combatant.name, defender.combatant.name)
    if attacker.status == "paralysis" and rng.random() < FULL_PARALYSIS_CHANCE:
        return Action(turn, side, *names, move="", defender_hp=defender.hp_percent)
    index = _best_move(attacker, defender)
    move = STRUGGLE if index is None else attacker.combatant.moves[index]
    if index is not None:
        attacker.pp[index] -= 1
    multiplier = _multiplier(move, defender)
    if move.accuracy is not None and rng.random() * 100 >= move.accuracy:
        return Action(turn, side, *names, move.name, missed=True, multiplier=multiplier, defender_hp=defender.hp_percent)
    if multiplier == 0:
        return Action(turn, side, *names, move.name, multiplier=0, defender_hp=defender.hp_percent)
    critical = rng.random() < CRITICAL_CHANCES[min(move.crit_stage, len(CRITICAL_CHANCES) - 1)]
    defender.hp = max(0, defender.hp - _damage(attacker, defender, move, multiplier, critical, rng))
    changes = () if defender.hp == 0 else _secondary_effects(side, move, attacker, defender, rng)
    recoil = move is STRUGGLE
    if recoil:
        attacker.hp = max(0, attacker.hp - max(1, attacker.max_hp // STRUGGLE_RECOIL_FRACTION))
    return Action(
        turn, side, *names, move.name, multiplier=multiplier, critical=critical, changes=changes, recoil=recoil,
        defender_hp=defender.hp_percent, knockout=defender.hp == 0, attacker_fainted=attacker.hp == 0,
    )


def _damage(attacker: _Fighter, defender: _Fighter, move: Move, multiplier: float, critical: bool,
            rng: random.Random) -> int:
    attack, defense = _stats_for(attacker, defender, move.physical)
    level = attacker.combatant.level
    damage = ((2 * level // 5 + 2) * move.power * attack / max(1, defense)) // 50 + 2
    damage *= _stab(attacker, move) * multiplier * (CRITICAL_MULTIPLIER if critical else 1.0)
    damage *= rng.randint(85, 100) / 100
    return max(1, int(damage))


def _secondary_effects(side: int, move: Move, attacker: _Fighter, defender: _Fighter,
                       rng: random.Random) -> tuple[Change, ...]:
    changes: list[Change] = []
    if (
        move.ailment in AILMENT_IMMUNE_TYPE
        and defender.status is None
        and AILMENT_IMMUNE_TYPE[move.ailment] not in defender.combatant.types
        and rng.random() * 100 < move.ailment_chance
    ):
        defender.status = move.ailment
        changes.append(Change(1 - side, defender.combatant.name, move.ailment))
    if move.stat_changes and rng.random() * 100 < move.stat_chance:
        target, target_side = (attacker, side) if move.stat_on_user else (defender, 1 - side)
        for key, stages in move.stat_changes:
            before = target.stages[key]
            target.stages[key] = max(-MAX_STAGE, min(MAX_STAGE, before + stages))
            if target.stages[key] != before:
                changes.append(Change(target_side, target.combatant.name, key, target.stages[key] - before))
    return tuple(changes)


def _best_move(attacker: _Fighter, defender: _Fighter) -> int | None:
    """Index of the move with PP left and the highest power × STAB × type × accuracy × attack/defense; None means Struggle."""
    best, best_score = None, -1.0
    for index, move in enumerate(attacker.combatant.moves):
        if attacker.pp[index] <= 0:
            continue
        attack, defense = _stats_for(attacker, defender, move.physical)
        accuracy = 100 if move.accuracy is None else move.accuracy
        score = move.power * _stab(attacker, move) * _multiplier(move, defender) * accuracy * attack / max(1, defense)
        if score > best_score:
            best, best_score = index, score
    return best


def _stab(attacker: _Fighter, move: Move) -> float:
    return STAB_MULTIPLIER if move.type in attacker.combatant.types else 1.0


def _multiplier(move: Move, defender: _Fighter) -> float:
    return 1.0 if move.type is None else effectiveness(move.type, defender.combatant.types)


def _stats_for(attacker: _Fighter, defender: _Fighter, physical: bool) -> tuple[float, float]:
    if physical:
        burned = 0.5 if attacker.status == "burn" else 1.0
        return attacker.stat("attack") * burned, defender.stat("defense")
    return attacker.stat("special_attack"), defender.stat("special_defense")


def _other_stat(base: int, iv: int, level: int) -> int:
    return (2 * base + iv) * level // 100 + 5
