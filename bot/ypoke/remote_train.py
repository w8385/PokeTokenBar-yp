"""The `train` remote op: one training-tab action on one owned Pokémon, made in Slack. Payload: `{"action", "id",
"pokemon_id", "name", …}` with the action's fields (`nature`, `stat`, `ability`, `form`, `moves`). Mint and Mirror Herb
come from the bag, else are bought at the shop price in `price` (null: the bag was to pay). Contract: bot/API.md
"The `train` op"."""

import copy as copying
from dataclasses import replace

from ypoke.remote_ops import OpKind, View, register
from ypoke.trades import NATURE_NAMES_KO

TRAIN = "train"
NATURE = "nature"
HERB = "herb"
CAPSULE = "capsule"
PATCH = "patch"
CAP = "cap"
GOLD_CAP = "gold_cap"
FORM = "form"
MOVES = "moves"
EVOLVE = "evolve"
ACTIONS = (NATURE, CAPSULE, PATCH, CAP, GOLD_CAP, HERB, FORM, MOVES, EVOLVE)
EVOLVE_ITEMS = {"linkingCord": "연결의끈"}
ITEM_KEYS = {NATURE: "mint", HERB: "mirrorHerb", CAPSULE: "abilityCapsule", PATCH: "abilityPatch", CAP: "bottleCap",
             GOLD_CAP: "goldBottleCap"}
BOUGHT = (NATURE, HERB)
STATS = {"hp": ("hp", "hp"), "attack": ("attack", "attack"), "defense": ("defense", "defense"),
         "special-attack": ("special_attack", "specialAttack"),
         "special-defense": ("special_defense", "specialDefense"), "speed": ("speed", "speed")}
STAT_NAMES = {"hp": "HP", "attack": "공격", "defense": "방어", "special-attack": "특수공격", "special-defense": "특수방어",
              "speed": "스피드"}
ACTION_NAMES = {NATURE: "민트", CAPSULE: "특성캡슐", PATCH: "특성패치", CAP: "은색병뚜껑", GOLD_CAP: "금색병뚜껑",
                HERB: "흉내허브", FORM: "폼 바꾸기", MOVES: "기술 바꾸기", EVOLVE: "연결의끈 진화"}
MAX_IV = 31
MAX_MOVES = 4
MACHINE_PREFIX = "tm:"
GONE = "gone"
EVOLVED = "evolved"
TRADE_LOCKED = "trade_locked"
NO_ITEM = "no_item"
NO_TOKENS = "no_tokens"
NOT_SOLD = "not_sold"
PRICE_CHANGED = "price_changed"
UNCHANGED = "unchanged"
NOT_APPLICABLE = "not_applicable"
NO_MACHINE = "no_machine"
NO_HERB = "no_herb"
NO_DATA = "no_data"
INVALID = "invalid"
WRONG_TARGET = "wrong_target"
NOT_READY = "not_ready"
EVERSTONE = "everstone"
REASONS = {
    GONE: "포켓몬이 이제 없어요(놓아주기·교환)",
    EVOLVED: "포켓몬이 진화하거나 모습이 바뀌었어요",
    TRADE_LOCKED: "교환에 올린 포켓몬이에요",
    NO_ITEM: "쓸 도구가 가방에 없어요",
    NO_TOKENS: "토큰이 모자라요",
    NOT_SOLD: "상점에서 팔지 않아요",
    PRICE_CHANGED: "값이 바뀌었어요",
    UNCHANGED: "이미 그 상태예요",
    NOT_APPLICABLE: "이 포켓몬에게는 이제 쓸 수 없어요",
    NO_MACHINE: "고른 기술의 기술머신이 가방에 없어요",
    NO_HERB: "알 기술은 흉내허브를 쓴 포켓몬만 배워요",
    NO_DATA: "앱이 포켓몬 정보를 불러오지 못했어요",
    INVALID: "트레이닝을 읽지 못했어요",
    WRONG_TARGET: "연결의끈으로 진화하지 않는 포켓몬이에요",
    NOT_READY: "진화에 필요한 지닌 도구나 친구가 없어요",
    EVERSTONE: "변함없는돌을 지니고 있어요",
}


def describe(payload: dict) -> str:
    action = payload.get("action")
    name = payload.get("name") or f"#{payload.get('pokemon_id')}"
    detail = ""
    if action == NATURE:
        detail = f" → {NATURE_NAMES_KO.get(payload.get('nature'), payload.get('nature'))}"
    elif action == CAP:
        detail = f" ({STAT_NAMES.get(payload.get('stat'), payload.get('stat'))})"
    elif action in (CAPSULE, PATCH):
        ability = payload.get("ability") or {}
        detail = f" → {ability.get('label') or ability.get('name')}"
    elif action == FORM:
        detail = f" → {payload.get('form_name') or payload.get('form')}"
    elif action == EVOLVE:
        detail = f" → {payload.get('to_name') or '#' + str(payload.get('to_pokemon_id'))}"
    cost = f" ({payload['price']:,}토큰)" if _is_int(payload.get("price")) else ""
    return f"트레이닝 {ACTION_NAMES.get(action, action)}: {name}{detail}{cost}"


def _replay(view: View, payload: dict) -> View:
    return train(view, payload)[0]


def train(view: View, payload: dict) -> tuple[View, str | None]:
    """The view with the action applied to every copy of the Pokémon (party, Box members and Box entries) and the bag
    or wallet paid, and None; or the view unchanged and the reason code the app would cancel it with."""
    action, individual_id, pokemon_id = payload.get("action"), payload.get("id"), payload.get("pokemon_id")
    if action not in ACTIONS or not isinstance(individual_id, str) or not _is_int(pokemon_id):
        return view, INVALID
    member = owned(view, individual_id)
    if member is None:
        locked = any(entry["id"] == individual_id for entry in view.pool)
        return view, TRADE_LOCKED if locked else GONE
    if member["pokemon_id"] != pokemon_id:
        return view, EVOLVED
    change, reason = _change(view, member, action, payload)
    if reason:
        return view, reason
    bag, wallet, reason = _pay(view, action, payload)
    if reason:
        return view, reason
    trained = replace(copying.deepcopy(view), bag=bag, wallet=wallet)
    for copy in _members(trained, individual_id):
        change(copy, None)
    for entry in trained.pool:
        if entry["id"] == individual_id:
            change(entry.get("member") or {}, entry)
    return trained, None


def owned(view: View, individual_id: str) -> dict | None:
    """The member the user may train: in the party, or in the Box and not tied up in a trade."""
    return next((member for member in [*view.party, *view.bench] if member.get("id") == individual_id), None)


def _change(view: View, member: dict, action: str, payload: dict):
    """A function that writes the action on a member copy (and its Box entry, when given), or the reason it can't."""
    if action == NATURE:
        nature = payload.get("nature")
        if nature not in NATURE_NAMES_KO:
            return None, INVALID
        if member.get("nature") == nature:
            return None, UNCHANGED
        return lambda copy, entry: _set_nature(copy, entry, nature), None
    if action == HERB:
        if member.get("mirror_herb"):
            return None, UNCHANGED
        if not member.get("egg_moves"):
            return None, NOT_APPLICABLE
        return _set_herb, None
    if action in (CAPSULE, PATCH):
        return _ability_change(view, member, action, payload)
    if action in (CAP, GOLD_CAP):
        stats = list(STATS) if action == GOLD_CAP else [payload.get("stat")]
        if any(stat not in STATS for stat in stats):
            return None, INVALID
        if item_count(view, ITEM_KEYS[action]) < 1:
            return None, NO_ITEM
        if all(member.get("ivs", {}).get(STATS[stat][0]) == MAX_IV for stat in stats):
            return None, UNCHANGED
        return lambda copy, entry: _max_ivs(copy, entry, stats), None
    if action == FORM:
        return _form_change(view, member, payload)
    if action == EVOLVE:
        return _evolve_change(member, payload)
    return _moves_change(view, member, payload)


def _evolve_change(member: dict, payload: dict):
    """The evolution the app offered for the member, with the held item it uses still on."""
    item, to = payload.get("item"), payload.get("to_pokemon_id")
    if item not in EVOLVE_ITEMS or not _is_int(to):
        return None, INVALID
    if member.get("held_item") == "everstone":
        return None, EVERSTONE
    evolution = member.get("evolution") or {}
    if (evolution.get("item"), evolution.get("pokemon_id")) != (item, to):
        return None, NOT_APPLICABLE
    if evolution.get("held_item") and member.get("held_item") != evolution["held_item"]:
        return None, NOT_APPLICABLE
    return lambda copy, entry: _evolve(copy, entry, evolution), None


def item_count(view: View, key: str) -> int:
    return sum(line["count"] for line in view.bag if line["key"] == key)


def _ability_change(view: View, member: dict, action: str, payload: dict):
    target = payload.get("ability")
    if not (isinstance(target, dict) and isinstance(target.get("name"), str) and _is_int(target.get("slot"))
            and isinstance(target.get("hidden"), bool)):
        return None, INVALID
    if item_count(view, ITEM_KEYS[action]) < 1:
        return None, NO_ITEM
    if not _is_int(member.get("ability_slot")) or form_ability(member):
        return None, NOT_APPLICABLE
    hidden = bool(member.get("ability_hidden"))
    if action == CAPSULE and (hidden or target["hidden"]):
        return None, NOT_APPLICABLE
    if (target["slot"], target["hidden"]) == (member["ability_slot"], hidden):
        return None, UNCHANGED
    return lambda copy, entry: _set_ability(copy, entry, target), None


def form_ability(member: dict) -> str | None:
    """The fixed ability of the member's current form, which no Capsule or Patch changes; None for its own."""
    return next((form["ability"] for form in member.get("forms", []) if form["pokemon_id"] == member["pokemon_id"]),
                None)


def _form_change(view: View, member: dict, payload: dict):
    form = next((form for form in member.get("forms", []) if form["form"] == payload.get("form")), None)
    if form is None or form["pokemon_id"] != payload.get("to_pokemon_id"):
        return None, NOT_APPLICABLE
    if item_count(view, member.get("form_tool", "")) < 1:
        return None, NO_ITEM
    if form["pokemon_id"] == member["pokemon_id"]:
        return None, UNCHANGED
    return lambda copy, entry: _set_form(copy, entry, form), None


def _moves_change(view: View, member: dict, payload: dict):
    moves, machine, egg = payload.get("moves"), payload.get("machine", []), payload.get("egg", [])
    if not (isinstance(moves, list) and isinstance(machine, list) and isinstance(egg, list)
            and len(moves) <= MAX_MOVES and all(_is_int(move_id) for move_id in moves)
            and len(set(moves)) == len(moves) and set(machine) <= set(moves) and set(egg) <= set(moves)):
        return None, INVALID
    if not set(machine) <= owned_machines(view):
        return None, NO_MACHINE
    if egg and not member.get("mirror_herb"):
        return None, NO_HERB
    return lambda copy, entry: _set_moves(copy, moves, machine), None


def owned_machines(view: View) -> set[int]:
    keys = [line["key"].removeprefix(MACHINE_PREFIX) for line in view.bag if line["key"].startswith(MACHINE_PREFIX)]
    return {int(key) for key in keys if key.isdigit()}


def _pay(view: View, action: str, payload: dict) -> tuple[list[dict], int | None, str | None]:
    """The bag and wallet after paying: one item from the bag, else (Mint, Mirror Herb) its shop price, which must be
    the price the player saw."""
    key = payload.get("item") if action == EVOLVE else ITEM_KEYS.get(action)
    if key is None:
        return view.bag, view.wallet, None
    if item_count(view, key) > 0:
        return _less_one(view.bag, key), view.wallet, None
    if action not in BOUGHT:
        return view.bag, view.wallet, NO_ITEM
    price, seen = shop_price(view, key), payload.get("price")
    if price is None:
        return view.bag, view.wallet, NOT_SOLD
    if not _is_int(seen):
        return view.bag, view.wallet, NO_ITEM
    if seen != price:
        return view.bag, view.wallet, PRICE_CHANGED
    if view.wallet is None or price > view.wallet:
        return view.bag, view.wallet, NO_TOKENS
    return view.bag, view.wallet - price, None


def shop_price(view: View, key: str) -> int | None:
    return next((line["price"] for line in view.shop if line["key"] == key), None)


def _less_one(bag: list[dict], key: str) -> list[dict]:
    lines = [{**line, "count": line["count"] - 1} if line["key"] == key else line for line in bag]
    return [line for line in lines if line["count"] > 0]


def _members(view: View, individual_id: str) -> list[dict]:
    return [member for member in [*view.party, *view.bench] if member.get("id") == individual_id]


def _set_nature(copy: dict, entry: dict | None, nature: str) -> None:
    copy["nature"] = nature
    if entry and isinstance(entry.get("entry"), dict):
        entry["entry"]["nature"] = nature


def _set_herb(copy: dict, entry: dict | None) -> None:
    copy["mirror_herb"] = True
    if (profile := _profile(entry)) is not None:
        profile["mirrorHerb"] = True


def _profile(entry: dict | None) -> dict | None:
    detail = entry.get("entry") if entry else None
    if not isinstance(detail, dict):
        return None
    if not isinstance(detail.get("profile"), dict):
        detail["profile"] = {}
    return detail["profile"]


def _set_ability(copy: dict, entry: dict | None, target: dict) -> None:
    copy["ability"] = target["name"]
    copy["ability_slot"] = target["slot"]
    if target["hidden"]:
        copy["ability_hidden"] = True
    else:
        copy.pop("ability_hidden", None)
    if "own_ability" in copy:
        copy["own_ability"] = target["name"]
    if (profile := _profile(entry)) is not None:
        profile.update({"abilitySlot": target["slot"], "abilityIsHidden": target["hidden"], "abilityName": target["name"]})


def _max_ivs(copy: dict, entry: dict | None, stats: list[str]) -> None:
    ivs = copy.setdefault("ivs", {})
    for stat in stats:
        ivs[STATS[stat][0]] = MAX_IV
    if (profile := _profile(entry)) is not None and isinstance(profile.get("ivs"), dict):
        for stat in stats:
            profile["ivs"][STATS[stat][1]] = MAX_IV


def _set_form(copy: dict, entry: dict | None, form: dict) -> None:
    """A form-tool change: the form's own ability, or (null) the individual's; moves chosen for the old form go."""
    copy["pokemon_id"] = form["pokemon_id"]
    copy["form"] = form["form"]
    if ability := form.get("ability") or copy.get("own_ability"):
        copy["ability"] = ability
    copy.pop("moves", None)
    copy.pop("machine", None)
    if entry:
        entry["pokemon_id"] = form["pokemon_id"]
        if isinstance(entry.get("entry"), dict):
            entry["entry"]["form"] = form["form"]


def _evolve(copy: dict, entry: dict | None, evolution: dict) -> None:
    """The evolved species keeps its ability until the app syncs; moves chosen for the old species go."""
    copy["pokemon_id"] = evolution["pokemon_id"]
    for key in ("moves", "machine", "evolution"):
        copy.pop(key, None)
    if evolution.get("held_item"):
        for key in ("held_item", "item_key", "item_name"):
            copy.pop(key, None)
    if entry:
        entry["pokemon_id"] = evolution["pokemon_id"]


def _set_moves(copy: dict, moves: list[int], machine: list[int]) -> None:
    copy.pop("machine", None)
    if not moves:
        copy.pop("moves", None)
        return
    copy["moves"] = list(moves)
    if machine:
        copy["machine"] = [move_id for move_id in moves if move_id in machine]


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


register(OpKind(TRAIN, describe, _replay, reasons=REASONS,
                changes=lambda payload: [payload["id"]] if isinstance(payload.get("id"), str) else []))
