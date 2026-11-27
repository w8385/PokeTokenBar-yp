"""Win rates of fixed entry teams in the battle tower, per stretch of the climb, the way `TowerBattles` fights them.
Run from `bot/`: `python3 tools/tower_balance.py <cache.db> [runs] [parties.json] [battles]`. Every run seed fights
battles 1 to 50 at full HP whether or not the battle before was won; `run50` counts seeds where all fifty were won.
`parties.json` maps a name to three party members and adds to the reference teams (a player's own box stays out of the
repo). `battles` (`20,50`) fights only those battles, for many seeds of the owner, and leaves `run50` and `reach` out.
"""

import json
import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ypoke import entry_rules, foe_items, foe_moves, gyms, tower  # noqa: E402
from ypoke.battle import simulate  # noqa: E402
from ypoke.combatants import combatant  # noqa: E402
from ypoke.pokeapi import PokeAPIService  # noqa: E402
from ypoke.store import Store  # noqa: E402
from ypoke.upload_server import IV_KEYS, validate_members  # noqa: E402

LAST_BATTLE = 50
COLUMNS = ("set1-2", "set3-4", "owner20", "set5", "owner50", "run50", "reach")


def main() -> None:
    cache_path, runs = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 20
    parties = dict(PARTIES)
    if len(sys.argv) > 3 and sys.argv[3]:
        parties |= json.loads(Path(sys.argv[3]).read_text())
    battles = (tuple(int(battle) for battle in sys.argv[4].split(",")) if len(sys.argv) > 4
               else tuple(range(1, LAST_BATTLE + 1)))
    jobs = [(cache_path, name, team, run, battles) for name, team in parties.items() for run in range(runs)]
    tallies: dict[tuple[str, str], list[float]] = defaultdict(lambda: [0, 0])
    with ProcessPoolExecutor() as pool:
        for name, results in pool.map(_climb, jobs):
            for column, hit in results:
                tallies[(name, column)][0] += hit
                tallies[(name, column)][1] += 1
    print(f"{'party':12}" + "".join(f"{column:>9}" for column in COLUMNS))
    for name in parties:
        cells = []
        for column in COLUMNS:
            hit, count = tallies[(name, column)]
            if not count:
                cells.append(f"{'-':>9}")
            else:
                cells.append(f"{hit / count:9.1f}" if column == "reach" else f"{100 * hit / count:8.0f}%")
        print(f"{name:12}" + "".join(cells))


def _climb(job: tuple[str, str, list[dict], int, tuple[int, ...]]) -> tuple[str, list[tuple[str, float]]]:
    cache_path, name, team, run, battles = job
    pokeapi = PokeAPIService(Store(cache_path))
    team = validate_members([dict(member) for member in team], "team")
    won = [fight(pokeapi, team, run, battle) for battle in battles]
    results = [(stretch(battle), hit) for battle, hit in zip(battles, won)]
    if len(battles) < LAST_BATTLE:
        return name, results
    reach = next((battle - 1 for battle, hit in zip(battles, won) if not hit), LAST_BATTLE)
    return name, [*results, ("run50", all(won)), ("reach", reach)]


def stretch(battle: int) -> str:
    if battle in tower.OWNER_BATTLES:
        return f"owner{battle}"
    return "set1-2" if battle <= 20 else "set3-4" if battle <= 40 else "set5"


def fight(pokeapi, team: list[dict], run: int, battle: int) -> bool:
    """Whether `team` beats battle `battle` of run `run`, fought like `TowerBattles.battle` in entry mode."""
    mine = list(entry_rules.lineup([{**member, "level": tower.BATTLE_LEVEL} for member in team]).members)
    opponent = tower.opponent(run, battle)
    fighters = [combatant(pokeapi, member) for member in (*mine, *(m.battle_member() for m in opponent.members))]
    result = simulate((tuple(fighters[:len(mine)]), tuple(fighters[len(mine):])), run * 1000 + battle, [None] * len(mine))
    return result.winner == 0


def _max_team(species: tuple[int, ...]) -> list[dict]:
    """IV 31 members with a nature for their better attack stat and the foe picker's moves and items."""
    holders = [gyms.holder(species_id, foe_moves.species(species_id).picked) for species_id in species]
    return [
        {"pokemon_id": holder.species_id, "level": 100, "ivs": dict.fromkeys(IV_KEYS, 31), "held_item": item,
         "nature": "adamant" if holder.stats["attack"] >= holder.stats["special_attack"] else "modest",
         "moves": list(foe_moves.species(holder.species_id).picked)}
        for holder, item in zip(holders, foe_items.assign(holders), strict=True)
    ]


PARTIES = {
    # Garchomp, Metagross, Tyranitar.
    "ref-pseudo": _max_team((445, 376, 248)),
    # Mewtwo, Kyogre, Dialga.
    "ref-legend": _max_team((150, 382, 483)),
}

if __name__ == "__main__":
    main()
