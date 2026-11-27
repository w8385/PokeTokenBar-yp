"""Regenerate `tests/tower_learnsets.json`: per species of the tower's archetype builds and owner teams, the abilities
it can have (hidden included), every move it learns by the rule the battle builds tower foes with (Lv100, status
moves and egg status moves included) and its weight, which the offline difficulty test fights with. Species of the
balance tool's reference teams come along for their weight. Run from `bot/` after changing `tower_teams`:
`python3 tools/generate_tower_learnsets.py <cache.db>`.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from generate_champion_learnsets import LEARN_LEVEL  # noqa: E402
from tower_balance import PARTIES  # noqa: E402

from ypoke import tower_teams  # noqa: E402
from ypoke.pokeapi import PokeAPIService  # noqa: E402
from ypoke.store import Store  # noqa: E402

TABLE = Path(__file__).resolve().parents[1] / "tests" / "tower_learnsets.json"


def main() -> None:
    pokeapi = PokeAPIService(Store(sys.argv[1]))
    builds = (*tower_teams.BUILDS, *(build for team in tower_teams.OWNER_TEAMS.values() for build in team))
    species_ids = {build.species for build in builds} | {member["pokemon_id"] for team in PARTIES.values()
                                                          for member in team}
    rows = {str(species): _learnset(pokeapi, species) for species in sorted(species_ids)}
    TABLE.write_text("{\n" + ",\n".join(f'"{key}": {json.dumps(row)}' for key, row in rows.items()) + "\n}\n")
    print(f"wrote {len(rows)} species to {TABLE}")


def _learnset(pokeapi: PokeAPIService, species: int) -> dict:
    return {
        "abilities": sorted(entry["name"] for entry in pokeapi.abilities(species)),
        "moves": sorted(move["id"] for move in pokeapi.attacking_moves(species, LEARN_LEVEL, None, status=True)),
        "weight": pokeapi.pokemon(species).get("weight", 0),
    }


if __name__ == "__main__":
    main()
