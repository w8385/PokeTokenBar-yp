"""Automatic battle, parties fought in order: base stats, level, IVs and type effectiveness. No moves or items."""

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
class Combatant:
    name: str
    level: int
    types: tuple[str, ...]
    base: BaseStats
    ivs: BaseStats
    shiny: bool = False

    @property
    def label(self) -> str:
        return f"{self.name}{'✨' if self.shiny else ''} Lv{self.level}"


@dataclass(frozen=True)
class Hit:
    turn: int
    attacker_side: int
    move: str
    multiplier: float
    critical: bool
    knockout: bool


@dataclass
class BattleResult:
    winner: int
    turns: int
    log: list[str] = field(default_factory=list)
    remaining: tuple[int, int] = (0, 0)
    hits: list[Hit] = field(default_factory=list)


def simulate(sides: tuple[list[Combatant], list[Combatant]], seed: int) -> BattleResult:
    """Fight both parties in order until one side has no Pokémon left.

    Args:
        sides: Two non-empty parties in battle order. Index 0 is the challenger.
        seed: RNG seed, so a stored battle can be replayed.

    Returns:
        Winner index (0 or 1), turn count, KO log and survivors per side.
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
            hits.append(Hit(turn, attacker_side, _move_name(hit), hit.multiplier, hit.critical, defender.hp <= 0))
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
    attack_type: str | None
    multiplier: float
    critical: bool


def _turn_order(current: tuple[_Fighter, _Fighter], rng: random.Random) -> tuple[int, int]:
    if current[0].speed != current[1].speed:
        return (0, 1) if current[0].speed > current[1].speed else (1, 0)
    return (0, 1) if rng.random() < 0.5 else (1, 0)


def _attack(attacker: _Fighter, defender: _Fighter, rng: random.Random) -> _Hit:
    attack_type, multiplier = _best_attack_type(attacker, defender)
    if attack_type is None:
        power, stab = TYPELESS_POWER, 1.0
    else:
        power, stab = ATTACK_POWER, STAB_MULTIPLIER
    if attacker.attack >= attacker.special_attack:
        attack_stat, defense_stat = attacker.attack, defender.defense
    else:
        attack_stat, defense_stat = attacker.special_attack, defender.special_defense
    level = attacker.combatant.level
    damage = ((2 * level // 5 + 2) * power * attack_stat // max(1, defense_stat)) // 50 + 2
    critical = rng.random() < CRITICAL_CHANCE
    scaled = damage * stab * multiplier * (CRITICAL_MULTIPLIER if critical else 1.0)
    scaled *= rng.randint(85, 100) / 100
    defender.hp -= max(1, int(scaled))
    return _Hit(attack_type=attack_type, multiplier=multiplier, critical=critical)


def _move_name(hit: _Hit) -> str:
    return TYPELESS_MOVE_NAME if hit.attack_type is None else f"{TYPE_NAMES_KO[hit.attack_type]} 공격"


def _knockout_line(turn: int, attacker_side: int, attacker: _Fighter, defender: _Fighter, hit: _Hit) -> str:
    move = _move_name(hit)
    notes = []
    if hit.critical:
        notes.append("급소!")
    if hit.multiplier > 1:
        notes.append("효과가 굉장했다!")
    elif 0 < hit.multiplier < 1:
        notes.append("효과가 별로인 듯하다…")
    suffix = f" ({' '.join(notes)})" if notes else ""
    marker = "🔵" if attacker_side == 0 else "🔴"
    return f"{turn}턴 {marker} {attacker.combatant.label}의 {move}{suffix} → {defender.combatant.label} 쓰러짐"


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
