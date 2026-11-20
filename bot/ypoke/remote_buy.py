"""The `buy` remote op: one shop purchase made in Slack. Payload: `{"key", "name", "count", "price"}` (`price` is the
unit price shown). Contract: bot/API.md "The `buy` op"."""

from dataclasses import replace

from ypoke.remote_ops import OpKind, View, register

BUY = "buy"
MAX_COUNT = 99
NOT_SOLD = "not_sold"
PRICE_CHANGED = "price_changed"
NO_TOKENS = "no_tokens"
INVALID = "invalid"
REASONS = {
    NOT_SOLD: "이제 상점에서 팔지 않아요",
    PRICE_CHANGED: "값이 바뀌었어요",
    NO_TOKENS: "토큰이 모자라요",
    INVALID: "구매를 읽지 못했어요",
}


def describe(payload: dict) -> str:
    count, price = payload.get("count", 0), payload.get("price", 0)
    return f"상점에서 사기: {payload.get('name') or payload.get('key')} ×{count} ({count * price:,}토큰)"


def _replay(view: View, payload: dict) -> View:
    return buy(view, payload)[0]


def buy(view: View, payload: dict) -> tuple[View, str | None]:
    """The view with the items in the bag and the cost off the wallet, and None; or the view unchanged and the reason
    code the app would cancel it with. A line bought once leaves the shop."""
    key, count, price = payload.get("key"), payload.get("count"), payload.get("price")
    if not (isinstance(key, str) and _is_int(count) and 1 <= count <= MAX_COUNT and _is_int(price) and price >= 0):
        return view, INVALID
    line = next((line for line in view.shop if line["key"] == key), None)
    if line is None:
        return view, NOT_SOLD
    if line["price"] != price:
        return view, PRICE_CHANGED
    if line["single"] and count != 1:
        return view, INVALID
    cost = price * count
    if view.wallet is None or cost > view.wallet:
        return view, NO_TOKENS
    shop = [other for other in view.shop if other is not line] if line["single"] else view.shop
    return replace(view, wallet=view.wallet - cost, bag=_with_items(view.bag, line, count), shop=shop), None


def _with_items(bag: list[dict], line: dict, count: int) -> list[dict]:
    if any(held["key"] == line["key"] for held in bag):
        return [{**held, "count": held["count"] + count} if held["key"] == line["key"] else held for held in bag]
    added = {"key": line["key"], "name": line["name"], "count": count}
    if line.get("equip"):
        added["equip"] = True
        if line.get("held_item"):
            added["held_item"] = line["held_item"]
    return [*bag, added]


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


register(OpKind(BUY, describe, _replay, reasons=REASONS))
