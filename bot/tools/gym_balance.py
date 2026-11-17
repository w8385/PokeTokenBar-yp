"""Win rates of three fixed parties against every gym, Elite Four member and champion, through `GymBattles`.
Run from `bot/`: `python3 tools/gym_balance.py <cache.db> [seeds]`. Every battle starts at full HP (the app heals
between battles of a run). The champion is fought with its finale (6+n) and without it (6+0).
"""

import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ypoke import gyms  # noqa: E402
from ypoke.gym_battle import GymBattles  # noqa: E402
from ypoke.pokeapi import PokeAPIService  # noqa: E402
from ypoke.store import Store  # noqa: E402
from ypoke.upload_server import validate_members  # noqa: E402


def _member(pokemon_id: int, level: int, **extra) -> dict:
    return {"pokemon_id": pokemon_id, "level": level, **extra}


BOX6_IVS = dict.fromkeys(("hp", "attack", "defense", "special_attack", "special_defense", "speed"), 20)
PARTIES = {
    "box6": [
        _member(59, 100, nature="bold", ability="intimidate", ivs=BOX6_IVS),
        _member(230, 100, nature="modest", ability="sniper", ivs=BOX6_IVS),
        _member(130, 100, nature="brave", ability="intimidate", held_item="gyaradosite", ivs=BOX6_IVS),
        _member(169, 100, nature="mild", ability="inner-focus", ivs=BOX6_IVS),
        _member(584, 100, nature="quirky", ability="snow-warning", ivs=BOX6_IVS),
        _member(254, 100, nature="lax", ability="overgrow", ivs=BOX6_IVS),
    ],
    "mid": [_member(pokemon_id, 50) for pokemon_id in (3, 59, 121, 94, 76, 143)],
    "weak": [_member(pokemon_id, 30) for pokemon_id in (1, 4, 7, 74, 92, 133)],
}
CHAMPION_MAIN_ONLY = "-champion6"


def main() -> None:
    cache_path, seeds = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 20
    jobs = [(cache_path, party, region.id, seed) for party in PARTIES for region in gyms.regions() for seed in range(seeds)]
    wins: dict[tuple[str, str, str], list[int]] = defaultdict(lambda: [0, 0])
    with ProcessPoolExecutor() as pool:
        for party, region_id, results in pool.map(_fight_region, jobs, chunksize=4):
            for battle, won in results:
                tally = wins[(party, region_id, battle)]
                tally[0] += won
                tally[1] += 1
    _report(wins)


def _fight_region(job: tuple[str, str, str, int]) -> tuple[str, str, list[tuple[str, bool]]]:
    cache_path, party, region_id, seed = job
    region = next(region for region in gyms.regions() if region.id == region_id)
    champion = region.elite[-1]
    main_only = replace(champion, id=champion.id + CHAMPION_MAIN_ONLY, team=champion.shown,
                        moves=champion.moves[:len(champion.shown)], items=champion.items[:len(champion.shown)], finale=0)
    original = gyms.find
    gyms.find = lambda battle_id: main_only if battle_id == main_only.id else original(battle_id)
    ordinal = [0]

    def new_seed() -> int:
        ordinal[0] += 1
        return seed * 7919 + ordinal[0] * 104729 + gyms.regions().index(region)

    engine = GymBattles(PokeAPIService(Store(cache_path)), new_seed)
    team = validate_members([dict(member) for member in PARTIES[party]], "team")
    battles = [*region.gyms, *region.elite, main_only]
    return party, region_id, [(_kind(opponent), engine.battle(opponent.id, team)["won"]) for opponent in battles]


def _kind(opponent: gyms.Opponent) -> str:
    if opponent.kind == "gym":
        return f"gym{opponent.index}"
    if opponent.kind == "elite":
        return "elite"
    return "champ6" if opponent.id.endswith(CHAMPION_MAIN_ONLY) else "champ"


def _report(wins: dict[tuple[str, str, str], list[int]]) -> None:
    columns = [*(f"gym{index}" for index in range(1, 9)), "elite", "champ6", "champ"]
    for party in PARTIES:
        print(f"\n{party}")
        print(f"{'region':8}" + "".join(f"{column:>7}" for column in columns))
        totals = defaultdict(lambda: [0, 0])
        for region in gyms.regions():
            cells = []
            for column in columns:
                won, fought = wins[(party, region.id, column)]
                totals[column][0] += won
                totals[column][1] += fought
                cells.append(f"{100 * won / fought:6.0f}%" if fought else "      -")
            print(f"{region.id:8}" + "".join(cells))
        print(f"{'all':8}" + "".join(f"{100 * won / fought:6.0f}%" for won, fought in (totals[c] for c in columns)))


if __name__ == "__main__":
    main()
