#!/usr/bin/env python3
"""Generate data/gender-differences.json from the PokéAPI sprite repo and PokéAPI.

Run when the sprite repo or a new generation changes, and commit the result.

    python3 -I scripts/generate-gender-fixture.py [--out PATH]

`spriteFolders` lists the ids in every `female/` sprite folder the app reads. `femaleVarieties` lists the
PokéAPI varieties named `<species>-female`: the female that is its own Pokémon with its own stats.
"""
import argparse
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data/gender-differences.json"
CONTENTS = "https://api.github.com/repos/PokeAPI/sprites/contents/sprites/pokemon/"
API = "https://pokeapi.co/api/v2/"
FOLDERS = [
    "female", "shiny/female", "back/female", "back/shiny/female",
    "versions/generation-v/black-white/animated/female",
    "versions/generation-v/black-white/animated/shiny/female",
    "versions/generation-v/black-white/animated/back/female",
    "versions/generation-v/black-white/animated/back/shiny/female",
    "other/showdown/female", "other/showdown/shiny/female",
    "other/showdown/back/female", "other/showdown/back/shiny/female",
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    fixture = {
        "spriteFolders": {folder: folder_ids(folder) for folder in FOLDERS},
        "femaleVarieties": female_varieties(),
    }
    args.out.write_text(json.dumps(fixture, indent=1, sort_keys=True) + "\n")


def folder_ids(folder: str) -> list[int]:
    names = [item["name"] for item in get(CONTENTS + folder) if item["type"] == "file"]
    return sorted(int(name.split(".")[0]) for name in names if name.split(".")[0].isdigit())


def female_varieties() -> list[dict]:
    varieties = []
    for result in get(API + "pokemon?limit=100000")["results"]:
        if not result["name"].endswith("-female"):
            continue
        pokemon = get(result["url"])
        species_id = int(pokemon["species"]["url"].rstrip("/").split("/")[-1])
        if pokemon["id"] != species_id:
            varieties.append({"pokemonID": pokemon["id"], "name": pokemon["name"], "speciesID": species_id})
    return sorted(varieties, key=lambda variety: variety["pokemonID"])


def get(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": "PokeTokenBar-fixture-generator"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


if __name__ == "__main__":
    main()
