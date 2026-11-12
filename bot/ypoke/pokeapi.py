"""PokéAPI client with a permanent SQLite cache. Docs: https://pokeapi.co/docs/v2"""

import json
import urllib.request

from ypoke.battle import BaseStats
from ypoke.store import Store

API_BASE = "https://pokeapi.co/api/v2"
TIMEOUT_SECONDS = 10

_STAT_KEYS = {
    "hp": "hp",
    "attack": "attack",
    "defense": "defense",
    "special-attack": "special_attack",
    "special-defense": "special_defense",
    "speed": "speed",
}


class PokeAPIService:
    def __init__(self, store: Store):
        self._store = store

    def pokemon(self, pokemon_id: int) -> dict:
        """Return `{"name_ko", "types", "base"}` for a PokéAPI `/pokemon/{id}` id. Raises on network errors."""
        cached = self._store.cached_pokemon(pokemon_id)
        if cached is not None:
            return cached
        data = self._fetch(pokemon_id)
        self._store.cache_pokemon(pokemon_id, data)
        return data

    def _fetch(self, pokemon_id: int) -> dict:
        pokemon = _get_json(f"{API_BASE}/pokemon/{pokemon_id}")
        species = _get_json(pokemon["species"]["url"])
        names = {entry["language"]["name"]: entry["name"] for entry in species["names"]}
        base = {_STAT_KEYS[entry["stat"]["name"]]: entry["base_stat"] for entry in pokemon["stats"]}
        return {
            "name_ko": names.get("ko") or names.get("en") or pokemon["name"],
            "types": [entry["type"]["name"] for entry in sorted(pokemon["types"], key=lambda t: t["slot"])],
            "base": base,
        }


def base_stats(data: dict) -> BaseStats:
    return BaseStats(**data["base"])


def _get_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "ypoke-bot/1.0"})
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.load(response)
