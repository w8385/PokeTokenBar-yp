"""The `lineup` remote op: the whole battle lineup a player set in Slack, in order, with each member's moves and held
item. Payload: `{"members": [{"id", "pokemon_id", "name", "moves", "machine", "item"}]}` (`item` is an inventory key
or null, `moves` empty for the level defaults). Contract: bot/API.md "Remote ops"."""

from collections import Counter
from dataclasses import replace

from ypoke import entry_rules
from ypoke.remote_ops import OpKind, View, register
from ypoke.tera_forms import usable_item

LINEUP = "lineup"
MAX_MEMBERS = 6
MACHINE_PREFIX = "tm:"
GONE = "gone"
EVOLVED = "evolved"
NO_ITEM = "no_item"
NO_MACHINE = "no_machine"
NOT_LEARNABLE = "not_learnable"
SPECIES_CLAUSE = "species_clause"
ITEM_CLAUSE = "item_clause"
TRADE_LOCKED = "trade_locked"
INVALID = "invalid"
REASONS = {
    GONE: "고른 포켓몬이 이제 없어요(놓아주기·교환)",
    EVOLVED: "포켓몬이 진화하거나 모습이 바뀌었어요",
    NO_ITEM: "지닐 도구가 가방에 없어요",
    NO_MACHINE: "고른 기술의 기술머신이 가방에 없어요",
    NOT_LEARNABLE: "고른 기술을 이제 배울 수 없어요",
    SPECIES_CLAUSE: "같은 포켓몬이 둘 나가게 돼요",
    ITEM_CLAUSE: "같은 도구를 두 마리가 들게 돼요",
    TRADE_LOCKED: "교환에 올린 포켓몬이에요",
    INVALID: "라인업을 읽지 못했어요",
}


def describe(payload: dict) -> str:
    names = [member.get("name") or f"#{member.get('pokemon_id')}" for member in payload.get("members", [])]
    return f"대결 라인업 바꾸기: {' · '.join(names)}"


def _replay(view: View, payload: dict) -> View:
    return set_lineup(view, payload)[0]


def set_lineup(view: View, payload: dict) -> tuple[View, str | None]:
    """The view with the payload's lineup and the bag after the item moves, and None; or the view unchanged and the
    reason code the app would cancel it with. Members leaving the lineup keep their items, as in the app."""
    targets = payload.get("members")
    if not _well_formed(targets):
        return view, INVALID
    owned = {member["id"]: member for member in [*view.party, *view.bench] if "id" in member}
    if any(target["id"] not in owned for target in targets):
        return view, GONE
    if any(owned[target["id"]]["pokemon_id"] != target["pokemon_id"] for target in targets):
        return view, EVOLVED
    machines = {int(line["key"].removeprefix(MACHINE_PREFIX)) for line in view.bag
                if line["key"].startswith(MACHINE_PREFIX) and line["key"].removeprefix(MACHINE_PREFIX).isdigit()}
    if any(move_id not in machines for target in targets for move_id in target["machine"]):
        return view, NO_MACHINE
    items = _known_items(view, owned)
    bag = Counter({line["key"]: line["count"] for line in view.bag})
    changing = [(owned[target["id"]], target) for target in targets if owned[target["id"]].get("item_key") != target["item"]]
    for member, _ in changing:
        if member.get("item_key"):
            bag[member["item_key"]] += 1
    for _, target in changing:
        if target["item"] is not None:
            bag[target["item"]] -= 1
            if bag[target["item"]] < 0 or target["item"] not in items:
                return view, NO_ITEM
    party = [_member(owned[target["id"]], target, items) for target in targets]
    reason = rule_break(party)
    if reason:
        return view, reason
    chosen = {target["id"] for target in targets}
    bench = [member for member in owned.values() if member["id"] not in chosen]
    return replace(view, party=party, bench=bench, bag=_bag_lines(view.bag, bag, items)), None


def rule_break(party: list[dict]) -> str | None:
    """The clause the lineup breaks, as the app counts them: one Pokémon per species, one holder per item, where a
    species-bound item counts only on its own species."""
    species = [entry_rules.species_id(member["pokemon_id"]) for member in party]
    if len(set(species)) != len(species):
        return SPECIES_CLAUSE
    held = [item for member in party if (item := _counted_item(member))]
    return ITEM_CLAUSE if len(set(held)) != len(held) else None


def _counted_item(member: dict) -> str | None:
    slug = member.get("held_item")
    if slug and usable_item(slug, member["pokemon_id"]) is None:
        return None
    return member.get("item_key") or slug


def _well_formed(targets: object) -> bool:
    if not isinstance(targets, list) or not 1 <= len(targets) <= MAX_MEMBERS:
        return False
    for target in targets:
        if not (isinstance(target, dict) and isinstance(target.get("id"), str) and isinstance(target.get("pokemon_id"), int)
                and isinstance(target.get("moves"), list) and isinstance(target.get("machine"), list)
                and (target.get("item") is None or isinstance(target.get("item"), str))):
            return False
    return len({target["id"] for target in targets}) == len(targets)


def _known_items(view: View, owned: dict[str, dict]) -> dict[str, dict]:
    """Inventory key -> `{"name", "held_item"}` of every item that can be held: the bag's and the ones on Pokémon."""
    items: dict[str, dict] = {}
    sources = [(member["item_key"], member["item_name"], member.get("held_item"))
               for member in owned.values() if member.get("item_key")]
    sources += [(line["key"], line["name"], line.get("held_item")) for line in view.bag if line.get("equip")]
    for key, name, slug in sources:
        items[key] = {"name": name, "held_item": slug or items.get(key, {}).get("held_item")}
    return items


def _member(member: dict, target: dict, items: dict[str, dict]) -> dict:
    item_fields = ("held_item", "item_key", "item_name")
    keeps_item = member.get("item_key") == target["item"]
    changed = {key: value for key, value in member.items()
               if key not in ("moves", "machine") and (keeps_item or key not in item_fields)}
    if target["moves"]:
        changed["moves"] = list(target["moves"])
        if target["machine"]:
            changed["machine"] = [move_id for move_id in target["moves"] if move_id in target["machine"]]
    if not keeps_item and target["item"] is not None:
        item = items[target["item"]]
        changed |= {"item_key": target["item"], "item_name": item["name"]}
        if item["held_item"]:
            changed["held_item"] = item["held_item"]
    return changed


def _bag_lines(lines: list[dict], counts: Counter, items: dict[str, dict]) -> list[dict]:
    kept = [{**line, "count": counts[line["key"]]} for line in lines if counts[line["key"]] > 0]
    listed = {line["key"] for line in lines}
    for key, count in counts.items():
        if key not in listed and count > 0:
            line = {"key": key, "name": items[key]["name"], "count": count, "equip": True}
            if items[key]["held_item"]:
                line["held_item"] = items[key]["held_item"]
            kept.append(line)
    return kept


register(OpKind(LINEUP, describe, _replay, reasons=REASONS, supersedes=True))
