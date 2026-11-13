"""PokéAPI client with a permanent SQLite cache. Docs: https://pokeapi.co/docs/v2"""

import json
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from ypoke.battle import BaseStats
from ypoke.store import Store

API_BASE = "https://pokeapi.co/api/v2"
TIMEOUT_SECONDS = 10
ATTEMPTS = 2
RETRY_BACKOFF_SECONDS = 1.0
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
_BATTLE_STAT_KEYS = set(_STAT_KEYS) - {"hp"}
_AILMENTS = {"burn", "paralysis", "poison", "toxic", "sleep", "freeze", "confusion"}
_TOXIC_MOVE_IDS = {92, 305, 830}
_STAT_CATEGORIES = {"damage-lower": "target", "damage-raise": "user"}
WEATHER_MOVES = {241: "sun", 240: "rain", 201: "sandstorm", 258: "hail", 883: "snow"}
_ALWAYS_HITS_IN = {87: ["rain"], 542: ["rain"], 59: ["hail", "snow"]}


class PokeAPIService:
    def __init__(self, store: Store):
        self._store = store

    def mega_form(self, pokemon_id: int) -> dict:
        """`pokemon()` of a Mega form plus its first non-hidden ability as `"ability_id"` (slug) and `"ability"`
        (Korean name); both None if PokéAPI lists none."""
        key = f"mega-v2/{pokemon_id}"
        cached = self._store.cached(key)
        if cached is not None:
            return cached
        ability_id, ability = self._ability(pokemon_id)
        data = {**self.pokemon(pokemon_id), "ability": ability, "ability_id": ability_id}
        self._store.cache(key, data)
        return data

    def pokemon(self, pokemon_id: int) -> dict:
        """Return `{"name_ko", "types", "base"}` for a PokéAPI `/pokemon/{id}` id. Raises on network errors."""
        cached = self._store.cached_pokemon(pokemon_id)
        if cached is not None:
            return cached
        data = self._fetch(pokemon_id)
        self._store.cache_pokemon(pokemon_id, data)
        return data

    def warm(self, members: list[dict]) -> int:
        """Cache the species, learnset and moves every member needs, in parallel within the request slots.

        Every member is tried; the first OSError is raised afterwards. Returns the number of distinct Pokémon.
        """
        needed = sorted({(member["pokemon_id"], member["level"]) for member in members})

        def fetch(item: tuple[int, int]) -> OSError | None:
            try:
                self.pokemon(item[0])
                self.attacking_moves(*item)
            except OSError as error:
                return error
            return None

        with ThreadPoolExecutor(max_workers=MOVE_FETCH_WORKERS) as pool:
            errors = [error for error in pool.map(fetch, needed) if error is not None]
        if errors:
            raise errors[0]
        return len({pokemon_id for pokemon_id, _ in needed})

    def attacking_moves(self, pokemon_id: int, level: int) -> list[dict]:
        """Damaging and weather-setting level-up moves learned at or below `level`, oldest first. Raises on network errors.

        Each move is `move()` plus `"level"`.
        """
        learned = [entry for entry in self.learnset(pokemon_id) if entry["level"] <= level]
        with ThreadPoolExecutor(max_workers=MOVE_FETCH_WORKERS) as pool:
            moves = list(pool.map(self.move, [entry["move_id"] for entry in learned]))
        return [
            {**move, "level": entry["level"]}
            for entry, move in zip(learned, moves)
            if move["weather"] or (move["power"] and move["damage_class"] != "status")
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
        """The move's battle data; `ailment` is one of the simulated statuses and other secondary effects are dropped."""
        key = f"move-v4/{move_id}"
        cached = self._store.cached(key)
        if cached is not None:
            return cached
        data = move_from(_get_json(f"{API_BASE}/move/{move_id}"))
        self._store.cache(key, data)
        return data

    def _ability(self, pokemon_id: int) -> tuple[str | None, str | None]:
        abilities = _get_json(f"{API_BASE}/pokemon/{pokemon_id}")["abilities"]
        slots = [entry for entry in abilities if not entry["is_hidden"]] or abilities
        if not slots:
            return None, None
        ability = _get_json(slots[0]["ability"]["url"])
        names = {entry["language"]["name"]: entry["name"] for entry in ability["names"]}
        return ability["name"], names.get("ko") or names.get("en") or ability["name"]

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


def move_from(move: dict) -> dict:
    """Normalize a `/move/{id}` body. Stat changes count only for damaging moves that lower the target or change the user.

    `drain` is a percent of the damage dealt: positive heals the user, negative is recoil. PokéAPI has no badly-poisoned ailment, so the toxic moves are listed by id.
    """
    names = {entry["language"]["name"]: entry["name"] for entry in move["names"]}
    meta = move.get("meta") or {}
    ailment = (meta.get("ailment") or {}).get("name")
    if ailment == "poison" and move["id"] in _TOXIC_MOVE_IDS:
        ailment = "toxic"
    category = (meta.get("category") or {}).get("name")
    stat_changes = [
        {"stat": _STAT_KEYS[entry["stat"]["name"]], "change": entry["change"]}
        for entry in move.get("stat_changes", [])
        if category in _STAT_CATEGORIES and entry["stat"]["name"] in _BATTLE_STAT_KEYS
    ]
    return {
        "id": move["id"],
        "name": names.get("ko") or names.get("en") or move["name"],
        "type": move["type"]["name"],
        "power": move["power"] or 0,
        "damage_class": move["damage_class"]["name"],
        "accuracy": move["accuracy"],
        "priority": move["priority"],
        "pp": move["pp"] or 1,
        "crit_rate": meta.get("crit_rate") or 0,
        "ailment": ailment if ailment in _AILMENTS else None,
        "ailment_chance": (meta.get("ailment_chance") or 0) if ailment in _AILMENTS else 0,
        "stat_changes": stat_changes,
        "stat_target": _STAT_CATEGORIES.get(category, "target"),
        "stat_chance": (meta.get("stat_chance") or 0) if stat_changes else 0,
        "weather": WEATHER_MOVES.get(move["id"]),
        "always_hits_in": _ALWAYS_HITS_IN.get(move["id"], []),
        "drain": meta.get("drain") or 0,
        "min_hits": meta.get("min_hits") or 1,
        "max_hits": meta.get("max_hits") or 1,
    }


def base_stats(data: dict) -> BaseStats:
    return BaseStats(**data["base"])


def _id_from_url(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[-1])


def _get_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "ypoke-bot/1.0"})
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return _read(request)
        except OSError as error:
            if attempt == ATTEMPTS or not _is_transient(error):
                raise
            time.sleep(RETRY_BACKOFF_SECONDS * attempt)
    raise AssertionError("unreachable")


def _is_transient(error: OSError) -> bool:
    if isinstance(error, urllib.error.HTTPError):
        return error.code >= 500
    if isinstance(error, urllib.error.URLError):
        return isinstance(error.reason, TimeoutError)
    return isinstance(error, TimeoutError)


def _read(request: urllib.request.Request) -> dict:
    with _REQUEST_SLOTS, urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.load(response)
