"""The `/상점` screens: a menu per shop category, then one item with a button per quantity. Each buy queues one `buy`
op (`remote_buy`) and is checked against the spendable balance: the last synced wallet less the pending buys."""

from ypoke import blocks as kit
from ypoke.editor import is_numbered, join_value, numbered, split_value
from ypoke.lineup_editor import EditorReply
from ypoke.remote_buy import BUY, NO_TOKENS, REASONS, buy
from ypoke.remote_ops import OLD_APP_REFUSAL, RemoteOps, View
from ypoke.remote_views import RemoteViews, Screen, sync_line, text_screen
from ypoke.trades import PICKER_LIMIT

ACTION_PREFIX = "shop_"
PICK_ACTION = "shop_pick"
BUY_ACTION = "shop_buy"
BACK_ACTION = "shop_back"
QUANTITIES = (1, 5, 10, 30)
TITLE = "*상점*"
SHOP_NOTE = "산 물건은 `/가방`과 `/파티` 도구에 바로 들어와요. 앱은 다음에 회사에서 동기화할 때 같은 값으로 사요."
EMPTY_SHOP = "상점 목록이 아직 없어요. 회사에서 앱을 한 번 켜 주세요."
SHORT = "토큰이 모자라요."
STALE = "그새 상점이 바뀌었어요. `/상점`을 다시 열어 주세요."


class ShopEditor:
    def __init__(self, remote: RemoteOps, views: RemoteViews):
        self._remote = remote
        self._views = views

    def handle(self, user_id: str, command: str, text: str) -> Screen:
        """The shop with buy controls when the user's app applies `buy` ops; the list alone otherwise. A query that
        names one item opens it."""
        view = self._remote.view(user_id)
        if view is None:
            return self._views.handle(user_id, command, text)
        query = text.strip()
        lines = _matching(view.shop, query)
        if not editable(view):
            return _read_only(view, lines, self._remote.edit_refusal(user_id, BUY) or OLD_APP_REFUSAL)
        if query and len(lines) == 1:
            return _item_screen(view, lines[0])
        return _shop_screen(view, lines, query)

    def act(self, user_id: str, action_id: str, value: str, selected: list[str]) -> EditorReply:
        """`value` is the picked item key, or `count|price|key` for a buy button."""
        view = self._remote.view(user_id)
        refusal = self._remote.edit_refusal(user_id, BUY)
        if view is None or refusal:
            return _note(refusal or STALE)
        if action_id == BACK_ACTION:
            return EditorReply(_shop_screen(view, view.shop, ""))
        if action_id == PICK_ACTION:
            line = _line(view, value)
            return EditorReply(_item_screen(view, line)) if line else _note(STALE)
        count, price, key = _buy_value(value)
        line = _line(view, key)
        if not is_numbered(action_id, BUY_ACTION) or line is None or count is None:
            return _note(STALE)
        payload = {"key": key, "name": line["name"], "count": count, "price": price}
        reason = buy(view, payload)[1]
        if reason == NO_TOKENS:
            return _note(f"{SHORT} 쓸 수 있는 토큰 {view.wallet or 0:,}, 필요한 토큰 {count * price:,}")
        if reason:
            return _note(f"살 수 없어요: {REASONS[reason]}")
        submitted = self._remote.submit(user_id, BUY, payload)
        if submitted.refusal:
            return _note(submitted.refusal)
        changed = self._remote.view(user_id)
        done = f"✅ {line['name']} ×{count}을(를) 샀어요. 남은 토큰 {changed.wallet:,}"
        still = _line(changed, key)
        return EditorReply(_item_screen(changed, still, done) if still else _shop_screen(changed, changed.shop, "", done))

    def options(self, user_id: str, block_id: str, query: str) -> list[dict]:
        """A category menu past Slack's 100 options: `block_id` is the category."""
        view = self._remote.view(user_id)
        if view is None or not editable(view):
            return []
        lines = [line for line in _matching(view.shop, query) if _category(line) == block_id]
        return [_item_option(line) for line in lines][:PICKER_LIMIT]


def editable(view: View) -> bool:
    return BUY in view.kinds


def _shop_screen(view: View, lines: list[dict], query: str, done: str | None = None) -> Screen:
    head = [done] if done else []
    head.append(f"{TITLE} · 쓸 수 있는 토큰 {view.wallet or 0:,}")
    if not view.shop:
        head.append(EMPTY_SHOP)
    elif not lines:
        head.append(f"'{query}'에 맞는 물건이 없어요.")
    else:
        head.append("분류에서 물건을 고르세요.")
    blocks = [kit.section("\n".join(head))]
    for category, group in _groups(lines).items():
        if len(group) <= PICKER_LIMIT:
            select = kit.static_select(PICK_ACTION, "물건 고르기", [_item_option(line) for line in group])
        else:
            select = kit.external_select(PICK_ACTION, "물건 고르기")
        blocks.append(kit.section(f"*{_category_name(group[0])}* {len(group)}개", block_id=category, accessory=select))
    blocks.append(kit.context(SHOP_NOTE, sync_line(view)))
    return Screen("\n".join([*head[:2], sync_line(view)]), blocks)


def _item_screen(view: View, line: dict, done: str | None = None) -> Screen:
    price, wallet = line["price"], view.wallet or 0
    held = sum(bagged["count"] for bagged in view.bag if bagged["key"] == line["key"])
    text = [done] if done else []
    text += [f"*{line['name']}* · {_category_name(line)}", f"값 {price:,}토큰 · 쓸 수 있는 토큰 {wallet:,}"]
    if held:
        text.append(f"가방에 {held}개 있어요.")
    affordable = wallet // price if price else QUANTITIES[-1]
    counts = [count for count in ((1,) if line["single"] else QUANTITIES) if count <= affordable]
    if not counts:
        text.append(SHORT)
    buttons = [kit.button(f"{count}개 사기 ({count * price:,})" if not line["single"] else f"사기 ({price:,})",
                          numbered(BUY_ACTION, count), join_value(str(count), str(price), line["key"]),
                          style="primary" if index == 0 else None) for index, count in enumerate(counts)]
    buttons.append(kit.button("상점으로", BACK_ACTION, "back"))
    blocks = [kit.section("\n".join(text)), kit.actions(buttons), kit.context(SHOP_NOTE, sync_line(view))]
    return Screen("\n".join([text[0], sync_line(view)]), blocks)


def _read_only(view: View, lines: list[dict], refusal: str) -> Screen:
    text = [TITLE, refusal]
    for group in _groups(lines).values():
        text.append(f"*{_category_name(group[0])}*")
        text += [f"• {line['name']} · {line['price']:,}토큰" for line in group]
    return text_screen(text, view)


def _matching(lines: list[dict], query: str) -> list[dict]:
    words = query.casefold().split()
    return [line for line in lines if all(word in line["name"].casefold() for word in words)]


def _groups(lines: list[dict]) -> dict[str, list[dict]]:
    """The lines by category, in the app's order."""
    groups: dict[str, list[dict]] = {}
    for line in lines:
        groups.setdefault(_category(line), []).append(line)
    return groups


def _category(line: dict) -> str:
    return line.get("category") or "other"


def _category_name(line: dict) -> str:
    return line.get("category_name") or line.get("category") or "기타"


def _line(view: View, key: str) -> dict | None:
    return next((line for line in view.shop if line["key"] == key), None)


def _buy_value(value: str) -> tuple[int | None, int, str]:
    count, price, key = split_value(value, 3)
    if not (count.isdigit() and price.isdigit()):
        return None, 0, ""
    return int(count), int(price), key


def _item_option(line: dict) -> dict:
    return kit.option(f"{line['name']} · {line['price']:,}", line["key"])


def _note(text: str) -> EditorReply:
    return EditorReply(Screen(text, [kit.section(text)]), replace=False)
