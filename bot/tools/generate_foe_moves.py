"""Regenerate `ypoke/foe_moves.json`: per species its types, base stats, the four moves `foe_moves.pick` gives it and
every attacking move it can learn (level-up at any level and machine), plus the data of those moves.
Run from `bot/`: `python3 tools/generate_foe_moves.py <cache.db>`; the PokéAPI cache lets a rerun resume.
"""

import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ypoke import foe_moves  # noqa: E402
from ypoke.foe_moves import FoeMove  # noqa: E402
from ypoke.pokeapi import PokeAPIService  # noqa: E402
from ypoke.store import Store  # noqa: E402

SPECIES_COUNT = 1025
LEARN_LEVEL = 100
STAT_KEYS = ("hp", "attack", "defense", "special_attack", "special_defense", "speed")


def main() -> None:
    pokeapi = PokeAPIService(Store(sys.argv[1]))
    with ThreadPoolExecutor(max_workers=6) as pool:
        rows = list(pool.map(lambda species_id: _species(pokeapi, species_id), range(1, SPECIES_COUNT + 1)))
    moves = {move.id: move for _, _, _, _, learnable in rows for move in learnable}
    body = {
        "moves": {
            str(move.id): [move.type, "physical" if move.physical else "special", move.power, move.accuracy, move.hits]
            for move in sorted(moves.values(), key=lambda move: move.id)
        },
        "species": [
            [species_id, types, stats, picked, sorted(move.id for move in learnable)]
            for species_id, types, stats, picked, learnable in rows
        ],
    }
    moves_text = ",\n".join(f'"{key}": {json.dumps(row)}' for key, row in body["moves"].items())
    species_text = ",\n".join(json.dumps(row) for row in body["species"])
    foe_moves.FOE_TABLE.write_text(f'{{"moves": {{\n{moves_text}\n}},\n"species": [\n{species_text}\n]}}\n')
    print(f"wrote {len(rows)} species and {len(moves)} moves to {foe_moves.FOE_TABLE}")


def _species(pokeapi: PokeAPIService, species_id: int) -> tuple:
    data = pokeapi.pokemon(species_id)
    learnable = [
        FoeMove(move["id"], move["type"], move["damage_class"] == "physical", move["power"], move["accuracy"],
                foe_moves.expected_hits(move["min_hits"], move["max_hits"]))
        for move in pokeapi.attacking_moves(species_id, LEARN_LEVEL, None)
        if move["power"] and move["damage_class"] != "status" and not move["weather"]
    ]
    stats = [data["base"][key] for key in STAT_KEYS]
    picked = foe_moves.pick(learnable, tuple(data["types"]), data["base"]["attack"], data["base"]["special_attack"])
    return species_id, data["types"], stats, picked, learnable


if __name__ == "__main__":
    main()
