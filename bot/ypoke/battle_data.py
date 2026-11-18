"""The battle rule data in `data/battle/` (see its README): items, abilities and moves with their effect keys.

An entry's `effect` is a key, a list of keys, `"todo"` or `{"inert": "<reason>"}`. A list may hold `"todo"` next to
keys when part of the entry's Gen 9 effect is still missing.
"""

import json
from functools import cache
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "battle"
KINDS = ("items", "abilities", "moves")
TODO = "todo"


def bot_names(kind: str, unless: str | None = None) -> dict[str, str]:
    """The Korean name the bot shows for every entry that runs a key, except the entries that run `unless`."""
    return {name: entry.get("bot_name") or entry["names"]["ko"] for name, entry in table(kind).items()
            if keys(entry) and unless not in keys(entry)}


def ids(kind: str, key: str) -> frozenset:
    return frozenset(with_key(kind, key))


def args(kind: str, key: str, field: str) -> dict:
    """`{name: entry["args"][field]}` for the entries that run `key`, lists as tuples."""
    return {name: _frozen(entry["args"][field]) for name, entry in with_key(kind, key).items()}


def with_key(kind: str, key: str) -> dict:
    """The entries of `kind` that run `key`, in file order, by name (a move by its int id)."""
    return {int(name) if kind == "moves" else name: entry for name, entry in table(kind).items()
            if key in keys(entry)}


@cache
def table(kind: str) -> dict:
    return read(kind)


def read(kind: str) -> dict:
    return json.loads(path(kind).read_text())


def path(kind: str) -> Path:
    return DATA_DIR / f"{kind}.json"


def keys(entry: dict) -> tuple[str, ...]:
    """The effect keys the bot runs for the entry; `"todo"` is not one, and an inert entry has none."""
    effect = entry.get("effect", TODO)
    if isinstance(effect, dict):
        return ()
    listed = (effect,) if isinstance(effect, str) else tuple(effect)
    return tuple(key for key in listed if key != TODO)


def is_inert(entry: dict) -> bool:
    return isinstance(entry.get("effect"), dict)


def is_todo(entry: dict) -> bool:
    effect = entry.get("effect", TODO)
    return effect == TODO or isinstance(effect, list) and TODO in effect


def write(kind: str, entries: dict) -> None:
    """One entry per line, in the given order, so a regeneration diffs line by line."""
    lines = [f"{json.dumps(key)}: {json.dumps(entry, ensure_ascii=False)}" for key, entry in entries.items()]
    path(kind).write_text("{\n" + ",\n".join(lines) + "\n}\n")


def _frozen(value):
    return tuple(value) if isinstance(value, list) else value
