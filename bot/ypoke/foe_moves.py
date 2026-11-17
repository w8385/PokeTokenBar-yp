"""The four moves a PvE foe brings, picked from everything its species learns.

`pick` is pure. `tools/generate_foe_moves.py` runs it over every species and commits the result to `foe_moves.json`
with each species' base stats and learnable attacking moves, so a team, its moves and its items are known without
asking PokéAPI.
"""

import json
from dataclasses import dataclass
from functools import cache
from pathlib import Path

from ypoke.battle import MULTI_HIT_ODDS, STAB_MULTIPLIER
from ypoke.moves import MAX_MOVES
from ypoke.type_chart import TYPE_NAMES_KO, effectiveness

FOE_TABLE = Path(__file__).with_name("foe_moves.json")
# The simulation gives these their power with none of their cost or condition, so a foe takes one only when it has
# fewer than four other attacking moves.
RECHARGE = frozenset({63, 307, 308, 338, 416, 439, 459, 711, 794, 795})
CHARGE_TURN = frozenset({13, 19, 76, 91, 130, 143, 291, 340, 467, 507, 553, 554, 566, 669, 800, 905})
SELF_FAINT = frozenset({120, 153, 720, 796, 802})
CONDITIONAL = frozenset({
    138, 173, 248, 252, 264, 284, 323, 353, 387, 389, 485, 562, 660, 682, 704, 798, 809, 892, 893, 901, 909, 918,
})
LAST_RESORT = RECHARGE | CHARGE_TURN | SELF_FAINT | CONDITIONAL
ATTACKING_TYPES = tuple(TYPE_NAMES_KO)


@dataclass(frozen=True)
class FoeMove:
    id: int
    type: str
    physical: bool
    power: int
    accuracy: int | None
    hits: float


@dataclass(frozen=True)
class FoeSpecies:
    id: int
    types: tuple[str, ...]
    stats: dict[str, int]
    picked: tuple[int, ...]
    learnable: frozenset[int]


def pick(moves: list[FoeMove], types: tuple[str, ...], attack: int, special_attack: int) -> list[int]:
    """Move ids, best first: the strongest move of each own type, then the moves that add the most damage across the
    18 types. A move is scored by power × accuracy × hits on the attack stat of its class, × STAB."""
    reliable = [move for move in moves if move.id not in LAST_RESORT]
    chosen = _pick_from(reliable, types, attack, special_attack)
    if len(chosen) < MAX_MOVES:
        spare = [move for move in moves if move.id in LAST_RESORT]
        chosen += _pick_from(spare, types, attack, special_attack, chosen)[:MAX_MOVES - len(chosen)]
    return [move.id for move in chosen]


def species(species_id: int) -> FoeSpecies | None:
    return _table()[0].get(species_id)


def move(move_id: int) -> FoeMove | None:
    return _table()[1].get(move_id)


def _pick_from(moves: list[FoeMove], types: tuple[str, ...], attack: int, special_attack: int,
               taken: list[FoeMove] = ()) -> list[FoeMove]:
    def score(move: FoeMove) -> float:
        stat = attack if move.physical else special_attack
        stab = STAB_MULTIPLIER if move.type in types else 1.0
        return move.power * (move.accuracy or 100) / 100 * move.hits * stat * stab

    ranked = sorted(moves, key=lambda move: (-score(move), move.id))
    chosen: list[FoeMove] = list(taken)
    for own in types:
        best = next((move for move in ranked if move.type == own and move not in chosen), None)
        if best is not None and len(chosen) < MAX_MOVES:
            chosen.append(best)

    def reach(picked: list[FoeMove]) -> float:
        return sum(
            max((score(move) * effectiveness(move.type, (defender,)) for move in picked), default=0.0)
            for defender in ATTACKING_TYPES
        )

    while len(chosen) < MAX_MOVES:
        left = [move for move in ranked if move not in chosen and move.type not in {other.type for other in chosen}]
        if not left:
            left = [move for move in ranked if move not in chosen]
        if not left:
            break
        now = reach(chosen)
        chosen.append(max(left, key=lambda move: (reach([*chosen, move]) - now, score(move), -move.id)))
    return chosen[len(taken):]


def expected_hits(min_hits: int, max_hits: int) -> float:
    if (min_hits, max_hits) == (2, 5):
        return sum(hits * odds for hits, odds in MULTI_HIT_ODDS.items()) / 100
    return (min_hits + max_hits) / 2


@cache
def _table() -> tuple[dict[int, FoeSpecies], dict[int, FoeMove]]:
    data = json.loads(FOE_TABLE.read_text())
    moves = {
        int(move_id): FoeMove(int(move_id), row[0], row[1] == "physical", row[2], row[3], row[4])
        for move_id, row in data["moves"].items()
    }
    keys = ("hp", "attack", "defense", "special_attack", "special_defense", "speed")
    species_rows = {
        row[0]: FoeSpecies(row[0], tuple(row[1]), dict(zip(keys, row[2])), tuple(row[3]), frozenset(row[4]))
        for row in data["species"]
    }
    return species_rows, moves
