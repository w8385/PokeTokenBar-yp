"""PokéAPI client with a permanent SQLite cache. Docs: https://pokeapi.co/docs/v2"""

import json
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Collection
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

    def can_evolve(self, pokemon_id: int) -> bool:
        """Whether the species still has an evolution (Eviolite). Raises on network errors."""
        key = f"can-evolve/{pokemon_id}"
        cached = self._store.cached(key)
        if cached is not None:
            return bool(cached)
        species = _get_json(_get_json(f"{API_BASE}/pokemon/{pokemon_id}")["species"]["url"])
        chain = _get_json(species["evolution_chain"]["url"])["chain"]
        result = _evolves_further(chain, species["name"])
        self._store.cache(key, result)
        return result

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
        needed = sorted({(member["pokemon_id"], member["level"], tuple(member.get("moves") or ())) for member in members})

        def fetch(item: tuple[int, int, tuple[int, ...]]) -> OSError | None:
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
        return len({pokemon_id for pokemon_id, _, _ in needed})

    def attacking_moves(self, pokemon_id: int, level: int, machine_ids: Collection[int] | None = ()) -> list[dict]:
        """Damaging and weather-setting moves usable at `level`: level-up moves learned at or below it, oldest first,
        then machine (TM) moves by id. Raises on network errors.

        Each move is `move()` plus `"level"` (0 for a machine move) and `"source"` (`"level"` or `"machine"`).
        A TM move's data is fetched only if its id is in `machine_ids`; `None` means all of them.
        """
        learnset = self.learnset(pokemon_id)
        by_id = {entry["move_id"]: entry for entry in learnset if entry["source"] == "level" and entry["level"] <= level}
        for entry in learnset:
            if entry["source"] == "machine" and entry["move_id"] not in by_id and (machine_ids is None or entry["move_id"] in machine_ids):
                by_id[entry["move_id"]] = entry
        learned = list(by_id.values())
        with ThreadPoolExecutor(max_workers=MOVE_FETCH_WORKERS) as pool:
            moves = list(pool.map(self.move, [entry["move_id"] for entry in learned]))
        return [
            {**move, "level": entry["level"], "source": entry["source"]}
            for entry, move in zip(learned, moves)
            if move["weather"] or (move["power"] and move["damage_class"] != "status")
        ]

    def learnset(self, pokemon_id: int) -> list[dict]:
        """`{"move_id", "level", "source"}` from the newest main game the Pokémon is in: level-up moves by level, then machine moves by id."""
        key = f"learnset-v2/{pokemon_id}"
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
    """Pick one version group out of a `/pokemon/{id}` body: its level-up moves (a move learned twice keeps its lowest level),
    then the moves it teaches by machine with level 0. The group is the newest one with level-up moves."""
    levels_by_group: dict[tuple[bool, int], dict[int, int]] = {}
    machines_by_group: dict[tuple[bool, int], set[int]] = {}
    for entry in pokemon["moves"]:
        move_id = _id_from_url(entry["move"]["url"])
        for detail in entry["version_group_details"]:
            method = detail["move_learn_method"]["name"]
            if method not in ("level-up", "machine"):
                continue
            group = detail["version_group"]
            rank = (group["name"] not in _SIDE_VERSION_GROUPS, _id_from_url(group["url"]))
            if method == "machine":
                machines_by_group.setdefault(rank, set()).add(move_id)
                continue
            levels = levels_by_group.setdefault(rank, {})
            levels[move_id] = min(levels.get(move_id, detail["level_learned_at"]), detail["level_learned_at"])
    if not levels_by_group:
        return []
    rank = max(levels_by_group)
    by_level = sorted(levels_by_group[rank].items(), key=lambda item: (item[1], item[0]))
    return [
        *({"move_id": move_id, "level": level, "source": "level"} for move_id, level in by_level),
        *({"move_id": move_id, "level": 0, "source": "machine"} for move_id in sorted(machines_by_group.get(rank, ()))),
    ]


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


def _evolves_further(node: dict, species_name: str) -> bool:
    """Whether `species_name` is in the chain below `node` with at least one evolution of its own."""
    if node["species"]["name"] == species_name:
        return bool(node["evolves_to"])
    return any(_evolves_further(child, species_name) for child in node["evolves_to"])


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
