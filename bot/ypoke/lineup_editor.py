"""The `/파티` lineup editor: per-slot menus and buttons that each queue one `lineup` op (`remote_lineup`) holding the
whole changed lineup, the moves screen, and the `/박스` button that puts a Box Pokémon in. Every value carries
individual ids, so a press on an older message still changes the Pokémon it names."""

from collections.abc import Callable
from dataclasses import dataclass

from ypoke.move_effects import STATUS_MOVES
from ypoke.remote_lineup import LINEUP, MACHINE_PREFIX, MAX_MEMBERS, REASONS, rule_break, set_lineup
from ypoke.remote_ops import RemoteOps, View
from ypoke.remote_views import PARTY_COMMAND, RemoteViews, Screen, box_screen, member_lines, party_title, sync_line
from ypoke.trades import OPTION_TEXT_LIMIT, PICKER_LIMIT, option_labels

ACTION_PREFIX = "lineup_"
SWAP_ACTION = "lineup_swap"
ORDER_ACTION = "lineup_order"
ITEM_ACTION = "lineup_item"
MOVES_ACTION = "lineup_moves"
SET_MOVES_ACTION = "lineup_set_moves"
DEFAULT_MOVES_ACTION = "lineup_default_moves"
BACK_ACTION = "lineup_back"
BOX_ADD_ACTION = "lineup_box_add"
ADD_SLOT = "+"
MAX_MOVES = 4
RULE_NOTE = "한 종에 한 마리, 같은 도구는 한 마리만 들 수 있어요. 규칙에 걸리는 포켓몬·도구는 목록에 없어요."
SYNC_NOTE = "바꾼 라인업은 동료의 `/대결`에 바로 쓰이고, 앱은 다음에 회사에서 동기화할 때 받아요."
MOVES_NOTE = "기술머신 기술은 가방에 있는 기술머신만, 알 기술은 미러허브를 쓴 포켓몬만 나와요."
STALE = "그새 파티가 바뀌었어요. `/파티`를 다시 열어 주세요."
NOT_EDITABLE = "지금 파티는 슬랙에서 바꿀 수 없어요. 앱에서 대결 포켓몬을 먼저 골라 주세요."
MOVES_UNAVAILABLE = "기술 목록을 불러오지 못했어요. 잠시 뒤 다시 해 주세요."
FULL_NO_SWAP = "파티의 누구와 바꿔도 같은 종·같은 도구 규칙에 걸려요."
MOVE_GROUPS = (("level", "레벨업"), ("egg", "알 기술"), ("machine", "기술머신"), ("status", "변화 기술"))
ORDER_WORDS = (("up", "위로"), ("down", "아래로"), ("drop", "빼기"))

MovesFor = Callable[..., list[dict]]


@dataclass(frozen=True)
class EditorReply:
    """`screen` replaces the message the action came from, or (`replace` False) is a private note under it."""

    screen: Screen
    replace: bool = True


class LineupEditor:
    """`moves_for` is `PokeAPIService.attacking_moves`; `species_name` names a `/pokemon` id in Korean."""

    def __init__(self, remote: RemoteOps, views: RemoteViews, moves_for: MovesFor, species_name: Callable[[int], str]):
        self._remote = remote
        self._views = views
        self._moves_for = moves_for
        self._species_name = species_name

    def handle(self, user_id: str, command: str, text: str) -> Screen:
        """`/파티` and `/박스` with the edit controls when the user's app applies lineup ops; the read-only screens
        otherwise."""
        view = self._remote.view(user_id)
        if view is None or not editable(view):
            return self._views.handle(user_id, command, text)
        if command == PARTY_COMMAND:
            return self._party(view)
        bench = {member["id"]: member for member in view.bench}
        return box_screen(view, text, lambda entry: _box_button(view, bench.get(entry["id"])))

    def act(self, user_id: str, action_id: str, value: str, selected: list[str]) -> EditorReply:
        """One press or pick; `value` is the action's value (the block id for the moves menu), `selected` the
        picked values of a multi-select."""
        view = self._remote.view(user_id)
        refusal = self._remote.edit_refusal(user_id, LINEUP)
        if view is None or refusal:
            return _note(refusal or STALE)
        if not editable(view):
            return _note(NOT_EDITABLE)
        if action_id == BACK_ACTION:
            return EditorReply(self._party(view))
        if action_id == MOVES_ACTION:
            return self._moves(view, value)
        if action_id == BOX_ADD_ACTION and len(view.party) >= MAX_MEMBERS:
            return self._full(view, value)
        if action_id in (SET_MOVES_ACTION, DEFAULT_MOVES_ACTION):
            picked = selected if action_id == SET_MOVES_ACTION else []
            member = _party_member(view, value)
            learnable = self._learnable(view, member) if member and picked else []
            if learnable is None:
                return _note(MOVES_UNAVAILABLE)
            targets = _with_moves(self._targets(view), value, picked, learnable)
        else:
            targets = self._edited(view, action_id, value)
        if targets is None:
            return _note(STALE)
        payload = {"members": targets}
        reason = set_lineup(view, payload)[1]
        if reason:
            return _note(f"바꿀 수 없어요: {REASONS[reason]}")
        submitted = self._remote.submit(user_id, LINEUP, payload)
        if submitted.refusal:
            return _note(submitted.refusal)
        changed = self._remote.view(user_id)
        if action_id in (SET_MOVES_ACTION, DEFAULT_MOVES_ACTION):
            return self._moves(changed, value)
        return EditorReply(self._party(changed))

    def options(self, user_id: str, block_id: str, query: str) -> list[dict]:
        """The swap menu's options past Slack's 100: `block_id` is the slot's individual id, or `ADD_SLOT`."""
        view = self._remote.view(user_id)
        if view is None or not editable(view):
            return []
        words = query.casefold().split()
        options = self._swap_options(view, block_id)
        return [option for option in options if all(word in option["text"]["text"].casefold() for word in words)][:PICKER_LIMIT]

    def _party(self, view: View) -> Screen:
        blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": party_title(view)}}]
        for index, member in enumerate(view.party):
            lines = member_lines(index + 1, member, self._name(member))
            blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": "\n".join(lines)}})
            blocks.append({"type": "actions", "block_id": member["id"], "elements": self._controls(view, index, member)})
        if len(view.party) < MAX_MEMBERS and (add := self._swap_select(view, ADD_SLOT, "포켓몬 넣기")):
            blocks.append({"type": "actions", "block_id": ADD_SLOT, "elements": [add]})
        notes = [RULE_NOTE, SYNC_NOTE, sync_line(view)]
        blocks.append({"type": "context", "elements": [{"type": "mrkdwn", "text": note} for note in notes]})
        return Screen("\n".join([party_title(view), sync_line(view)]), blocks)

    def _controls(self, view: View, index: int, member: dict) -> list[dict]:
        controls = [self._swap_select(view, member["id"], "바꾸기"),
                    _button(MOVES_ACTION, "기술", member["id"]),
                    _item_select(view, member)]
        orders = [(verb, word) for verb, word in ORDER_WORDS
                  if (verb, index) != ("up", 0) and (verb != "down" or index < len(view.party) - 1)
                  and (verb != "drop" or len(view.party) > 1)]
        if orders:
            controls.append({"type": "overflow", "action_id": ORDER_ACTION,
                             "options": [_option(word, f"{verb}|{member['id']}") for verb, word in orders]})
        return [control for control in controls if control is not None]

    def _swap_select(self, view: View, slot: str, placeholder: str) -> dict | None:
        options = self._swap_options(view, slot)
        if not options:
            return None
        select = {"action_id": SWAP_ACTION, "placeholder": {"type": "plain_text", "text": placeholder}}
        if len(options) <= PICKER_LIMIT:
            return select | {"type": "static_select", "options": options}
        return select | {"type": "external_select", "min_query_length": 0}

    def _swap_options(self, view: View, slot: str) -> list[dict]:
        replacing = None if slot == ADD_SLOT else slot
        labels = self._labels(view)
        return [_option(labels[member["id"]], f"{slot}|{member['id']}") for member in candidates(view, replacing)]

    def _labels(self, view: View) -> dict[str, str]:
        """Individual id -> its Box label (name, sex, level, nature), so same-species individuals differ."""
        labels = dict(zip([entry["id"] for entry in view.pool], option_labels(view.pool)))
        for member in [*view.party, *view.bench]:
            labels.setdefault(member["id"], f"{self._name(member)} Lv.{member['level']}"[:OPTION_TEXT_LIMIT])
        return labels

    def _name(self, member: dict) -> str:
        return member.get("name") or self._species_name(member["pokemon_id"])

    def _moves(self, view: View, member_id: str) -> EditorReply:
        member = _party_member(view, member_id)
        if member is None:
            return _note(STALE)
        learnable = self._learnable(view, member)
        if learnable is None:
            return _note(MOVES_UNAVAILABLE)
        return EditorReply(_moves_screen(view, member, self._name(member), learnable))

    def _learnable(self, view: View, member: dict) -> list[dict] | None:
        try:
            return self._moves_for(member["pokemon_id"], member["level"], owned_machines(view), status=True,
                                   egg=bool(member.get("mirror_herb")))
        except OSError:
            return None

    def _full(self, view: View, new_id: str) -> EditorReply:
        member = next((member for member in view.bench if member["id"] == new_id), None)
        if member is None:
            return _note(STALE)
        slots = [slot for slot in view.party
                 if rule_break([member if other is slot else other for other in view.party]) is None]
        if not slots:
            return _note(FULL_NO_SWAP)
        names = {slot["id"]: f"{index}. {self._name(slot)} Lv.{slot['level']}" for index, slot in enumerate(view.party, 1)}
        select = {"type": "static_select", "action_id": SWAP_ACTION,
                  "placeholder": {"type": "plain_text", "text": "뺄 포켓몬 고르기"},
                  "options": [_option(names[slot["id"]], f"{slot['id']}|{new_id}") for slot in slots]}
        title = f"*파티가 가득 찼어요.* {self._labels(view)[new_id]}을(를) 누구 대신 넣을까요?"
        blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": title}},
                  {"type": "actions", "elements": [select, _button(BACK_ACTION, "파티 보기", new_id)]},
                  {"type": "context", "elements": [{"type": "mrkdwn", "text": RULE_NOTE}]}]
        return EditorReply(Screen(title, blocks))

    def _edited(self, view: View, action_id: str, value: str) -> list[dict] | None:
        """The lineup after a swap, add, reorder, removal or item change; None when the value no longer fits it."""
        targets = self._targets(view)
        ids = [target["id"] for target in targets]
        if action_id in (SWAP_ACTION, BOX_ADD_ACTION):
            slot, _, new_id = value.partition("|") if action_id == SWAP_ACTION else (ADD_SLOT, "", value)
            incoming = next((member for member in view.bench if member["id"] == new_id), None)
            if incoming is None:
                return None
            if slot == ADD_SLOT:
                return [*targets, self._target(incoming)] if len(targets) < MAX_MEMBERS else None
            if slot not in ids:
                return None
            targets[ids.index(slot)] = self._target(incoming)
            return targets
        first, _, second = value.partition("|")
        if action_id == ITEM_ACTION and first in ids:
            targets[ids.index(first)]["item"] = second or None
            return targets
        if action_id != ORDER_ACTION or second not in ids:
            return None
        index = ids.index(second)
        if first == "drop":
            return [target for target in targets if target["id"] != second] if len(targets) > 1 else None
        other = index - 1 if first == "up" else index + 1
        if not 0 <= other < len(targets):
            return None
        targets[index], targets[other] = targets[other], targets[index]
        return targets

    def _targets(self, view: View) -> list[dict]:
        return [self._target(member) for member in view.party]

    def _target(self, member: dict) -> dict:
        return {"id": member["id"], "pokemon_id": member["pokemon_id"], "name": self._name(member),
                "moves": list(member.get("moves", [])), "machine": list(member.get("machine", [])),
                "item": member.get("item_key")}


def editable(view: View) -> bool:
    """Whether the user's app applies lineup ops and every member of the party is an owned individual."""
    return LINEUP in view.kinds and bool(view.party) and all("id" in member for member in view.party)


def candidates(view: View, replacing: str | None) -> list[dict]:
    """The bench members that may take `replacing`'s place (None: join the end) without breaking a clause."""
    others = [member for member in view.party if member["id"] != replacing]
    return [member for member in view.bench if rule_break([*others, member]) is None]


def owned_machines(view: View) -> set[int]:
    keys = [line["key"].removeprefix(MACHINE_PREFIX) for line in view.bag if line["key"].startswith(MACHINE_PREFIX)]
    return {int(key) for key in keys if key.isdigit()}


def _party_member(view: View, member_id: str) -> dict | None:
    return next((member for member in view.party if member["id"] == member_id), None)


def _with_moves(targets: list[dict], member_id: str, picked: list[str], learnable: list[dict]) -> list[dict] | None:
    """The lineup with `member_id`'s moves set to the picked ones it can learn; none picked is its level's defaults."""
    target = next((target for target in targets if target["id"] == member_id), None)
    if target is None:
        return None
    by_id = {move["id"]: move for move in learnable}
    moves = [int(value) for value in picked if value.isdigit() and int(value) in by_id][:MAX_MOVES]
    target["moves"] = moves
    target["machine"] = [move_id for move_id in moves if by_id[move_id]["source"] == "machine"]
    return targets


def _note(text: str) -> EditorReply:
    return EditorReply(Screen(text, [{"type": "section", "text": {"type": "mrkdwn", "text": text}}]), replace=False)


def _box_button(view: View, member: dict | None) -> dict | None:
    """`엔트리에 넣기` for a Box Pokémon that can join: one not tied up in a trade, and when the party has room, one that
    breaks no clause there."""
    if member is None:
        return None
    if len(view.party) < MAX_MEMBERS and rule_break([*view.party, member]) is not None:
        return None
    return _button(BOX_ADD_ACTION, "엔트리에 넣기", member["id"])


def _button(action_id: str, text: str, value: str) -> dict:
    return {"type": "button", "action_id": action_id, "text": {"type": "plain_text", "text": text}, "value": value}


def _item_select(view: View, member: dict) -> dict | None:
    """`도구 없음`, the held item and the bag's holdable items that clash with no other member."""
    current = member.get("item_key")
    options = [_option("도구 없음", f"{member['id']}|")]
    if current:
        options.append(_option(f"@{member['item_name']}", f"{member['id']}|{current}"))
    for line in view.bag:
        if not line.get("equip") or line["key"] == current or len(options) >= PICKER_LIMIT:
            continue
        holding = {**member, "item_key": line["key"], "held_item": line.get("held_item")}
        if rule_break([holding if other is member else other for other in view.party]) is None:
            options.append(_option(f"{line['name']} ×{line['count']}", f"{member['id']}|{line['key']}"))
    if len(options) == 1:
        return None
    return {"type": "static_select", "action_id": ITEM_ACTION, "placeholder": {"type": "plain_text", "text": "도구"},
            "options": options, "initial_option": options[1 if current else 0]}


def _option(text: str, value: str) -> dict:
    return {"text": {"type": "plain_text", "text": text[:OPTION_TEXT_LIMIT]}, "value": value}


def _moves_screen(view: View, member: dict, name: str, learnable: list[dict]) -> Screen:
    chosen = [move_id for move_id in member.get("moves", []) if any(move["id"] == move_id for move in learnable)]
    names = {move["id"]: move["name"] for move in learnable}
    title = f"*{name} Lv.{member['level']}의 기술* (최대 {MAX_MOVES}개)"
    now = " / ".join(names[move_id] for move_id in chosen) or "레벨에 맞는 기본 기술"
    groups = _move_groups(learnable, set(chosen))
    picked = [option for group in groups for option in group["options"] if int(option["value"]) in chosen]
    select = {"type": "multi_static_select", "action_id": SET_MOVES_ACTION, "max_selected_items": MAX_MOVES,
              "placeholder": {"type": "plain_text", "text": "기술 고르기"}, "option_groups": groups}
    if picked:
        select["initial_options"] = picked
    buttons = [_button(BACK_ACTION, "파티로 돌아가기", member["id"])]
    if member.get("moves"):
        buttons.insert(0, _button(DEFAULT_MOVES_ACTION, "기본 기술로", member["id"]))
    blocks = [
        {"type": "section", "text": {"type": "mrkdwn", "text": f"{title}\n지금: {now}"}},
        {"type": "actions", "block_id": member["id"], "elements": [select]},
        {"type": "actions", "elements": buttons},
        {"type": "context", "elements": [{"type": "mrkdwn", "text": text} for text in (MOVES_NOTE, SYNC_NOTE, sync_line(view))]},
    ]
    return Screen(title, blocks)


def _move_groups(learnable: list[dict], chosen: set[int]) -> list[dict]:
    """The learnable moves by how they are learned, at most Slack's 100 in all; the chosen ones always stay."""
    room = PICKER_LIMIT - len(chosen)
    grouped: dict[str, list[dict]] = {key: [] for key, _ in MOVE_GROUPS}
    for move in learnable:
        if move["id"] not in chosen:
            if room <= 0:
                continue
            room -= 1
        group = "status" if move["id"] in STATUS_MOVES else move["source"]
        level = f" (Lv.{move['level']})" if move["source"] == "level" and move["level"] else ""
        grouped.setdefault(group, []).append(_option(f"{move['name']}{level}", str(move["id"])))
    labels = dict(MOVE_GROUPS)
    return [{"label": {"type": "plain_text", "text": labels.get(key, key)}, "options": options}
            for key, options in grouped.items() if options]
