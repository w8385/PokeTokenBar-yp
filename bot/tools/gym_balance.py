"""Win rates of fixed parties against every gym, Elite Four member and champion, through `GymBattles`.
Run from `bot/`: `python3 tools/gym_balance.py <cache.db> [seeds] [party,party,...]`. Every battle starts at full HP
(the app heals between battles of a run). The champion is fought with its finale (6+n) and without it (6+0);
`e4run` counts seeds where all four Elite Four battles were won, `finale` how often the champion's hidden member
came out. The `max` parties are what a dedicated player could own: IV 31, the foe move picker's moves, the foe item
rule's items and one Mega Stone.
"""

import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ypoke import foe_items, foe_moves, gyms  # noqa: E402
from ypoke.gym_battle import GymBattles  # noqa: E402
from ypoke.pokeapi import PokeAPIService  # noqa: E402
from ypoke.store import Store  # noqa: E402
from ypoke.upload_server import IV_KEYS, validate_members  # noqa: E402

CHAMPION_MAIN_ONLY = "-champion6"
COLUMNS = (*(f"gym{index}" for index in range(1, 9)), "elite", "e4run", "champ6", "champ", "finale")


def main() -> None:
    cache_path, seeds = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 20
    parties = sys.argv[3].split(",") if len(sys.argv) > 3 else list(PARTIES)
    jobs = [(cache_path, party, region.id, seed) for party in parties for region in gyms.regions() for seed in range(seeds)]
    tallies: dict[tuple[str, str, str], list[int]] = defaultdict(lambda: [0, 0])
    with ProcessPoolExecutor() as pool:
        for party, region_id, results in pool.map(_fight_region, jobs, chunksize=4):
            for column, hit in results:
                tally = tallies[(party, region_id, column)]
                tally[0] += hit
                tally[1] += 1
    _report(parties, tallies)


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
    results: list[tuple[str, bool]] = []
    for opponent in (*region.gyms, *region.elite, main_only):
        body = engine.battle(opponent.id, team)
        results.append((_column(opponent), body["won"]))
        if opponent.kind == "champion" and opponent.finale:
            results.append(("finale", any(event["type"] == "finale" for event in body["events"])))
    elite = [won for column, won in results if column == "elite"]
    results.append(("e4run", all(elite)))
    return party, region_id, results


def _column(opponent: gyms.Opponent) -> str:
    if opponent.kind == "gym":
        return f"gym{opponent.index}"
    if opponent.kind == "elite":
        return "elite"
    return "champ6" if opponent.id.endswith(CHAMPION_MAIN_ONLY) else "champ"


def _report(parties: list[str], tallies: dict[tuple[str, str, str], list[int]]) -> None:
    for party in parties:
        print(f"\n{party}")
        print(f"{'region':8}" + "".join(f"{column:>7}" for column in COLUMNS))
        totals = defaultdict(lambda: [0, 0])
        for region in gyms.regions():
            cells = []
            for column in COLUMNS:
                hit, count = tallies[(party, region.id, column)]
                totals[column][0] += hit
                totals[column][1] += count
                cells.append(f"{100 * hit / count:6.0f}%" if count else "      -")
            print(f"{region.id:8}" + "".join(cells))
        print(f"{'all':8}" + "".join(f"{100 * hit / count:6.0f}%" if count else "      -"
                                     for hit, count in (totals[column] for column in COLUMNS)))


def _max_party(species: tuple[int, ...], stone_holder: int, stone: str) -> list[dict]:
    """Lv100 members (they fight at Lv50) with IV 31, a nature for their better attack stat, the foe picker's moves
    and the foe item rule's items, `stone` replacing the item of `species[stone_holder]`."""
    holders = [gyms.holder(species_id, foe_moves.species(species_id).picked) for species_id in species]
    held = foe_items.assign(holders[:stone_holder] + holders[stone_holder + 1:])
    held.insert(stone_holder, stone)
    return [
        _member(holder.species_id, 100, ivs=dict.fromkeys(IV_KEYS, 31), held_item=item,
                nature="adamant" if holder.stats["attack"] >= holder.stats["special_attack"] else "modest",
                moves=list(foe_moves.species(holder.species_id).picked))
        for holder, item in zip(holders, held, strict=True)
    ]


def _member(pokemon_id: int, level: int, **extra) -> dict:
    return {"pokemon_id": pokemon_id, "level": level, **extra}


BOX6_IVS = dict.fromkeys(IV_KEYS, 20)
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
    # Garchomp, Metagross, Tyranitar, Rayquaza, Kyogre, Togekiss.
    "max": _max_party((445, 376, 248, 384, 382, 468), 0, "garchompite"),
    # Ice and Fairy for the dragon- and flying-heavy champions: Mamoswine, Gardevoir, Metagross, Tyranitar, Kyogre,
    # Garchomp.
    "max-ice": _max_party((473, 282, 376, 248, 382, 445), 1, "gardevoirite"),
    # Mewtwo, Kyogre, Groudon, Rayquaza, Dialga, Xerneas.
    "max-legend": _max_party((150, 382, 383, 384, 483, 716), 0, "mewtwonite-y"),
}

if __name__ == "__main__":
    main()
