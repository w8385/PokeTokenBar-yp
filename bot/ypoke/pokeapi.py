"""PokéAPI client with a permanent SQLite cache. Docs: https://pokeapi.co/docs/v2"""

import json
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from ypoke.battle import BaseStats
from ypoke.store import Store

API_BASE = "https://pokeapi.co/api/v2"
TIMEOUT_SECONDS = 10
ATTEMPTS = 3
MOVE_FETCH_WORKERS = 6
_REQUEST_SLOTS = threading.BoundedSemaphore(MOVE_FETCH_WORKERS)
# Side games and remakes with their own learnsets; used only when a Pokémon appears in no main game.
_SIDE_VERSION_GROUPS = {
    "colosseum", "xd", "lets-go-pikachu-lets-go-eevee", "legends-arceus",
    "red-green-japan", "blue-japan", "legends-za", "mega-dimension", "champions",
}

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

    def attacking_moves(self, pokemon_id: int, level: int) -> list[dict]:
        """Damaging level-up moves learned at or below `level`, oldest first. Raises on network errors.

        Each move is `{"id", "name", "type", "power", "damage_class", "accuracy", "level"}`.
        """
        learned = [entry for entry in self.learnset(pokemon_id) if entry["level"] <= level]
        with ThreadPoolExecutor(max_workers=MOVE_FETCH_WORKERS) as pool:
            moves = list(pool.map(self.move, [entry["move_id"] for entry in learned]))
        return [
            {**move, "level": entry["level"]}
            for entry, move in zip(learned, moves)
            if move["power"] and move["damage_class"] != "status"
        ]

    def learnset(self, pokemon_id: int) -> list[dict]:
        """Level-up moves `{"move_id", "level"}` from the newest main game the Pokémon is in, by level."""
        key = f"learnset/{pokemon_id}"
        cached = self._store.cached(key)
        if cached is not None:
            return cached
        data = learnset_from(_get_json(f"{API_BASE}/pokemon/{pokemon_id}"))
        self._store.cache(key, data)
        return data

    def move(self, move_id: int) -> dict:
        key = f"move/{move_id}"
        cached = self._store.cached(key)
        if cached is not None:
            return cached
        move = _get_json(f"{API_BASE}/move/{move_id}")
        names = {entry["language"]["name"]: entry["name"] for entry in move["names"]}
        data = {
            "id": move["id"],
            "name": names.get("ko") or names.get("en") or move["name"],
            "type": move["type"]["name"],
            "power": move["power"],
            "damage_class": move["damage_class"]["name"],
            "accuracy": move["accuracy"],
        }
        self._store.cache(key, data)
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


def learnset_from(pokemon: dict) -> list[dict]:
    """Pick one version group's level-up moves out of a `/pokemon/{id}` body; a move learned twice keeps its lowest level."""
    by_group: dict[tuple[bool, int], dict[int, int]] = {}
    for entry in pokemon["moves"]:
        move_id = _id_from_url(entry["move"]["url"])
        for detail in entry["version_group_details"]:
            if detail["move_learn_method"]["name"] != "level-up":
                continue
            group = detail["version_group"]
            rank = (group["name"] not in _SIDE_VERSION_GROUPS, _id_from_url(group["url"]))
            levels = by_group.setdefault(rank, {})
            levels[move_id] = min(levels.get(move_id, detail["level_learned_at"]), detail["level_learned_at"])
    if not by_group:
        return []
    levels = by_group[max(by_group)]
    return [{"move_id": move_id, "level": level} for move_id, level in sorted(levels.items(), key=lambda item: (item[1], item[0]))]


def base_stats(data: dict) -> BaseStats:
    return BaseStats(**data["base"])


def _id_from_url(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[-1])


def _get_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "ypoke-bot/1.0"})
    for _ in range(ATTEMPTS - 1):
        try:
            return _read(request)
        except TimeoutError:
            pass
    return _read(request)


def _read(request: urllib.request.Request) -> dict:
    with _REQUEST_SLOTS, urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.load(response)
