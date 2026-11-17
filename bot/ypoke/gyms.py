"""The PvE trainers of nine regions: eight gym leaders, the Elite Four and a champion, and a villain organization.

Everything here is pure data. A team comes from the committed species table (`species.json`, made by
`tools/generate_species.py`) and a seed made of the region and the trainer; its moves and items come from
`foe_moves.json` (`tools/generate_foe_moves.py`). So `GET /v1/gyms` shows the team the battle will use without asking
PokéAPI. A gym leader fields only its type, 3 to 6 by gym number; the champion's team is the fixed table in
`gym_data.CHAMPION_TEAMS`. Everyone fights at Lv50. Contract: bot/API.md.
"""

import json
import random
from dataclasses import dataclass, replace
from functools import cache
from pathlib import Path

from ypoke import foe_items, foe_moves
from ypoke.battle import BATTLE_LEVEL
from ypoke.dex import REGIONS as DEX_REGIONS
from ypoke.gym_data import (
    CHAMPION_TEAMS, CHAMPIONS, ELITE, ELITE_TYPES, GYM_TYPES, LEADERS, ORG_TYPES, ORGS, Ace,
)
from ypoke.pokeapi import WEATHER_MOVES
from ypoke.upload_server import IV_KEYS

TEAM_SIZE = 6
GYM_SIZES = (3, 3, 4, 4, 5, 5, 6, 6)
CHAMPION_MAIN = 6
LEARN_LEVEL = 100
MIN_TOTAL = 300
LANGUAGES = ("ko", "en", "ja")
SPECIES_TABLE = Path(__file__).with_name("species.json")
# (base-stat total the species are picked around, IVs of every stat): per gym number, then per other kind. Absolute,
# not ranked within a region, so every region climbs the same curve. The Elite Four and the champion stand above gym 8.
GYM_STRENGTH = ((420, 12), (435, 14), (450, 16), (465, 17), (480, 18), (495, 19), (495, 18), (520, 21))
STRENGTH = {"elite": (555, 28), "champion": (600, 31), "grunt": (430, 12), "admin": (480, 20), "boss": (530, 26)}
# How far from the target a pick may stray at random, in base-stat total.
SPREAD = 30
# How many of a team's six are of the trainer's focus types: `MIN_FOCUS` always (fewer where the region has fewer
# such species), up to `FOCUS` while they are within `WINDOW` of the target total.
FOCUS = {"elite": 6, "grunt": 3, "admin": 4, "boss": 5}
MIN_FOCUS = 3
WINDOW = 40
# Ultra Beasts and Paradox Pokémon: PokéAPI flags them neither legendary nor mythical.
QUASI_LEGENDARY = frozenset((*range(793, 800), *range(803, 807), *range(984, 996), 1005, 1006, 1009, 1010,
                             *range(1020, 1024)))
ORG_ROLES = ("grunt", "grunt", "admin", "boss")
ORG_MEMBER_WORD = ("단원", "Grunt", "の下っ端")


@dataclass(frozen=True)
class Trainer:
    name: dict[str, str]
    line: dict[str, str]


@dataclass(frozen=True)
class Opponent:
    """`kind` is gym, elite, champion, grunt, admin or boss. `types` is the team's focus (empty for the champion).
    `run`, `step` and `steps` place the battle in a run of consecutive battles (None for a gym). `moves` and `items`
    are per member of `team`, and so are a champion's `aces` (form, ability, nature); the last `finale` members only
    come out after the others faint and stay hidden in the preview."""

    id: str
    region: str
    kind: str
    index: int
    types: tuple[str, ...]
    trainer: Trainer
    team: tuple[int, ...]
    run: str | None = None
    step: int = 0
    steps: int = 0
    moves: tuple[tuple[int, ...], ...] = ()
    items: tuple[str, ...] = ()
    finale: int = 0
    aces: tuple[Ace, ...] = ()

    @property
    def shown(self) -> tuple[int, ...]:
        return self.team[:len(self.team) - self.finale]

    @property
    def level(self) -> int:
        return BATTLE_LEVEL

    @property
    def iv(self) -> int:
        return _strength(self.kind, self.index)[1]


@dataclass(frozen=True)
class Org:
    name: dict[str, str]
    types: tuple[str, ...]


@dataclass(frozen=True)
class Region:
    id: str
    name: str
    first: int
    last: int
    gyms: tuple[Opponent, ...]
    elite: tuple[Opponent, ...]
    org: Org
    hideout: tuple[Opponent, ...]

    @property
    def elite_run(self) -> str:
        return f"{self.id}-elite"

    @property
    def hideout_run(self) -> str:
        return f"{self.id}-hideout"


@dataclass(frozen=True)
class Species:
    id: int
    types: tuple[str, ...]
    parent: int
    level: int
    excluded: bool
    total: int
    reach: int


def catalog() -> dict:
    """The body of `GET /v1/gyms` (without `ok`)."""
    return {"regions": [_region_json(region) for region in regions()]}


def find(battle_id: str) -> Opponent | None:
    return _by_id().get(battle_id)


def next_in_run(opponent: Opponent) -> str | None:
    """The id of the battle after `opponent` in its run; None at the end of a run and for a gym."""
    if opponent.run is None or opponent.step == opponent.steps:
        return None
    return run_of(opponent)[opponent.step].id


def run_of(opponent: Opponent) -> tuple[Opponent, ...]:
    """Every battle of the run `opponent` belongs to, in order."""
    region = _region(opponent.region)
    return region.elite if opponent.run == region.elite_run else region.hideout


def foe_members(opponent: Opponent) -> list[dict]:
    """The team as party members the battle can build, with their moves and items. `learned_at` lets a foe use
    moves its species learns above the battle level."""
    ivs = dict.fromkeys(IV_KEYS, opponent.iv)
    aces = opponent.aces or (None,) * len(opponent.team)
    return [
        {"pokemon_id": pokemon_id, "level": opponent.level, "learned_at": LEARN_LEVEL, "shiny": False, "ivs": ivs,
         "moves": list(moves), "held_item": item, "can_evolve": can_evolve(pokemon_id), **_ace_fields(ace)}
        for pokemon_id, moves, item, ace in zip(opponent.team, opponent.moves, opponent.items, aces, strict=True)
    ]


def _ace_fields(ace: Ace | None) -> dict:
    """A champion member's form, as the `pokemon_id` the battle builds, its ability and its nature."""
    if ace is None:
        return {}
    return {"pokemon_id": ace.form or ace.species, "ability": ace.ability, "nature": ace.nature}


@cache
def regions() -> tuple[Region, ...]:
    table = species_table()
    built = []
    first = 1
    for region_id, (name, count) in DEX_REGIONS.items():
        last = first + count - 1
        built.append(_build_region(region_id, name, first, last, table))
        first = last + 1
    return tuple(built)


@cache
def species_table() -> dict[int, Species]:
    rows = json.loads(SPECIES_TABLE.read_text())
    return {
        row[0]: Species(row[0], tuple(kind for kind in row[1:3] if kind), row[3], row[4], bool(row[5]), row[6], row[7])
        for row in rows
    }


def _build_region(region_id: str, name: str, first: int, last: int, table: dict[int, Species]) -> Region:
    pool = usable_species(table, first, last)
    gym_pool = usable_species(table, first, last, final_only=False)
    gyms = [
        _gym(region_id, index, kind, _trainer(LEADERS[region_id][index - 1]), gym_pool, table)
        for index, kind in enumerate(GYM_TYPES[region_id], 1)
    ]
    elite_run, steps = f"{region_id}-elite", len(ELITE_TYPES[region_id]) + 1
    elite: list[Opponent] = []
    for index, kind in enumerate(ELITE_TYPES[region_id], 1):
        fielded = {ace.species for ace in CHAMPION_TEAMS[region_id]} | {s for member in elite for s in member.team}
        elite.append(_themed(region_id, f"{region_id}-elite-{index}", "elite", index, (kind,),
                             _trainer(ELITE[region_id][index - 1]), pool, elite_run, steps, fielded, gym_pool))
    elite.append(_champion(region_id, steps, _trainer(CHAMPIONS[region_id]), elite_run))
    org_row, admin, boss = ORGS[region_id]
    org = Org(_languages(org_row[:3]), ORG_TYPES[region_id])
    members = (_grunt(org_row), _grunt(org_row), _trainer(admin), _trainer(boss))
    hideout: list[Opponent] = []
    for index, (role, trainer) in enumerate(zip(ORG_ROLES, members), 1):
        fielded = {species_id for member in hideout for species_id in member.team}
        hideout.append(_themed(region_id, f"{region_id}-hideout-{index}", role, index, org.types, trainer, pool,
                               f"{region_id}-hideout", len(members), fielded))
    return Region(region_id, name, first, last, tuple(gyms), tuple(elite), org, tuple(hideout))


def usable_species(table: dict[int, Species], first: int, last: int, final_only: bool = True) -> list[Species]:
    """Species of the dex range `first..last` a Lv50 trainer may field, by id: not baby, legendary, mythical, Ultra
    Beast or Paradox, reachable and armed by Lv50, of at least `MIN_TOTAL` base stats, and with `final_only` not yet
    evolved into a form it could already be."""
    evolving = (
        {species.parent for species in table.values() if species.parent and species.reach <= BATTLE_LEVEL}
        if final_only else set()
    )
    return [
        species for species in table.values()
        if first <= species.id <= last and not species.excluded and species.id not in QUASI_LEGENDARY
        and species.level <= BATTLE_LEVEL and species.total >= MIN_TOTAL and species.id not in evolving
    ]


def _themed(region_id: str, battle_id: str, kind: str, index: int, types: tuple[str, ...], trainer: Trainer,
            pool: list[Species], run: str | None = None, steps: int = 0,
            fielded: set[int] = frozenset(), unevolved: list[Species] = ()) -> Opponent:
    """Up to `FOCUS[kind]` species of the focus types, the best-ranked ones by the seed, topped up to `MIN_FOCUS`
    from `unevolved` where the region has too few final forms of them; the rest of the team comes from the region's
    other species, ones earlier trainers of the run did not field. The strongest member goes last."""
    rng = random.Random(battle_id)
    target = _strength(kind, index)[0]
    matching = _ranked(rng, [species for species in pool if set(types) & set(species.types)], target)
    chosen = matching[:min(FOCUS[kind], MIN_FOCUS)]
    near = [species for species in matching[len(chosen):] if abs(species.total - target) <= WINDOW]
    chosen += near[:FOCUS[kind] - len(chosen)]
    for species in _ranked(rng, [species for species in unevolved if set(types) & set(species.types)], target):
        if len(chosen) < MIN_FOCUS and not any(
                species.id == other.id or _related(species.id, other.id, species_table()) for other in chosen):
            chosen.append(species)
    taken = {species.id for species in chosen} | set(fielded)
    rest = [species for species in pool if species.id not in taken]
    chosen += _ranked(rng, rest, target)[:TEAM_SIZE - len(chosen)]
    return _armed(Opponent(battle_id, region_id, kind, index, types, trainer, _lineup(chosen), run,
                           index if run else 0, steps))


def _gym(region_id: str, index: int, kind: str, trainer: Trainer, pool: list[Species],
         table: dict[int, Species]) -> Opponent:
    """`GYM_SIZES[index - 1]` species of the leader's type nearest the gym's target total, by the seed. No member
    evolves from another unless the region has too few of the type for that."""
    battle_id = f"{region_id}-{index}"
    rng = random.Random(battle_id)
    size = GYM_SIZES[index - 1]
    ranked = _ranked(rng, [species for species in pool if kind in species.types], _strength("gym", index)[0])
    chosen: list[Species] = []
    for species in ranked:
        if len(chosen) < size and not any(_related(species.id, other.id, table) for other in chosen):
            chosen.append(species)
    chosen += [species for species in ranked if species not in chosen][:size - len(chosen)]
    return _armed(Opponent(battle_id, region_id, "gym", index, (kind,), trainer, _lineup(chosen)))


def _champion(region_id: str, index: int, trainer: Trainer, run: str) -> Opponent:
    """The champion (last of the run, `index` is also the run's length) fields the fixed table, finale last."""
    entries = CHAMPION_TEAMS[region_id]
    return Opponent(
        f"{region_id}-champion", region_id, "champion", index, (), trainer, tuple(ace.species for ace in entries), run,
        index, index, tuple(ace.moves for ace in entries), tuple(ace.item for ace in entries),
        len(entries) - CHAMPION_MAIN, entries,
    )


def _armed(opponent: Opponent) -> Opponent:
    """`opponent` with each member's picked moves and an item for each."""
    moves = tuple(foe_moves.species(species_id).picked for species_id in opponent.team)
    held = foe_items.assign([holder(species_id, picked) for species_id, picked in zip(opponent.team, moves)])
    return replace(opponent, moves=moves, items=tuple(held))


def holder(species_id: int, move_ids: tuple[int, ...]) -> foe_items.Holder:
    """Status and weather moves are not in `foe_moves`; a weather move still lets a weather rock fire."""
    data = foe_moves.species(species_id)
    moves = tuple(move for move in map(foe_moves.move, move_ids) if move is not None)
    weathers = tuple(WEATHER_MOVES[move_id] for move_id in move_ids if move_id in WEATHER_MOVES)
    return foe_items.Holder(species_id, data.types, data.stats, moves, can_evolve(species_id), weathers)


def can_evolve(species_id: int) -> bool:
    return species_id in _parents()


@cache
def _parents() -> frozenset[int]:
    return frozenset(species.parent for species in species_table().values() if species.parent)


def _related(first: int, second: int, table: dict[int, Species]) -> bool:
    return second in _ancestors(first, table) or first in _ancestors(second, table)


def _ancestors(species_id: int, table: dict[int, Species]) -> set[int]:
    found = set()
    while table[species_id].parent:
        species_id = table[species_id].parent
        found.add(species_id)
    return found


def _strength(kind: str, index: int) -> tuple[int, int]:
    return GYM_STRENGTH[index - 1] if kind == "gym" else STRENGTH[kind]


def _ranked(rng: random.Random, candidates: list[Species], target: int) -> list[Species]:
    """`candidates` nearest base-stat total `target` first, each pushed back by up to `SPREAD` at random."""
    ordered = sorted(candidates, key=lambda species: (species.total, species.id))
    scores = {species.id: abs(species.total - target) + SPREAD * rng.random() for species in ordered}
    return sorted(ordered, key=lambda species: scores[species.id])


def _lineup(chosen: list[Species]) -> tuple[int, ...]:
    return tuple(species.id for species in sorted(chosen, key=lambda species: (species.total, species.id)))


def _grunt(org_row: tuple[str, ...]) -> Trainer:
    """A grunt is named after the organization and says its line."""
    names = (f"{org_row[0]} {ORG_MEMBER_WORD[0]}", f"{org_row[1].removeprefix('The ')} {ORG_MEMBER_WORD[1]}",
             f"{org_row[2]}{ORG_MEMBER_WORD[2]}")
    return Trainer(_languages(names), _languages(org_row[3:]))


def _trainer(row: tuple[str, ...]) -> Trainer:
    """`row` is the name in `LANGUAGES` order, then the line in the same order."""
    return Trainer(_languages(row[:3]), _languages(row[3:]))


def _languages(values: tuple[str, ...]) -> dict[str, str]:
    return dict(zip(LANGUAGES, values))


@cache
def _by_id() -> dict[str, Opponent]:
    return {
        opponent.id: opponent for region in regions() for opponent in (*region.gyms, *region.elite, *region.hideout)
    }


def _region(region_id: str) -> Region:
    return next(region for region in regions() if region.id == region_id)


def _region_json(region: Region) -> dict:
    return {
        "id": region.id,
        "name": region.name,
        "first": region.first,
        "last": region.last,
        "gyms": [_opponent_json(opponent) for opponent in region.gyms],
        "elite": {
            "run": region.elite_run, "badges_needed": len(region.gyms),
            "battles": [_opponent_json(opponent) for opponent in region.elite],
        },
        "hideout": {
            "run": region.hideout_run, "org": {"name": region.org.name, "types": list(region.org.types)},
            "battles": [_opponent_json(opponent) for opponent in region.hideout],
        },
    }


def _opponent_json(opponent: Opponent) -> dict:
    return {
        "id": opponent.id,
        "kind": opponent.kind,
        "index": opponent.index,
        "types": list(opponent.types),
        "level": opponent.level,
        "trainer": {"name": opponent.trainer.name, "line": opponent.trainer.line},
        "team": list(opponent.shown),
        "finale": opponent.finale,
        "run": {"id": opponent.run, "step": opponent.step, "steps": opponent.steps} if opponent.run else None,
    }
