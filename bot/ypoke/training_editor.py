"""The `/트레이닝` screens: pick an owned Pokémon (party or Box), then each control queues one `train` op
(`remote_train`) that the bot's view shows at once. Each control says whether the bag or tokens pay, the way the
app's training tab does. Values carry individual ids, so a press on an older message still names its Pokémon."""

from collections.abc import Callable

from ypoke import blocks as kit
from ypoke.lineup_editor import (
    MAX_MOVES,
    TRAINING_OPEN_ACTION,
    EditorReply,
    MovesFor,
    move_options,
    moves_select,
    owned_machines,
)
from ypoke.remote_ops import OLD_APP_REFUSAL, RemoteOps, View
from ypoke.remote_train import (
    CAP, CAPSULE, EVOLVE, EVOLVE_ITEMS, FORM, GOLD_CAP, HERB, ITEM_KEYS, MAX_IV, MOVES, NATURE, NO_TOKENS, PATCH, REASONS,
    STAT_NAMES, STATS, TRAIN, describe, form_ability, item_count, owned, shop_price, train,
)
from ypoke.remote_views import RemoteViews, Screen, ability_name, sync_line, text_screen
from ypoke.trades import NATURE_NAMES_KO, PICKER_LIMIT, option_labels

ACTION_PREFIX = "train_"
OPEN_ACTION = TRAINING_OPEN_ACTION
PICK_ACTION = "train_pick"
BACK_ACTION = "train_back"
NATURE_ACTION = "train_nature"
CAP_ACTION = "train_cap"
GOLD_CAP_ACTION = "train_gold_cap"
CAPSULE_ACTION = "train_capsule"
PATCH_ACTION = "train_patch"
HERB_ACTION = "train_herb"
FORM_ACTION = "train_form"
EVOLVE_ACTION = "train_evolve"
MOVES_ACTION = "train_moves"
SET_MOVES_ACTION = "train_set_moves"
DEFAULT_MOVES_ACTION = "train_default_moves"
TITLE = "*트레이닝*"
PICK_PROMPT = "트레이닝할 포켓몬을 고르세요. 파티와 박스(교환에 올린 포켓몬 빼고)에서 골라요."
NONE_OWNED = "트레이닝할 포켓몬이 없어요. 회사에서 앱을 한 번 켜 주세요."
NO_MATCH = "'{query}'에 맞는 포켓몬이 없어요."
SYNC_NOTE = "트레이닝은 동료의 `/대결`에 바로 쓰이고, 앱은 다음에 회사에서 동기화할 때 같은 값으로 적용해요."
SHOP_NOTE = "특성캡슐·특성패치·병뚜껑·폼 도구·연결의끈은 가방에 있어야 써요. 없으면 `/상점`에서 사 주세요."
MOVES_NOTE = "기술머신 기술은 가방에 있는 기술머신만, 알 기술은 흉내허브를 쓴 포켓몬만 나와요."
STALE = "그새 포켓몬이 바뀌었어요. `/트레이닝`을 다시 열어 주세요."
MOVES_UNAVAILABLE = "기술 목록을 불러오지 못했어요. 잠시 뒤 다시 해 주세요."
SHORT = "토큰이 모자라요."
FORM_NAMES = {"incarnate": "화신폼", "therian": "영물폼", "normal": "기본", "black": "블랙", "white": "화이트",
              "ice": "백마 탄 모습", "shadow": "흑마 탄 모습"}
IV_SHORT = {"hp": "H", "attack": "A", "defense": "B", "special-attack": "C", "special-defense": "D", "speed": "S"}

AbilitiesFor = Callable[[int], list[dict]]


class TrainingEditor:
    """`moves_for` is `PokeAPIService.attacking_moves`, `abilities_for` `PokeAPIService.abilities`."""

    def __init__(self, remote: RemoteOps, views: RemoteViews, moves_for: MovesFor, abilities_for: AbilitiesFor,
                 species_name: Callable[[int], str]):
        self._remote = remote
        self._views = views
        self._moves_for = moves_for
        self._abilities_for = abilities_for
        self._species_name = species_name

    def handle(self, user_id: str, command: str, text: str) -> Screen:
        """The picker, or one Pokémon's screen when the text names one. Read-only when the app cannot apply it."""
        view = self._remote.view(user_id)
        if view is None:
            return self._views.handle(user_id, command, text)
        query = text.strip()
        members = self._matching(view, query)
        if not editable(view):
            return self._read_only(view, members, self._remote.edit_refusal(user_id, TRAIN) or OLD_APP_REFUSAL)
        if query and len(members) == 1:
            return self._pokemon(view, members[0])
        return self._picker(view, members, query)

    def act(self, user_id: str, action_id: str, value: str, selected: list[str]) -> EditorReply:
        """`value` is the individual id, or `id|choice` for a menu pick; the moves menu sends its block id."""
        view = self._remote.view(user_id)
        refusal = self._remote.edit_refusal(user_id, TRAIN)
        if view is None or refusal:
            return _note(refusal or STALE)
        individual_id, _, choice = value.partition("|")
        if action_id == BACK_ACTION:
            return EditorReply(self._picker(view, self._matching(view, ""), ""))
        member = owned(view, individual_id)
        if member is None:
            return _note(STALE)
        if action_id in (OPEN_ACTION, PICK_ACTION):
            return EditorReply(self._pokemon(view, member))
        if action_id == MOVES_ACTION:
            return self._moves(view, member)
        payload = self._payload(view, member, action_id, choice, selected)
        if payload is None:
            return _note(STALE)
        if isinstance(payload, EditorReply):
            return payload
        reason = train(view, payload)[1]
        if reason:
            return _note(f"트레이닝할 수 없어요: {REASONS[reason]}{self._shortfall(view, payload, reason)}")
        submitted = self._remote.submit(user_id, TRAIN, payload)
        if submitted.refusal:
            return _note(submitted.refusal)
        changed = self._remote.view(user_id)
        trained = owned(changed, individual_id) if changed else None
        if trained is None:
            return _note(STALE)
        if payload["action"] == MOVES:
            return self._moves(changed, trained)
        return EditorReply(self._pokemon(changed, trained, done=_done(payload)))

    def options(self, user_id: str, block_id: str, query: str) -> list[dict]:
        """The picker's options past Slack's 100."""
        view = self._remote.view(user_id)
        if view is None or not editable(view):
            return []
        words = query.casefold().split()
        options = [kit.option(label, member["id"]) for member, label in self._labelled(view, self._matching(view, ""))]
        return [option for option in options if all(word in option["text"]["text"].casefold() for word in words)][:PICKER_LIMIT]

    def move_options(self, user_id: str, block_id: str, query: str) -> list[dict]:
        """The moves menu's options for the Pokémon `block_id`."""
        view = self._remote.view(user_id)
        member = owned(view, block_id) if view is not None and editable(view) else None
        learnable = self._learnable(view, member) if member else None
        if not learnable:
            return []
        return move_options(learnable, member.get("moves", []), query)

    def _matching(self, view: View, query: str) -> list[dict]:
        members = [*view.party, *view.bench]
        members = [member for member in members if "id" in member]
        if not query:
            return members
        return [member for member in members if query.casefold() in self._name(member).casefold()]

    def _labelled(self, view: View, members: list[dict]) -> list[tuple[dict, str]]:
        labels = dict(zip([entry["id"] for entry in view.pool], option_labels(view.pool)))
        party = {member.get("id") for member in view.party}
        return [(member, ("[파티] " if member["id"] in party else "")
                 + labels.get(member["id"], f"{self._name(member)} Lv.{member['level']}")) for member in members]

    def _name(self, member: dict) -> str:
        return member.get("name") or self._species_name(member["pokemon_id"])

    def _picker(self, view: View, members: list[dict], query: str) -> Screen:
        head = f"{TITLE} '{query}' 검색" if query else TITLE
        if not members:
            return text_screen([head, NO_MATCH.format(query=query) if query else NONE_OWNED], view)
        options = [kit.option(label, member["id"]) for member, label in self._labelled(view, members)]
        if len(options) <= PICKER_LIMIT:
            select = kit.static_select(PICK_ACTION, "포켓몬 고르기", options)
        else:
            select = kit.external_select(PICK_ACTION, "포켓몬 고르기")
        return Screen(head, [kit.section(f"{head}\n{PICK_PROMPT}"), kit.actions([select]),
                             kit.context(_wallet_line(view), sync_line(view))])

    def _read_only(self, view: View, members: list[dict], refusal: str) -> Screen:
        lines = [TITLE, refusal]
        lines += [f"• {label} · {_traits(member)}" for member, label in self._labelled(view, members)]
        return text_screen(lines, view)

    def _pokemon(self, view: View, member: dict, done: str | None = None) -> Screen:
        name = self._name(member)
        head = f"{TITLE} · {name}{' ✨' if member.get('shiny') else ''} Lv.{member['level']}"
        lines = [head, _traits(member), _iv_line(member)]
        if done:
            lines.insert(0, done)
        first = [control for control in (_nature_select(view, member), _cap_select(view, member),
                                         _gold_cap_button(view, member)) if control]
        second = [control for control in (*self._ability_buttons(view, member), _herb_button(view, member),
                                          _form_select(view, member), self._evolve_button(view, member)) if control]
        third = [kit.button("기술 바꾸기", MOVES_ACTION, member["id"]), kit.button("다른 포켓몬", BACK_ACTION, member["id"])]
        blocks = [kit.section("\n".join(lines))]
        blocks += [kit.actions(elements, block_id=f"{member['id']}#{index}")
                   for index, elements in enumerate((first, second, third)) if elements]
        blocks.append(kit.context(_wallet_line(view), _stock_line(view), SHOP_NOTE, SYNC_NOTE, sync_line(view)))
        return Screen(head, blocks)

    def _ability_buttons(self, view: View, member: dict) -> list[dict | None]:
        buttons = []
        for action, action_id, word in ((CAPSULE, CAPSULE_ACTION, "특성캡슐"), (PATCH, PATCH_ACTION, "특성패치")):
            count = item_count(view, ITEM_KEYS[action])
            target = self._ability_target(member, action) if count else None
            buttons.append(kit.button(f"{word} → {ability_name(target['name'])} (가방 ×{count})", action_id,
                                      member["id"]) if target else None)
        return buttons

    def _evolve_button(self, view: View, member: dict) -> dict | None:
        """Shown when the app offered the evolution and the replayed bag still has the item."""
        payload = self._evolve_payload(member)
        if payload is None or train(view, payload)[1]:
            return None
        item = payload["item"]
        text = f"{EVOLVE_ITEMS[item]}으로 진화 → {payload['to_name']} (가방 ×{item_count(view, item)})"
        return kit.button(text, EVOLVE_ACTION, member["id"])

    def _evolve_payload(self, member: dict) -> dict | None:
        evolution = member.get("evolution")
        if not evolution or evolution.get("item") not in EVOLVE_ITEMS:
            return None
        return {"id": member["id"], "pokemon_id": member["pokemon_id"], "name": self._name(member), "action": EVOLVE,
                "item": evolution["item"], "to_pokemon_id": evolution["pokemon_id"],
                "to_name": self._species_name(evolution["pokemon_id"])}

    def _ability_target(self, member: dict, action: str) -> dict | None:
        """The ability the app's Capsule or Patch would give, from the abilities of the member's current form."""
        if not isinstance(member.get("ability_slot"), int) or form_ability(member):
            return None
        try:
            options = self._abilities_for(member["pokemon_id"])
        except OSError:
            return None
        hidden = bool(member.get("ability_hidden"))
        if action == CAPSULE:
            if hidden:
                return None
            return next((option for option in options
                         if not option["hidden"] and option["slot"] != member["ability_slot"]), None)
        regular = sorted((option for option in options if not option["hidden"]), key=lambda option: option["slot"])
        if hidden:
            return regular[0] if regular else None
        return next((option for option in options if option["hidden"]), None)

    def _payload(self, view: View, member: dict, action_id: str, choice: str,
                 selected: list[str]) -> dict | EditorReply | None:
        base = {"id": member["id"], "pokemon_id": member["pokemon_id"], "name": self._name(member)}
        if action_id == NATURE_ACTION:
            return base | {"action": NATURE, "nature": choice, "price": _price(view, NATURE)}
        if action_id == HERB_ACTION:
            return base | {"action": HERB, "price": _price(view, HERB)}
        if action_id == CAP_ACTION:
            return base | {"action": CAP, "stat": choice}
        if action_id == GOLD_CAP_ACTION:
            return base | {"action": GOLD_CAP}
        if action_id in (CAPSULE_ACTION, PATCH_ACTION):
            action = CAPSULE if action_id == CAPSULE_ACTION else PATCH
            target = self._ability_target(member, action)
            if target is None:
                return None
            return base | {"action": action, "ability": {**target, "label": ability_name(target["name"])}}
        if action_id == FORM_ACTION:
            form = next((form for form in member.get("forms", []) if form["form"] == choice), None)
            if form is None:
                return None
            return base | {"action": FORM, "form": choice, "to_pokemon_id": form["pokemon_id"],
                           "form_name": FORM_NAMES.get(choice, choice)}
        if action_id == EVOLVE_ACTION:
            return self._evolve_payload(member)
        if action_id in (SET_MOVES_ACTION, DEFAULT_MOVES_ACTION):
            picked = selected if action_id == SET_MOVES_ACTION else []
            learnable = self._learnable(view, member) if picked else []
            if learnable is None:
                return _note(MOVES_UNAVAILABLE)
            by_id = {move["id"]: move for move in learnable}
            moves = [int(value) for value in picked if value.isdigit() and int(value) in by_id][:MAX_MOVES]
            return base | {"action": MOVES, "moves": moves,
                           "machine": [move_id for move_id in moves if by_id[move_id]["source"] == "machine"],
                           "egg": [move_id for move_id in moves if by_id[move_id]["source"] == "egg"]}
        return None

    def _shortfall(self, view: View, payload: dict, reason: str) -> str:
        if reason != NO_TOKENS:
            return ""
        return f". 쓸 수 있는 토큰 {view.wallet or 0:,}, 필요한 토큰 {payload.get('price') or 0:,}"

    def _moves(self, view: View, member: dict) -> EditorReply:
        learnable = self._learnable(view, member)
        if learnable is None:
            return _note(MOVES_UNAVAILABLE)
        chosen = [move_id for move_id in member.get("moves", []) if any(move["id"] == move_id for move in learnable)]
        names = {move["id"]: move["name"] for move in learnable}
        title = f"*{self._name(member)} Lv.{member['level']}의 기술* (최대 {MAX_MOVES}개)"
        now = " / ".join(names[move_id] for move_id in chosen) or "레벨에 맞는 기본 기술"
        select = moves_select(SET_MOVES_ACTION, learnable, chosen)
        buttons = [kit.button("트레이닝으로 돌아가기", OPEN_ACTION, member["id"])]
        if member.get("moves"):
            buttons.insert(0, kit.button("기본 기술로", DEFAULT_MOVES_ACTION, member["id"]))
        blocks = [kit.section(f"{title}\n지금: {now}", block_id=member["id"], accessory=select),
                  kit.actions(buttons), kit.context(MOVES_NOTE, SYNC_NOTE, sync_line(view))]
        return EditorReply(Screen(title, blocks))

    def _learnable(self, view: View, member: dict) -> list[dict] | None:
        try:
            return self._moves_for(member["pokemon_id"], member["level"], owned_machines(view), status=True,
                                   egg=bool(member.get("mirror_herb")))
        except OSError:
            return None


def editable(view: View) -> bool:
    return TRAIN in view.kinds


def _price(view: View, action: str) -> int | None:
    """None when the bag pays; else the shop price the player is shown."""
    return None if item_count(view, ITEM_KEYS[action]) else shop_price(view, ITEM_KEYS[action])


def _nature_select(view: View, member: dict) -> dict | None:
    cost = _cost(view, NATURE)
    if cost is None:
        return None
    options = [kit.option(name, f"{member['id']}|{key}") for key, name in NATURE_NAMES_KO.items()
               if key != member.get("nature")]
    return kit.static_select(NATURE_ACTION, f"민트로 성격 바꾸기 ({cost})", options)


def _cost(view: View, action: str) -> str | None:
    """How a Mint or Mirror Herb is paid, or None when neither the bag nor the balance can."""
    count = item_count(view, ITEM_KEYS[action])
    if count:
        return f"가방 ×{count}"
    price = shop_price(view, ITEM_KEYS[action])
    if price is None or view.wallet is None or price > view.wallet:
        return None
    return f"{price:,}토큰"


def _cap_select(view: View, member: dict) -> dict | None:
    count = item_count(view, ITEM_KEYS[CAP])
    stats = [stat for stat, (key, _) in STATS.items() if member.get("ivs", {}).get(key) != MAX_IV]
    if not count or not stats:
        return None
    return kit.static_select(CAP_ACTION, f"은색병뚜껑 (가방 ×{count})",
                             [kit.option(STAT_NAMES[stat], f"{member['id']}|{stat}") for stat in stats])


def _gold_cap_button(view: View, member: dict) -> dict | None:
    count = item_count(view, ITEM_KEYS[GOLD_CAP])
    if not count or all(member.get("ivs", {}).get(key) == MAX_IV for key, _ in STATS.values()):
        return None
    return kit.button(f"금색병뚜껑 (가방 ×{count})", GOLD_CAP_ACTION, member["id"])


def _herb_button(view: View, member: dict) -> dict | None:
    if member.get("mirror_herb") or not member.get("egg_moves") or (cost := _cost(view, HERB)) is None:
        return None
    return kit.button(f"흉내허브 ({cost})", HERB_ACTION, member["id"])


def _form_select(view: View, member: dict) -> dict | None:
    forms = [form for form in member.get("forms", []) if form["pokemon_id"] != member["pokemon_id"]]
    if not forms or not item_count(view, member.get("form_tool", "")):
        return None
    return kit.static_select(FORM_ACTION, "폼 바꾸기", [
        kit.option(FORM_NAMES.get(form["form"], form["form"]), f"{member['id']}|{form['form']}") for form in forms])


def _traits(member: dict) -> str:
    parts = [NATURE_NAMES_KO.get(member.get("nature"), "성격 없음"),
             ability_name(member["ability"]) if member.get("ability") else "특성 없음"]
    if member.get("form") in FORM_NAMES:
        parts.append(FORM_NAMES[member["form"]])
    if member.get("mirror_herb"):
        parts.append("흉내허브 사용")
    return " · ".join(parts)


def _iv_line(member: dict) -> str:
    ivs = member.get("ivs", {})
    values = [f"{IV_SHORT[stat]}{ivs[key]}" for stat, (key, _) in STATS.items() if key in ivs]
    return f"개체값 {' '.join(values)}" if values else "개체값 알 수 없음"


def _wallet_line(view: View) -> str:
    return f"쓸 수 있는 토큰 {view.wallet:,}" if view.wallet is not None else "쓸 수 있는 토큰 알 수 없음"


def _stock_line(view: View) -> str:
    words = [(ITEM_KEYS[action], word) for action, word in (
        (NATURE, "민트"), (CAPSULE, "특성캡슐"), (PATCH, "특성패치"), (CAP, "은색병뚜껑"), (GOLD_CAP, "금색병뚜껑"),
        (HERB, "흉내허브"))]
    stock = [f"{word} ×{item_count(view, key)}" for key, word in [*words, *EVOLVE_ITEMS.items()]
             if item_count(view, key)]
    return f"가방: {' · '.join(stock)}" if stock else "가방에 트레이닝 도구가 없어요."


def _done(payload: dict) -> str:
    return f"✅ {describe(payload)} — 걸어 뒀어요."


def _note(text: str) -> EditorReply:
    return EditorReply(Screen(text, [kit.section(text)]), replace=False)
