"""PokéAPI client with a permanent SQLite cache. Docs: https://pokeapi.co/docs/v2"""

import json
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Collection, Sequence
from concurrent.futures import ThreadPoolExecutor

from ypoke import battle_data, items, tera_forms
from ypoke.battle import BaseStats
from ypoke.mega_stones import mega_form_id, move_mega_form_id
from ypoke.move_effects import STATUS_MOVES, attacks, wants_status_moves
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
    "accuracy": "accuracy",
    "evasion": "evasion",
}
_BATTLE_STAT_KEYS = set(_STAT_KEYS) - {"hp"}
_AILMENTS = {"burn", "paralysis", "poison", "toxic", "sleep", "freeze", "confusion"}
EFFECT_KEYS = frozenset({"badly-poisons", "weather", "always-hits-in"})
_TOXIC_MOVE_IDS = battle_data.ids("moves", "badly-poisons")
_STAT_CATEGORIES = {"damage-lower": "target", "damage-raise": "user"}
WEATHER_MOVES = battle_data.args("moves", "weather", "weather")
_ALWAYS_HITS_IN = {move_id: list(weathers)
                   for move_id, weathers in battle_data.args("moves", "always-hits-in", "weathers").items()}


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
        """Cache the species, form, learnset and moves every member needs, in parallel within the request slots.

        Every member is tried; the first OSError is raised afterwards. Returns the number of distinct Pokémon.
        """
        needed = sorted({(member["pokemon_id"], member["level"], tuple(member.get("moves") or ()), bool(member.get("mirror_herb")))
                         for member in members})
        forms = sorted({form for member in members for form in _forms_of(member)})

        def fetch(item: tuple[int, int, tuple[int, ...], bool]) -> OSError | None:
            pokemon_id, level, chosen, herb = item
            try:
                self.pokemon(pokemon_id)
                self.attacking_moves(pokemon_id, level, chosen, status=wants_status_moves(chosen), **({"egg": True} if herb else {}))
            except OSError as error:
                return error
            return None

        def fetch_form(form: tuple[str, int]) -> OSError | None:
            try:
                (self.mega_form if form[0] == "mega" else self.pokemon)(form[1])
            except OSError as error:
                return error
            return None

        with ThreadPoolExecutor(max_workers=MOVE_FETCH_WORKERS) as pool:
            results = [*pool.map(fetch, needed), *pool.map(fetch_form, forms)]
        errors = [error for error in results if error is not None]
        if errors:
            raise errors[0]
        return len({pokemon_id for pokemon_id, *_ in needed})

    def attacking_moves(self, pokemon_id: int, level: int, machine_ids: Collection[int] | None = (),
                        status: bool = False, egg: bool = False) -> list[dict]:
        """Damaging and weather-setting moves usable at `level`: level-up moves learned at or below it, oldest first,
        then machine (TM) moves by id. Raises on network errors.

        Each move is `move()` plus `"level"` (0 for a machine or egg move) and `"source"` (`"level"`, `"egg"` or
        `"machine"`). A TM move's data is fetched only if its id is in `machine_ids`; `None` means all of them.
        With `egg` (a Mirror Herb), the attacking egg moves of the Pokémon and every species it evolved from come
        between the level-up and machine moves, by id. With `status`, the status moves the battle implements follow
        (`status_move_entries`).
        """
        learnset = self.learnset(pokemon_id)
        eggs = [self.egg_moves(member) for member in (pokemon_id, *_ancestors(pokemon_id))] if status or egg else []
        by_id = {entry["move_id"]: entry for entry in learnset if entry["source"] == "level" and entry["level"] <= level}
        if egg:
            for move_id in sorted({move_id for listed in eggs for move_id in listed}):
                by_id.setdefault(move_id, {"move_id": move_id, "level": 0, "source": "egg"})
        for entry in learnset:
            if entry["source"] == "machine" and entry["move_id"] not in by_id and (machine_ids is None or entry["move_id"] in machine_ids):
                by_id[entry["move_id"]] = entry
        learned = [entry for entry in by_id.values() if entry["move_id"] not in STATUS_MOVES]
        if status:
            learned += status_move_entries(learnset, level, machine_ids, eggs)
        with ThreadPoolExecutor(max_workers=MOVE_FETCH_WORKERS) as pool:
            moves = list(pool.map(self.move, [entry["move_id"] for entry in learned]))
        return [
            {**move, "level": entry["level"], "source": entry["source"]}
            for entry, move in zip(learned, moves)
            if move["weather"] or attacks(move["id"], move["power"], move["damage_class"]) or move["id"] in STATUS_MOVES
        ]

    def egg_moves(self, pokemon_id: int) -> list[int]:
        key = f"egg-moves-v1/{pokemon_id}"
        cached = self._store.cached(key)
        if cached is not None:
            return cached
        data = egg_moves_from(_get_json(f"{API_BASE}/pokemon/{pokemon_id}"))
        self._store.cache(key, data)
        return data

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
        """The move's battle data; `ailment` is one of the simulated statuses and other secondary effects are dropped.
        A move whose `data/battle/moves.json` entry fills meta PokéAPI lacks (`args.meta`) is read from there."""
        if "meta" in battle_data.table("moves").get(str(move_id), {}).get("args", {}):
            return data_move(move_id)
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


def _forms_of(member: dict) -> list[tuple[str, int]]:
    """The form `/pokemon` ids `combatant()` reads for the member, as ("pokemon" | "mega", id)."""
    pokemon_id = member["pokemon_id"]
    item = tera_forms.usable_item(member.get("held_item"), pokemon_id)
    forms = []
    if pokemon_id == tera_forms.TERAPAGOS:
        forms.append(("pokemon", tera_forms.TERASTAL_FORM))
    if item in tera_forms.MASKS and tera_forms.MASKS[item][0] is not None:
        forms.append(("pokemon", tera_forms.MASKS[item][0]))
    if item == items.STELLAR_CRYSTAL:
        forms.append(("pokemon", tera_forms.STELLAR_FORM))
    if item in tera_forms.ITEM_FORMS:
        forms.append(("mega", tera_forms.ITEM_FORMS[item][1]))
    mega = mega_form_id(item, pokemon_id) or move_mega_form_id(pokemon_id, tuple(member.get("moves") or ()), item)
    if mega is not None:
        forms.append(("mega", mega))
    return forms


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


def egg_moves_from(pokemon: dict) -> list[int]:
    """The egg move ids of the version group `learnset_from` picks, by id."""
    groups: dict[tuple[bool, int], set[str]] = {}
    for entry in pokemon["moves"]:
        for detail in entry["version_group_details"]:
            group = detail["version_group"]
            rank = (group["name"] not in _SIDE_VERSION_GROUPS, _id_from_url(group["url"]))
            groups.setdefault(rank, set()).add(detail["move_learn_method"]["name"])
    ranked = [rank for rank, methods in groups.items() if "level-up" in methods]
    if not ranked:
        return []
    newest = max(ranked)
    return sorted({
        _id_from_url(entry["move"]["url"]) for entry in pokemon["moves"] for detail in entry["version_group_details"]
        if detail["move_learn_method"]["name"] == "egg"
        and (detail["version_group"]["name"] not in _SIDE_VERSION_GROUPS, _id_from_url(detail["version_group"]["url"])) == newest
    })


def status_move_entries(learnset: list[dict], level: int, machine_ids: Collection[int] | None,
                        eggs: Sequence[Collection[int]]) -> list[dict]:
    """The battle's status moves a Pokémon may use: by level-up at or below `level` or by machine (as for attacking
    moves), or as an egg move of the Pokémon or any species it evolved from (`eggs`). Learnset entries, by id.
    A move learnable several ways keeps the first of level-up, egg, machine."""
    found: dict[int, dict] = {}
    for entry in learnset:
        if entry["move_id"] in STATUS_MOVES and entry["source"] == "level" and entry["level"] <= level:
            found.setdefault(entry["move_id"], entry)
    for move_id in sorted({move_id for listed in eggs for move_id in listed if move_id in STATUS_MOVES}):
        found.setdefault(move_id, {"move_id": move_id, "level": 0, "source": "egg"})
    for entry in learnset:
        if entry["move_id"] in STATUS_MOVES and entry["source"] == "machine" and (
            machine_ids is None or entry["move_id"] in machine_ids
        ):
            found.setdefault(entry["move_id"], entry)
    return [found[move_id] for move_id in sorted(found)]


def _ancestors(pokemon_id: int) -> list[int]:
    from ypoke.gyms import species_table

    table = species_table()
    found = []
    while pokemon_id in table and table[pokemon_id].parent:
        pokemon_id = table[pokemon_id].parent
        found.append(pokemon_id)
    return found


def move_from(move: dict) -> dict:
    """Normalize a `/move/{id}` body. Stat changes count only for damaging moves that lower the target or change the user.

    `drain` is a percent of the damage dealt: positive heals the user, negative is recoil. PokéAPI has no badly-poisoned ailment, so the toxic moves are listed by id.
    """
    names = {entry["language"]["name"]: entry["name"] for entry in move["names"]}
    meta = move.get("meta") or {}
    changes = [(_STAT_KEYS[entry["stat"]["name"]], entry["change"]) for entry in move.get("stat_changes", [])
               if entry["stat"]["name"] in _BATTLE_STAT_KEYS]
    flat = {**meta, "ailment": (meta.get("ailment") or {}).get("name"),
            "category": (meta.get("category") or {}).get("name")}
    return _battle_move(move["id"], names.get("ko") or names.get("en") or move["name"], move["type"]["name"],
                        move["damage_class"]["name"], move, flat, changes)


def data_move(move_id: int) -> dict:
    """`move_from` for a move read from `data/battle/moves.json`. Its `args.meta` fills what PokéAPI leaves out (the
    Gen 9 moves' meta, an accuracy drop)."""
    entry = battle_data.table("moves")[str(move_id)]
    meta = merged_meta(entry)
    changes = [(key, change) for key, change in meta["stat_changes"] if key != "hp"]
    return _battle_move(move_id, entry["names"].get("ko") or entry["names"]["en"], entry["type"], entry["class"],
                        entry, meta, changes)


def merged_meta(entry: dict) -> dict:
    return {**entry["meta"], **entry.get("args", {}).get("meta", {})}


def _battle_move(move_id: int, name: str, kind: str, damage_class: str, move: dict, meta: dict,
                 changes: list[tuple[str, int]]) -> dict:
    """`move` holds the power, accuracy, priority and PP; `meta` the flat PokéAPI meta with `ailment` and `category`
    as names."""
    ailment = "toxic" if meta.get("ailment") == "poison" and move_id in _TOXIC_MOVE_IDS else meta.get("ailment")
    category = meta.get("category")
    stat_changes = [{"stat": key, "change": change} for key, change in changes if category in _STAT_CATEGORIES]
    return {
        "id": move_id,
        "name": name,
        "type": kind,
        "power": move["power"] or 0,
        "damage_class": damage_class,
        "accuracy": move["accuracy"],
        "priority": move["priority"],
        "pp": move["pp"] or 1,
        "crit_rate": meta.get("crit_rate") or 0,
        "ailment": ailment if ailment in _AILMENTS else None,
        "ailment_chance": (meta.get("ailment_chance") or 0) if ailment in _AILMENTS else 0,
        "stat_changes": stat_changes,
        "stat_target": _STAT_CATEGORIES.get(category, "target"),
        "stat_chance": (meta.get("stat_chance") or 0) if stat_changes else 0,
        "weather": WEATHER_MOVES.get(move_id),
        "always_hits_in": _ALWAYS_HITS_IN.get(move_id, []),
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
