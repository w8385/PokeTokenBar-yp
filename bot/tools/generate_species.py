"""Regenerate `ypoke/species.json` (static species table for gym teams). Run from `bot/`:
`python3 tools/generate_species.py [cache-dir]`; a cache directory lets a rerun resume after a network failure.
Row: `[id, type1, type2, parent_id, level, excluded, base_stat_total, reach]`. `reach` is the level the species can be
reached by evolving (stone, trade and friendship evolutions count as 30); `level` is the first level it is usable at
(its first damaging level-up move); `excluded` marks baby, legendary and mythical species.
"""

import hashlib
import json
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ypoke.pokeapi import learnset_from  # noqa: E402

DATA_BASE = "https://raw.githubusercontent.com/PokeAPI/api-data/master/data/api/v2"
SPECIES_COUNT = 1025
MAX_LEVEL = 50
NO_LEVEL_EVOLUTION = 30
NEVER = 999
ATTEMPTS = 6
OUTPUT = Path(__file__).resolve().parents[1] / "ypoke" / "species.json"
CACHE = Path(sys.argv[1]) if len(sys.argv) > 1 else None


def main() -> None:
    if CACHE:
        CACHE.mkdir(parents=True, exist_ok=True)
    ids = range(1, SPECIES_COUNT + 1)
    with ThreadPoolExecutor(max_workers=8) as pool:
        pokemon = dict(zip(ids, pool.map(lambda i: _get_json("pokemon", i), ids)))
        species = dict(zip(ids, pool.map(lambda i: _get_json("pokemon-species", i), ids)))
        learnsets = {i: [e for e in learnset_from(pokemon[i]) if e["level"] <= MAX_LEVEL] for i in ids}
        move_ids = sorted({entry["move_id"] for rows in learnsets.values() for entry in rows})
        moves = dict(zip(move_ids, pool.map(lambda m: _get_json("move", m), move_ids)))
        chain_ids = sorted({_species_id(species[i]["evolution_chain"]["url"]) for i in ids})
        chains = list(pool.map(lambda c: _get_json("evolution-chain", c), chain_ids))
    own_level: dict[int, int] = {}
    for chain in chains:
        _collect_levels(chain["chain"], own_level)
    damaging = {m for m, data in moves.items() if data["power"] and data["damage_class"]["name"] != "status"}
    parents = {i: _species_id(species[i]["evolves_from_species"]["url"]) if species[i]["evolves_from_species"] else 0 for i in ids}
    first_attack = {
        i: min((e["level"] for e in learnsets[i] if e["move_id"] in damaging), default=NEVER) for i in ids
    }
    reached: dict[int, int] = {}

    def reach_level(i: int) -> int:
        if i not in reached:
            reached[i] = 1
            if parents[i]:
                reached[i] = max(own_level.get(i, NO_LEVEL_EVOLUTION), reach_level(parents[i]))
        return reached[i]

    def usable_level(i: int) -> int:
        return max(1, first_attack[i], reach_level(i))

    rows = []
    for i in ids:
        types = [t["type"]["name"] for t in sorted(pokemon[i]["types"], key=lambda t: t["slot"])]
        excluded = species[i]["is_baby"] or species[i]["is_legendary"] or species[i]["is_mythical"]
        total = sum(entry["base_stat"] for entry in pokemon[i]["stats"])
        rows.append(
            [i, types[0], types[1] if len(types) > 1 else "", parents[i], usable_level(i), int(excluded), total, reach_level(i)]
        )
    OUTPUT.write_text("[\n" + ",\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n]\n")
    print(f"wrote {len(rows)} rows to {OUTPUT}")


def _collect_levels(node: dict, levels: dict[int, int]) -> None:
    required = [d["min_level"] for d in node["evolution_details"] if d.get("min_level")]
    if required:
        levels[_species_id(node["species"]["url"])] = min(required)
    for child in node["evolves_to"]:
        _collect_levels(child, levels)


def _species_id(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[-1])


def _get_json(kind: str, item_id: int) -> dict:
    url = f"{DATA_BASE}/{kind}/{item_id}/index.json"
    path = CACHE / hashlib.sha1(url.encode()).hexdigest() if CACHE else None
    if path and path.exists():
        return json.loads(path.read_text())
    request = urllib.request.Request(url, headers={"User-Agent": "ypoke-bot-tools/1.0"})
    for attempt in range(1, ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                body = response.read()
            break
        except OSError:
            if attempt == ATTEMPTS:
                raise
            time.sleep(2 * attempt)
    if path:
        path.write_bytes(body)
    return json.loads(body)


if __name__ == "__main__":
    main()
