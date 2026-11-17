"""Regenerate `tests/champion_learnsets.json`: per champion member's `/pokemon` id (its form's, if it names one) the
abilities it can have (hidden included) and every move it learns by the rule the battle builds foes with, egg moves
included. `foe_moves.json` holds species' attacking moves only, so the champion tests read forms and status moves from
here. Run from `bot/` after changing `CHAMPION_TEAMS`: `python3 tools/generate_champion_learnsets.py <cache.db>`.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ypoke import pokeapi as pokeapi_module  # noqa: E402
from ypoke.gym_data import CHAMPION_TEAMS  # noqa: E402
from ypoke.pokeapi import API_BASE, PokeAPIService  # noqa: E402
from ypoke.store import Store  # noqa: E402

TABLE = Path(__file__).resolve().parents[1] / "tests" / "champion_learnsets.json"
LEARN_LEVEL = 100


def main() -> None:
    pokeapi = PokeAPIService(Store(sys.argv[1]))
    members = sorted({ace.form or ace.species for team in CHAMPION_TEAMS.values() for ace in team})
    rows = {str(pokemon_id): _learnset(pokeapi, pokemon_id) for pokemon_id in members}
    TABLE.write_text("{\n" + ",\n".join(f'"{key}": {json.dumps(row)}' for key, row in rows.items()) + "\n}\n")
    print(f"wrote {len(rows)} members to {TABLE}")


def _learnset(pokeapi: PokeAPIService, pokemon_id: int) -> dict:
    abilities = pokeapi_module._get_json(f"{API_BASE}/pokemon/{pokemon_id}")["abilities"]
    moves = pokeapi.attacking_moves(pokemon_id, LEARN_LEVEL, None, status=True)
    return {
        "abilities": sorted(entry["ability"]["name"] for entry in abilities),
        "moves": sorted(move["id"] for move in moves),
    }


if __name__ == "__main__":
    main()
