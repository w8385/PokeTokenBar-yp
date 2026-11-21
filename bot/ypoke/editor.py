"""What the Slack editors (`/파티`, `/상점`, `/트레이닝`, `/교환`·`/미라클`) and the trade and Miracle cards share: a
control's value is parts joined by `|`, and each editor owns every action id under its prefix. A screen posted before
a release keeps working while its ids keep their prefix and its values the same parts."""

from dataclasses import dataclass

SEPARATOR = "|"


def join_value(*parts: str) -> str:
    return SEPARATOR.join(parts)


def split_value(value: str, parts: int = 2) -> tuple[str, ...]:
    """`value` cut at its first `parts - 1` separators, a missing part empty: `a` is (`a`, ``), `a|b|c` is (`a`, `b|c`)."""
    pieces = value.split(SEPARATOR, parts - 1)
    return (*pieces, *[""] * (parts - len(pieces)))


def pressed_value(action: dict) -> str:
    """The value a button press or a single-select pick sends."""
    return action.get("value") or (action.get("selected_option") or {}).get("value") or ""


def numbered(action_id: str, key: object) -> str:
    """One of several controls of one kind in an actions block, which takes each action id once."""
    return f"{action_id}_{key}"


def is_numbered(action_id: str, base: str) -> bool:
    """`action_id` is `base` itself (cards from before numbering) or one of its numbered copies."""
    return action_id == base or action_id.startswith(f"{base}_")


@dataclass(frozen=True)
class Route:
    """An editor's presses (every action id under `prefix`) and its typed-search menus: each an action id and the name
    of the editor method that answers it."""

    prefix: str
    editor: object
    menus: tuple[tuple[str, str], ...] = ()


def checked(routes: list[Route]) -> list[Route]:
    """`routes`, refused when a press could reach two editors or a menu is not its own editor's alone."""
    prefixes = [route.prefix for route in routes]
    for prefix in prefixes:
        if prefixes.count(prefix) > 1 or any(other != prefix and other.startswith(prefix) for other in prefixes):
            raise ValueError(f"action id prefix {prefix!r} overlaps another editor's")
    menus = [action_id for route in routes for action_id, _ in route.menus]
    for route in routes:
        for action_id, _ in route.menus:
            if not action_id.startswith(route.prefix) or menus.count(action_id) > 1:
                raise ValueError(f"menu {action_id!r} is not {route.prefix!r}'s alone")
    return routes


def route_for(routes: list[Route], action_id: str) -> Route | None:
    return next((route for route in routes if action_id.startswith(route.prefix)), None)
