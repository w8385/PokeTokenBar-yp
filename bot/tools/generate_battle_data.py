"""Regenerate `data/battle/{items,abilities,moves}.json` from PokéAPI: names, PokéAPI summaries and move stats.

Run from `bot/`: `python3 tools/generate_battle_data.py <cache.db>`. The cache is a scratch SQLite file (never the bot's
database); a rerun reads PokéAPI bodies from it. Hand-set fields (`HAND_FIELDS`) of an existing entry are kept as they
are; a new entry gets an effect from `_default_effect` (inert by rule, plain damage by rule, else "todo").

PokéAPI has no contact flag. `python3 tools/generate_battle_data.py --showdown-contact <moves.ts>` sets the "contact"
flag of every move from Pokémon Showdown's `data/moves.ts` (`flags.contact`, MIT, `data/battle/LICENSE-showdown`) at
`SHOWDOWN_COMMIT`, matching Showdown's `num` to the move id.
"""

import json
import re
import sys
import time
import urllib.error
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ypoke import battle_data, pokeapi  # noqa: E402
from ypoke.store import Store  # noqa: E402

HAND_FIELDS = ("effect", "args", "flags", "note", "bot_name", "pokeapi", "names_extra")
SHOWDOWN_COMMIT = "5b88c476113d51a939bddbcd00b5cd182a5d8058"
SHOWDOWN_ENTRY = re.compile(r"\n\t[a-z0-9]+: \{\n(.*?)\n\t\},?(?=\n)", re.DOTALL)
FETCH_WORKERS = 4
FETCH_ATTEMPTS = 5
LANGUAGES = {"ko": ("ko",), "en": ("en",), "ja": ("ja-hrkt", "ja"), "es": ("es",), "fr": ("fr",), "de": ("de",),
             "pt": ("pt-br",), "ru": ("ru",)}
HOLDABLE_ATTRIBUTES = ("holdable", "holdable-active", "holdable-passive")
HELD_CATEGORIES = (
    "held-items", "choice", "effort-training", "bad-held-items", "training", "plates", "species-specific",
    "type-enhancement", "scarves", "jewels", "mega-stones", "memories", "z-crystals", "medicine", "other", "in-a-pinch",
    "picky-healing", "type-protection", "evolution",
)
# Items the app sells that no category above lists; the app's item text takes their names from here.
APP_ITEMS = (
    "shiny-charm", "auspicious-armor", "galarica-cuff", "galarica-wreath", "scroll-of-darkness", "scroll-of-waters",
    "ability-capsule", "ability-patch", "bottle-cap", "gold-bottle-cap", "reveal-glass", "dna-splicers",
    "reins-of-unity",
)
INERT_ITEM_CATEGORIES = {
    "z-crystals": "Z-Crystal: Z-Moves are not in this format",
    "scarves": "contest scarf: no battle effect",
    "healing": "medicine: no effect while held",
    "pp-recovery": "medicine: no effect while held",
    "revival": "medicine: no effect while held",
    "status-cures": "medicine: no effect while held",
    "vitamins": "medicine: no effect while held",
    "special-balls": "Poké Ball: no effect while held",
    "standard-balls": "Poké Ball: no effect while held",
    "stat-boosts": "bag item used by a trainer: no effect while held",
    "flutes": "flute: no effect while held",
    "spelunking": "field item: no effect while held",
    "evolution": "evolution item: no effect while held",
    "collectibles": "collectible: no effect while held",
    "loot": "valuable: no effect while held",
    "gameplay": "key item: no effect while held",
    "plot-advancement": "key item: no effect while held",
    "picnic": "picnic item: no effect while held",
}
NOT_LEARNABLE = "no Pokémon learns it (Z-Move, Max Move or shadow move): not in this format"
NOT_MAIN_SERIES = "Pokémon Conquest ability: not in the main series"
PLAIN_DAMAGE_CATEGORIES = ("damage", "damage-ailment", "damage-lower", "damage-raise", "damage-heal")
SIMULATED_AILMENTS = ("burn", "paralysis", "poison", "sleep", "freeze", "confusion")
# PokéAPI short effects (unfilled) whose whole Gen 9 singles effect is damage plus the meta fields the battle reads:
# stat change, ailment, drain, recoil, hits, crit rate, priority. Doubles-only and money parts count as nothing.
PLAIN_DAMAGE_SUMMARIES = frozenset({
    "Inflicts regular damage with no additional effect.",
    "Inflicts regular damage.",
    "Has an increased chance for a critical hit.",
    "Always scores a critical hit.",
    "Hits three times. Always scores a critical hit.",
    "Hits 2-5 times in one turn.",
    "Hits 2–5 times.",
    "Hits twice in one turn.",
    "Hits twice in one turn. In Double Battles, this move will hit both enemy targets. If it would fail to hit one of "
    "the targets, the other target will be hit twice.",
    "Never misses.",
    "User receives 1/4 the damage it inflicts in recoil.",
    "User receives 1/3 the damage inflicted in recoil.",
    "User receives 1/2 the damage inflicted in recoil.",
    "Scatters money on the ground worth five times the user’s level.",
    "Deals splash damage to Pokémon next to the target.",
    "Has double power if it’s used more than once per turn.",
    "Damages opponents, but heals allies for 50% of their max HP.",
    "With Grass Pledge, halves opposing Pokémon’s Speed for four turns.",
    "With Water Pledge, doubles the effect chance of friendly Pokémon’s moves for four turns.",
    "With Fire Pledge, damages opposing Pokémon for 1/8 their max HP every turn for four turns.",
    "Deals twice the damage if the target is Dynamaxed.",
    "The user ignores the effects of opposing Pokémon's moves and Abilities that draw in moves, allowing this move to "
    "hit the chosen target.",
    "Has a chance to burn the target.",
    "Has a chance to paralyze the target.",
    "Has a chance to poison the target.",
    "Has a chance to freeze the target.",
    "Has a chance to confuse the target.",
    "Has a chance to badly poison the target.",
    "Has an increased chance for a critical hit and a chance to poison the target.",
    "Has an increased chance for a critical hit and a chance to burn the target.",
    "Hits twice in the same turn. Has a chance to poison the target.",
    "User takes 1/3 the damage inflicted in recoil. Has a chance to paralyze the target.",
    "User takes 1/3 the damage inflicted in recoil. Has a chance to burn the target.",
    "Drains half the damage inflicted to heal the user.",
    "Drains 75% of the damage inflicted to heal the user.",
    "Heals the user for half the total damage dealt to all targets.",
    "Has a chance to lower the target’s Attack by one stage.",
    "Has a chance to lower the target’s Defense by one stage.",
    "Has a chance to lower the target’s Special Attack by one stage.",
    "Has a chance to lower the target’s Special Defense by one stage.",
    "Has a chance to lower the target’s Special Defense by two stages.",
    "Has a chance to lower the target’s Speed by one stage.",
    "Lowers the target’s Attack by one stage after inflicting damage.",
    "Lowers the target’s Defense by one stage after inflicting damage.",
    "Lowers the target’s Speed by one stage.",
    "Lowers the target’s Special Attack by one stage.",
    "Lowers the target’s Special Defense by two stages.",
    "Lower the targets Special Defense by 1 stage.",
    "Has a chance to raise the user’s Attack by one stage.",
    "Has a chance to raise the user’s Defense by one stage.",
    "Has a chance to raise the user’s Defense by two stages for each target hit.",
    "Has a chance to raise the user’s Special Attack by one stage.",
    "Has a chance to raise all of the user’s stats by one stage.",
    "Raises the user’s Attack by one stage after inflicting damage.",
    "Inflicts regular damage. Raises the user’s Speed by one stage.",
    "Lowers the user’s Special Attack by two stages after inflicting damage.",
    "Lowers the user’s Attack and Defense by one stage after inflicting damage.",
    "Lowers the user’s Defense by one stage after inflicting damage.",
    "Lowers the user’s Defense and Special Defense by one stage after inflicting damage.",
    "Lowers the user’s Defense, Special Defense, and Speed by one stage each.",
    "Lowers user’s Speed by one stage.",
})


def main() -> None:
    if sys.argv[1] == "--showdown-contact":
        _set_contact(Path(sys.argv[2]).read_text())
        return
    store = Store(sys.argv[1])
    for kind, build in (("items", _items), ("abilities", _abilities), ("moves", _moves)):
        old = battle_data.read(kind) if battle_data.path(kind).exists() else {}
        fresh = build(store, old)
        battle_data.write(kind, {key: _merged(fresh[key], old.get(key)) for key in fresh})
        print(f"{kind}: {len(fresh)} entries", file=sys.stderr)


def _set_contact(showdown_moves: str) -> None:
    contact = _showdown_contact(showdown_moves)
    moves = battle_data.read("moves")
    for move_id, entry in moves.items():
        flags = [flag for flag in entry.get("flags", ()) if flag != "contact"]
        flags += ["contact"] if int(move_id) in contact else []
        if flags:
            entry["flags"] = flags
        else:
            entry.pop("flags", None)
    battle_data.write("moves", moves)
    print(f"moves: {sum(int(move_id) in contact for move_id in moves)} make contact", file=sys.stderr)


def _showdown_contact(showdown_moves: str) -> set[int]:
    """The move ids (Showdown `num`) whose `flags` have `contact`."""
    contact = set()
    for body in SHOWDOWN_ENTRY.findall(showdown_moves):
        num = re.search(r"^\t\tnum: (\d+),", body, re.MULTILINE)
        flags = re.search(r"^\t\tflags: \{([^}]*)\}", body, re.MULTILINE)
        if num and flags and re.search(r"\bcontact: 1\b", flags.group(1)):
            contact.add(int(num.group(1)))
    return contact


def _merged(fresh: dict, old: dict | None) -> dict:
    """The regenerated entry with the old entry's hand-set fields, which win over any default."""
    if old is None:
        return fresh
    kept = {**fresh, **{field: old[field] for field in HAND_FIELDS if field in old}}
    if old.get("pokeapi", "") is None:
        kept["names"] = old.get("names", {})
    return kept


def _items(store: Store, old: dict) -> dict:
    slugs = {entry["name"] for attribute in HOLDABLE_ATTRIBUTES
             for entry in _get(store, f"item-attribute/{attribute}")["items"]}
    slugs |= {entry["name"] for category in HELD_CATEGORIES
              for entry in _get(store, f"item-category/{category}")["items"] if not entry["name"].endswith("--bag")}
    slugs |= set(APP_ITEMS)
    by_slug = {slug: slug for slug in slugs}
    by_slug |= {slug: entry.get("pokeapi", slug) for slug, entry in old.items()}
    bodies = _fetch_all(store, [f"item/{source}" for source in by_slug.values() if source is not None])
    entries = {}
    for slug, source in sorted(by_slug.items()):
        if source is None:
            entries[slug] = {"names": old[slug]["names"], "effect": "todo"}
            continue
        body = bodies[f"item/{source}"]
        if body is None:
            continue
        category = body["category"]["name"]
        entry = {"names": _names(body), "category": category, "summary": _summary(body)}
        entries[slug] = {**entry, "effect": _default_item_effect(category)}
    return entries


def _abilities(store: Store, old: dict) -> dict:
    listed = [entry["name"] for entry in _get(store, "ability?limit=2000")["results"]]
    bodies = _fetch_all(store, [f"ability/{slug}" for slug in listed])
    entries = {}
    for slug in sorted(listed):
        body = bodies[f"ability/{slug}"]
        if body is None:
            continue
        effect = "todo" if body["is_main_series"] else {"inert": NOT_MAIN_SERIES}
        entries[slug] = {"names": _names(body), "summary": _summary(body), "effect": effect}
    return entries


def _moves(store: Store, old: dict) -> dict:
    listed = [entry["url"] for entry in _get(store, "move?limit=3000")["results"]]
    bodies = _fetch_all(store, [f"move/{_id_of(url)}" for url in listed])
    entries = {}
    for move_id in sorted(_id_of(url) for url in listed):
        body = bodies[f"move/{move_id}"]
        if body is None:
            continue
        entries[str(move_id)] = {**_move_stats(body), "effect": _default_move_effect(body)}
    return entries


def _move_stats(body: dict) -> dict:
    normalized = pokeapi.move_from(body)
    meta = body.get("meta") or {}
    return {
        "slug": body["name"], "names": _names(body), "summary": _summary(body), "type": body["type"]["name"],
        "class": body["damage_class"]["name"], "power": body["power"], "accuracy": body["accuracy"],
        "priority": body["priority"], "pp": body["pp"],
        "meta": {
            "category": (meta.get("category") or {}).get("name"),
            "ailment": (meta.get("ailment") or {}).get("name"), "ailment_chance": meta.get("ailment_chance") or 0,
            "flinch_chance": meta.get("flinch_chance") or 0, "crit_rate": normalized["crit_rate"],
            "drain": normalized["drain"], "healing": meta.get("healing") or 0,
            "min_hits": normalized["min_hits"], "max_hits": normalized["max_hits"],
            "stat_changes": [[change["stat"], change["change"]] for change in normalized["stat_changes"]],
            "stat_target": normalized["stat_target"], "stat_chance": normalized["stat_chance"],
        },
    }


def _default_item_effect(category: str) -> str | dict:
    reason = INERT_ITEM_CATEGORIES.get(category)
    return {"inert": reason} if reason else "todo"


def _default_move_effect(body: dict) -> str | dict:
    """Inert when nothing learns it; plain damage when PokéAPI's meta says all the move does and the battle reads it."""
    if not body.get("learned_by_pokemon"):
        return {"inert": NOT_LEARNABLE}
    meta = body.get("meta") or {}
    ailment = (meta.get("ailment") or {}).get("name") or "none"
    plain = (body["damage_class"]["name"] != "status" and body["power"]
             and (meta.get("category") or {}).get("name") in PLAIN_DAMAGE_CATEGORIES
             and not meta.get("flinch_chance") and not meta.get("healing")
             and (ailment == "none" or ailment in SIMULATED_AILMENTS)
             and _summary(body, filled=False) in PLAIN_DAMAGE_SUMMARIES)
    return "damage" if plain else "todo"


def _names(body: dict) -> dict:
    by_code = {entry["language"]["name"].lower(): entry["name"].strip() for entry in body.get("names", [])}
    names = {}
    for language, codes in LANGUAGES.items():
        name = next((by_code[code] for code in codes if by_code.get(code)), None)
        if name:
            names[language] = name
    return names


def _summary(body: dict, filled: bool = True) -> str:
    """PokéAPI's English short effect, with the effect chance filled in unless not `filled`."""
    text = next((entry["short_effect"] for entry in body.get("effect_entries", [])
                 if entry["language"]["name"] == "en"), "")
    if text.startswith("XXX"):
        return ""
    chance = body.get("effect_chance")
    if not filled:
        return " ".join(text.split())
    return " ".join(text.replace("$effect_chance", str(chance) if chance is not None else "?").split())


def _fetch_all(store: Store, paths: list[str]) -> dict[str, dict]:
    with ThreadPoolExecutor(max_workers=FETCH_WORKERS) as pool:
        return dict(zip(paths, pool.map(lambda path: _get(store, path), paths)))


def _get(store: Store, path: str) -> dict | None:
    """The PokéAPI body at `path`, None when PokéAPI lists it but has no such resource."""
    key = f"raw-v1/{path}"
    cached = store.cached(key)
    if cached is not None:
        return cached
    for attempt in range(1, FETCH_ATTEMPTS + 1):
        try:
            body = pokeapi._get_json(f"{pokeapi.API_BASE}/{path}")
            break
        except urllib.error.HTTPError as error:
            if error.code == 404:
                print(f"missing in PokéAPI: {path}", file=sys.stderr)
                return None
            raise
        except urllib.error.URLError:
            if attempt == FETCH_ATTEMPTS:
                raise
            time.sleep(attempt)
    store.cache(key, body)
    return body


def _id_of(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[-1])


if __name__ == "__main__":
    main()
