"""Automatic battle, entries fought in order: base stats, level, IVs, type effectiveness and level-up moves. No items or switching."""

import random
from dataclasses import dataclass, field

from ypoke.type_chart import TYPE_NAMES_KO, effectiveness

ATTACK_POWER = 80
TYPELESS_POWER = 50
TYPELESS_MOVE_NAME = "몸통박치기"
STAB_MULTIPLIER = 1.5
CRITICAL_CHANCE = 1 / 24
CRITICAL_MULTIPLIER = 1.5
TURN_LIMIT = 2000


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
    type: str
    power: int
    physical: bool
    accuracy: int | None = None


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
class Hit:
    turn: int
    attacker_side: int
    attacker: str
    defender: str
    move: str
    multiplier: float
    critical: bool
    knockout: bool
    missed: bool = False


@dataclass
class BattleResult:
    winner: int
    turns: int
    log: list[str] = field(default_factory=list)
    remaining: tuple[int, int] = (0, 0)
    hits: list[Hit] = field(default_factory=list)


def simulate(sides: tuple[list[Combatant], list[Combatant]], seed: int) -> BattleResult:
    """Fight both entries in order until one side has no Pokémon left.

    A Pokémon with moves uses the one with the highest expected damage each turn;
    one without moves attacks with its best type.
    """
    rng = random.Random(seed)
    fighters = (
        [_Fighter.enter(combatant) for combatant in sides[0]],
        [_Fighter.enter(combatant) for combatant in sides[1]],
    )
    active = [0, 0]
    log: list[str] = []
    hits: list[Hit] = []
    turn = 0
    while active[0] < len(fighters[0]) and active[1] < len(fighters[1]) and turn < TURN_LIMIT:
        turn += 1
        current = (fighters[0][active[0]], fighters[1][active[1]])
        for attacker_side in _turn_order(current, rng):
            attacker = current[attacker_side]
            defender = current[1 - attacker_side]
            if attacker.hp <= 0 or defender.hp <= 0:
                continue
            hit = _attack(attacker, defender, rng)
            hits.append(Hit(
                turn, attacker_side, attacker.combatant.name, defender.combatant.name,
                hit.move, hit.multiplier, hit.critical, defender.hp <= 0, hit.missed,
            ))
            if defender.hp <= 0:
                log.append(_knockout_line(turn, attacker_side, attacker, defender, hit))
        for side in (0, 1):
            if current[side].hp <= 0:
                active[side] += 1
    remaining = (len(fighters[0]) - active[0], len(fighters[1]) - active[1])
    return BattleResult(
        winner=_decide_winner(fighters, active, remaining),
        turns=turn,
        log=log,
        remaining=remaining,
        hits=hits,
    )


@dataclass
class _Fighter:
    combatant: Combatant
    max_hp: int
    hp: int
    attack: int
    defense: int
    special_attack: int
    special_defense: int
    speed: int

    @classmethod
    def enter(cls, combatant: Combatant) -> "_Fighter":
        base, ivs, level = combatant.base, combatant.ivs, combatant.level
        max_hp = 1 if base.hp == 1 else (2 * base.hp + ivs.hp) * level // 100 + level + 10
        return cls(
            combatant=combatant,
            max_hp=max_hp,
            hp=max_hp,
            attack=_other_stat(base.attack, ivs.attack, level),
            defense=_other_stat(base.defense, ivs.defense, level),
            special_attack=_other_stat(base.special_attack, ivs.special_attack, level),
            special_defense=_other_stat(base.special_defense, ivs.special_defense, level),
            speed=_other_stat(base.speed, ivs.speed, level),
        )


@dataclass(frozen=True)
class _Hit:
    move: str
    multiplier: float
    critical: bool
    missed: bool = False


def _turn_order(current: tuple[_Fighter, _Fighter], rng: random.Random) -> tuple[int, int]:
    if current[0].speed != current[1].speed:
        return (0, 1) if current[0].speed > current[1].speed else (1, 0)
    return (0, 1) if rng.random() < 0.5 else (1, 0)


def _attack(attacker: _Fighter, defender: _Fighter, rng: random.Random) -> _Hit:
    move = _best_move(attacker, defender)
    if move is None:
        return _type_attack(attacker, defender, rng)
    if move.accuracy is not None and rng.random() * 100 >= move.accuracy:
        return _Hit(move=move.name, multiplier=_multiplier(move, defender), critical=False, missed=True)
    multiplier = _multiplier(move, defender)
    stab = STAB_MULTIPLIER if move.type in attacker.combatant.types else 1.0
    attack_stat, defense_stat = _stats_for(attacker, defender, move.physical)
    critical = _deal_damage(attacker, defender, rng, move.power, attack_stat, defense_stat, stab * multiplier)
    return _Hit(move=move.name, multiplier=multiplier, critical=critical)


def _type_attack(attacker: _Fighter, defender: _Fighter, rng: random.Random) -> _Hit:
    attack_type, multiplier = _best_attack_type(attacker, defender)
    if attack_type is None:
        power, stab = TYPELESS_POWER, 1.0
    else:
        power, stab = ATTACK_POWER, STAB_MULTIPLIER
    attack_stat, defense_stat = _stats_for(attacker, defender, attacker.attack >= attacker.special_attack)
    critical = _deal_damage(attacker, defender, rng, power, attack_stat, defense_stat, stab * multiplier)
    name = TYPELESS_MOVE_NAME if attack_type is None else f"{TYPE_NAMES_KO[attack_type]} 공격"
    return _Hit(move=name, multiplier=multiplier, critical=critical)


def _deal_damage(
    attacker: _Fighter, defender: _Fighter, rng: random.Random,
    power: int, attack_stat: int, defense_stat: int, modifier: float,
) -> bool:
    level = attacker.combatant.level
    damage = ((2 * level // 5 + 2) * power * attack_stat // max(1, defense_stat)) // 50 + 2
    critical = rng.random() < CRITICAL_CHANCE
    scaled = damage * modifier * (CRITICAL_MULTIPLIER if critical else 1.0)
    scaled *= rng.randint(85, 100) / 100
    defender.hp -= max(1, int(scaled))
    return critical


def _best_move(attacker: _Fighter, defender: _Fighter) -> Move | None:
    """Highest power × STAB × type × accuracy × attack/defense ratio; None if every move does nothing."""
    best, best_score = None, 0.0
    for move in attacker.combatant.moves:
        stab = STAB_MULTIPLIER if move.type in attacker.combatant.types else 1.0
        attack_stat, defense_stat = _stats_for(attacker, defender, move.physical)
        accuracy = 100 if move.accuracy is None else move.accuracy
        score = move.power * stab * _multiplier(move, defender) * accuracy / 100 * attack_stat / max(1, defense_stat)
        if score > best_score:
            best, best_score = move, score
    return best


def _multiplier(move: Move, defender: _Fighter) -> float:
    return effectiveness(move.type, defender.combatant.types)


def _stats_for(attacker: _Fighter, defender: _Fighter, physical: bool) -> tuple[int, int]:
    if physical:
        return attacker.attack, defender.defense
    return attacker.special_attack, defender.special_defense


def _knockout_line(turn: int, attacker_side: int, attacker: _Fighter, defender: _Fighter, hit: _Hit) -> str:
    notes = []
    if hit.critical:
        notes.append("급소!")
    if hit.multiplier > 1:
        notes.append("효과가 굉장했다!")
    elif 0 < hit.multiplier < 1:
        notes.append("효과가 별로인 듯하다…")
    suffix = f" ({' '.join(notes)})" if notes else ""
    marker = "🔵" if attacker_side == 0 else "🔴"
    return f"{turn}턴 {marker} {attacker.combatant.label}의 {hit.move}{suffix} → {defender.combatant.label} 쓰러짐"


def _decide_winner(fighters: tuple[list[_Fighter], list[_Fighter]], active: list[int], remaining: tuple[int, int]) -> int:
    if remaining[0] != remaining[1]:
        return 0 if remaining[0] > remaining[1] else 1
    hp_share = [sum(f.hp / f.max_hp for f in fighters[side][active[side]:]) for side in (0, 1)]
    return 0 if hp_share[0] >= hp_share[1] else 1


def _other_stat(base: int, iv: int, level: int) -> int:
    return (2 * base + iv) * level // 100 + 5


def _best_attack_type(attacker: _Fighter, defender: _Fighter) -> tuple[str | None, float]:
    best_type, best_multiplier = None, 0.0
    for attack_type in attacker.combatant.types:
        multiplier = effectiveness(attack_type, defender.combatant.types)
        if multiplier > best_multiplier:
            best_type, best_multiplier = attack_type, multiplier
    if best_type is None:
        return None, 1.0
    return best_type, best_multiplier
