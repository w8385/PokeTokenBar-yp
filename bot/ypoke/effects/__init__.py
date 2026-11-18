"""The effect registry: every effect key of `data/battle/*.json` has exactly one handler, and `effects.hooks` runs the
handlers at the battle's hook points (`hooks.HOOKS`, in the order a turn reaches them)."""

from ypoke import battle_data

REGISTRY: dict[str, dict[str, "Handler"]] = {kind: {} for kind in battle_data.KINDS}


class Handler:
    """The behavior of one effect key. A subclass defines the hooks it needs (`hooks.HOOKS`); each hook gets the
    ability or item slug, or the `battle.Move`, first. `by_id` marks a move key found by the move's id rather than by
    a `Move` field. A key that acts outside the battle loop has no hook and says where in `elsewhere`."""

    kind = ""
    key = ""
    by_id = False
    elsewhere = ""


def elsewhere(kind: str, where: str, *keys: str) -> None:
    register(kind, *keys)(type("Elsewhere", (Handler,), {"elsewhere": where}))


def register(kind: str, *keys: str):
    """Class decorator: one instance of the class handles each of `keys`."""
    def add(cls):
        for key in keys:
            if key in REGISTRY[kind]:
                raise ValueError(f"{kind} effect key {key} already has a handler")
            handler = cls()
            handler.kind, handler.key = kind, key
            REGISTRY[kind][key] = handler
        return cls
    return add


def keys(kind: str) -> frozenset[str]:
    return frozenset(loaded()[kind])


def problems(data: dict | None = None) -> list[str]:
    """Why the registry and the data disagree, empty when they match: a key with no handler, a handler no entry names,
    a handler with neither a hook nor `elsewhere`, a method that is no hook, two keys of one entry on the same hook."""
    from ypoke.effects import hooks

    registry = loaded()
    data = data or {kind: battle_data.table(kind) for kind in battle_data.KINDS}
    found = []
    for kind, entries in data.items():
        used = {key for entry in entries.values() for key in battle_data.keys(entry)}
        found += [f"{kind}: effect key {key} has no handler" for key in sorted(used - set(registry[kind]))]
        found += [f"{kind}: handler {key} is named by no entry" for key in sorted(set(registry[kind]) - used)]
        for key, handler in sorted(registry[kind].items()):
            names = hook_names(handler)
            if not names and not handler.elsewhere:
                found.append(f"{kind}: handler {key} has no hook")
            found += [f"{kind}: handler {key} method {name} is not a hook" for name in names if name not in hooks.HOOKS]
        for name, entry in entries.items():
            hooked = [hook for key in battle_data.keys(entry) if key in registry[kind]
                      for hook in hook_names(registry[kind][key])]
            found += [f"{kind} {name}: two keys run {hook}" for hook in sorted(set(hooked)) if hooked.count(hook) > 1]
    return found


def loaded() -> dict[str, dict[str, Handler]]:
    """The registry once every handler module has registered. They import `battle`, which needs the modules that
    import `effects.hooks`, so they load on first use rather than with this package."""
    from ypoke.effects import (  # noqa: F401
        abilities, callers, changers, conditions, field, healing, item_moves, items, moves, protection, secondary, stats,
        switching, volatiles,
    )

    return REGISTRY


def hook_names(handler: Handler) -> tuple[str, ...]:
    """The public methods the handler's classes define below `Handler`: the hooks it runs."""
    names = []
    for cls in type(handler).__mro__:
        if cls is Handler:
            break
        names += [name for name, value in vars(cls).items() if callable(value) and not name.startswith("_")]
    return tuple(dict.fromkeys(names))
