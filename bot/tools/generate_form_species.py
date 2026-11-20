"""Regenerate `ypoke/form_species.json`: the national species of every PokéAPI `/pokemon` variety id above 10000
(Megas, regional forms, Rotom's appliances…). Run from `bot/`: `python3 tools/generate_form_species.py`.
"""

import csv
import io
import json
import urllib.request
from pathlib import Path

SOURCE = "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon.csv"
OUTPUT = Path(__file__).resolve().parents[1] / "ypoke" / "form_species.json"


def main() -> None:
    with urllib.request.urlopen(SOURCE, timeout=60) as response:
        rows = csv.DictReader(io.StringIO(response.read().decode()))
        table = {int(row["id"]): int(row["species_id"]) for row in rows if int(row["id"]) > 10000}
    OUTPUT.write_text(json.dumps({str(key): table[key] for key in sorted(table)}, separators=(",", ":")) + "\n")
    print(f"wrote {len(table)} varieties to {OUTPUT}")


if __name__ == "__main__":
    main()
