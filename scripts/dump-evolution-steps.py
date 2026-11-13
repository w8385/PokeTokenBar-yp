#!/usr/bin/env python3
"""Dump every evolution step of the supported dex (#1..#1025) from PokéAPI into a checked-in fixture.

    python3 scripts/dump-evolution-steps.py            # rewrites Tests/PokeTokenBarTests/Fixtures/evolution-steps.json

Each step is one edge of an evolution chain: the evolved species, its parent, and every
`evolution_details` entry with its empty fields dropped. The invariant test walks this file, so
a new PokéAPI condition that the app does not map fails the build instead of silently becoming
an XP fallback. Re-run it when a new generation lands.
"""
import json
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

API = "https://pokeapi.co/api/v2"
MAX_SPECIES = 1025
OUT = Path(__file__).resolve().parent.parent / "Tests/PokeTokenBarTests/Fixtures/evolution-steps.json"


def main():
    listing = get(f"{API}/evolution-chain?limit=2000")["results"]
    with ThreadPoolExecutor(max_workers=4) as pool:
        chains = list(pool.map(lambda entry: get(entry["url"]), listing))
    steps = []
    for chain in chains:
        walk(chain["chain"], None, steps)
    steps.sort(key=lambda s: (s["species"], s["parent"]))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(steps, ensure_ascii=False, indent=1) + "\n")
    print(f"{len(steps)} steps -> {OUT}", file=sys.stderr)


def walk(link, parent, steps):
    sid = species_id(link["species"])
    if parent is not None and sid <= MAX_SPECIES:
        steps.append({
            "species": sid,
            "name": link["species"]["name"],
            "parent": parent,
            "details": [compact(d) for d in link["evolution_details"]],
        })
    for child in link["evolves_to"]:
        walk(child, sid, steps)


def compact(detail):
    out = {}
    for key, value in detail.items():
        if value is None or value is False or value in ("", []):
            continue
        out[key] = value.get("name", value) if isinstance(value, dict) else value
    return out


def species_id(ref):
    return int(ref["url"].rstrip("/").split("/")[-1])


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "poketokenbar-fixture-dump"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=30) as resp:
                return json.load(resp)
        except (OSError, ValueError):
            if attempt == 5:
                raise
            time.sleep(2 ** attempt)


if __name__ == "__main__":
    main()
