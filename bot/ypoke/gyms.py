"""The PvE trainers of nine regions: eight gym leaders, the Elite Four and a champion, and a villain organization.

Everything here is pure data. A team comes from the committed species table (`species.json`, made by
`tools/generate_species.py`) and a seed made of the region and the trainer, so `GET /v1/gyms` shows the team the
battle will use without asking PokéAPI. Every trainer fields six Pokémon at Lv50. Contract: bot/API.md.
"""

import json
import random
from dataclasses import dataclass
from functools import cache
from pathlib import Path

from ypoke.battle import BATTLE_LEVEL
from ypoke.dex import REGIONS as DEX_REGIONS
from ypoke.gym_data import CHAMPIONS, ELITE, ELITE_TYPES, GYM_TYPES, LEADERS, ORG_TYPES, ORGS
from ypoke.upload_server import IV_KEYS

TEAM_SIZE = 6
MIN_TOTAL = 300
LANGUAGES = ("ko", "en", "ja")
SPECIES_TABLE = Path(__file__).with_name("species.json")
# (base-stat total the species are picked around, IVs of every stat): per gym number, then per other kind. Absolute,
# not ranked within a region, so every region climbs the same curve. The Elite Four and the champion stand above gym 8.
GYM_STRENGTH = ((420, 12), (435, 14), (450, 16), (470, 18), (490, 19), (505, 20), (525, 21), (545, 26))
STRENGTH = {"elite": (555, 28), "champion": (600, 31), "grunt": (430, 12), "admin": (480, 20), "boss": (530, 26)}
# How far from the target a pick may stray at random, in base-stat total.
SPREAD = 30
# How many of a team's six are of the trainer's focus types: `MIN_FOCUS` always (fewer where the region has fewer
# such species), up to `FOCUS` while they are within `WINDOW` of the target total.
FOCUS = {"gym": 6, "elite": 6, "grunt": 3, "admin": 4, "boss": 5}
MIN_FOCUS = 3
WINDOW = 40
ORG_ROLES = ("grunt", "grunt", "admin", "boss")
ORG_MEMBER_WORD = ("단원", "Grunt", "の下っ端")


@dataclass(frozen=True)
class Trainer:
    name: dict[str, str]
    line: dict[str, str]


@dataclass(frozen=True)
class Opponent:
    """`kind` is gym, elite, champion, grunt, admin or boss. `types` is the team's focus (empty for the champion).
    `run`, `step` and `steps` place the battle in a run of consecutive battles (None for a gym)."""

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
    """The team as party members the battle can build (no moves chosen: the latest attacking moves)."""
    ivs = dict.fromkeys(IV_KEYS, opponent.iv)
    return [{"pokemon_id": pokemon_id, "level": opponent.level, "shiny": False, "ivs": ivs} for pokemon_id in opponent.team]


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
        _themed(region_id, f"{region_id}-{index}", "gym", index, (kind,), _trainer(LEADERS[region_id][index - 1]),
                gym_pool)
        for index, kind in enumerate(GYM_TYPES[region_id], 1)
    ]
    elite_run, steps = f"{region_id}-elite", len(ELITE_TYPES[region_id]) + 1
    elite = [
        _themed(region_id, f"{region_id}-elite-{index}", "elite", index, (kind,), _trainer(ELITE[region_id][index - 1]),
                pool, elite_run, steps)
        for index, kind in enumerate(ELITE_TYPES[region_id], 1)
    ]
    elite.append(_mixed(region_id, f"{region_id}-champion", steps, _trainer(CHAMPIONS[region_id]), pool, elite_run))
    org_row, admin, boss = ORGS[region_id]
    org = Org(_languages(org_row[:3]), ORG_TYPES[region_id])
    members = (_grunt(org_row), _grunt(org_row), _trainer(admin), _trainer(boss))
    hideout = [
        _themed(region_id, f"{region_id}-hideout-{index}", role, index, org.types, trainer, pool,
                f"{region_id}-hideout", len(members))
        for index, (role, trainer) in enumerate(zip(ORG_ROLES, members), 1)
    ]
    return Region(region_id, name, first, last, tuple(gyms), tuple(elite), org, tuple(hideout))


def usable_species(table: dict[int, Species], first: int, last: int, final_only: bool = True) -> list[Species]:
    """Species of the dex range `first..last` a Lv50 trainer may field, by id: not baby, legendary or mythical,
    reachable and armed by Lv50, of at least `MIN_TOTAL` base stats, and with `final_only` not yet evolved into a
    form it could already be."""
    evolving = (
        {species.parent for species in table.values() if species.parent and species.reach <= BATTLE_LEVEL}
        if final_only else set()
    )
    return [
        species for species in table.values()
        if first <= species.id <= last and not species.excluded and species.level <= BATTLE_LEVEL
        and species.total >= MIN_TOTAL and species.id not in evolving
    ]


def _themed(region_id: str, battle_id: str, kind: str, index: int, types: tuple[str, ...], trainer: Trainer,
            pool: list[Species], run: str | None = None, steps: int = 0) -> Opponent:
    """Up to `FOCUS[kind]` species of the focus types, the best-ranked ones by the seed; the rest of the team comes
    from the region's other species. The strongest member goes last."""
    rng = random.Random(battle_id)
    target = _strength(kind, index)[0]
    matching = _ranked(rng, [species for species in pool if set(types) & set(species.types)], target)
    chosen = matching[:min(FOCUS[kind], MIN_FOCUS)]
    near = [species for species in matching[len(chosen):] if abs(species.total - target) <= WINDOW]
    chosen += near[:FOCUS[kind] - len(chosen)]
    taken = {species.id for species in chosen}
    rest = [species for species in pool if species.id not in taken]
    chosen += _ranked(rng, rest, target)[:TEAM_SIZE - len(chosen)]
    return Opponent(battle_id, region_id, kind, index, types, trainer, _lineup(chosen), run, index if run else 0, steps)


def _mixed(region_id: str, battle_id: str, index: int, trainer: Trainer, pool: list[Species], run: str) -> Opponent:
    """The champion (last of the run, `index` is also the run's length) has no focus: the region's species nearest
    its target, no two sharing a first type."""
    rng = random.Random(battle_id)
    chosen: list[Species] = []
    for species in _ranked(rng, pool, STRENGTH["champion"][0]):
        if all(species.types[0] != other.types[0] for other in chosen):
            chosen.append(species)
        if len(chosen) == TEAM_SIZE:
            break
    return Opponent(battle_id, region_id, "champion", index, (), trainer, _lineup(chosen), run, index, index)


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
        "team": list(opponent.team),
        "run": {"id": opponent.run, "step": opponent.step, "steps": opponent.steps} if opponent.run else None,
    }
