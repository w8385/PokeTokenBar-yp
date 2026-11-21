import json
import re
from pathlib import Path
from types import SimpleNamespace

import pytest

from ypoke import __main__ as bot
from ypoke.editor import Route, checked, is_numbered, join_value, numbered, pressed_value, route_for, split_value
from ypoke.shop_editor import BUY_ACTION

GOLDEN = Path(__file__).parent / "golden" / "screens"
LEGACY_ACTION_IDS = ("shop_buy",)


class App:
    """Records what `register` listens for."""

    def __init__(self):
        self.pressed, self.menus = [], []

    def action(self, matcher):
        return lambda listener: self.pressed.append(matcher)

    def options(self, matcher):
        return lambda listener: self.menus.append(matcher)

    def command(self, name):
        return lambda listener: None

    def event(self, name):
        return lambda listener: None


def test_every_action_id_the_bot_has_sent_reaches_exactly_one_listener():
    app = registered()
    action_ids = {node["action_id"] for node in golden_nodes() if "action_id" in node} | set(LEGACY_ACTION_IDS)
    assert len(action_ids) > 40
    assert {action_id: listeners_for(app.pressed, action_id) for action_id in sorted(action_ids)} == {
        action_id: 1 for action_id in sorted(action_ids)}


def test_every_typed_search_menu_the_bot_has_sent_is_answered():
    app = registered()
    typed = {node["action_id"] for node in golden_nodes()
             if "action_id" in node and node["type"].endswith("external_select")}
    assert typed
    assert {action_id: listeners_for(app.menus, action_id) for action_id in sorted(typed)} == {
        action_id: 1 for action_id in sorted(typed)}


def test_the_training_button_on_the_party_screen_reaches_the_training_editor():
    routes = bot.editor_routes(SimpleNamespace(editor="lineup", shop="shop", training="training", trading="trading"))
    assert route_for(routes, "train_open").editor == "training"
    assert route_for(routes, "shop_buy").editor == "shop"
    assert route_for(routes, "shop_buy_30").editor == "shop"
    assert route_for(routes, "offer_miracle_post").editor == "trading"


def test_a_value_splits_the_way_the_editors_always_read_it():
    values = [node["value"] for node in golden_nodes() if isinstance(node.get("value"), str)]
    assert any(value.count("|") == 2 for value in values)
    for value in values:
        first, _, rest = value.partition("|")
        second, _, third = rest.partition("|")
        assert split_value(value) == (first, rest)
        assert split_value(value, 3) == (first, second, third)
        assert join_value(*split_value(value)) == value or "|" not in value


def test_every_buy_button_the_shop_has_sent_is_a_buy():
    buys = [node["action_id"] for node in golden_nodes() if node.get("action_id", "").startswith(BUY_ACTION)]
    assert len(buys) > 1
    assert all(is_numbered(action_id, BUY_ACTION) for action_id in [*buys, *LEGACY_ACTION_IDS])
    assert numbered(BUY_ACTION, 10) == "shop_buy_10"
    assert not is_numbered("shop_buyer", BUY_ACTION)


def test_a_press_sends_its_value_or_its_picked_option():
    assert pressed_value({"value": "p1"}) == "p1"
    assert pressed_value({"selected_option": {"value": "p1|b1"}}) == "p1|b1"
    assert pressed_value({"block_id": "p1"}) == ""


def test_editor_prefixes_and_menus_cannot_collide():
    with pytest.raises(ValueError):
        checked([Route("train_", "training"), Route("train_open", "lineup")])
    with pytest.raises(ValueError):
        checked([Route("lineup_", "lineup", (("shop_pick", None),)), Route("shop_", "shop")])
    with pytest.raises(ValueError):
        checked([Route("shop_", "shop", (("shop_pick", None), ("shop_pick", None)))])


def registered() -> App:
    menus = SimpleNamespace(options=None, item_options=None, move_options=None)
    handler = SimpleNamespace(editor=menus, shop=menus, training=menus, trading=menus)
    app = App()
    bot.register(app, handler, trades=None, miracle=None, pictures=None)
    return app


def golden_nodes() -> list[dict]:
    """Every dict in every golden screen: blocks, controls, options."""
    found = []
    pending = [json.loads(path.read_text()) for path in sorted(GOLDEN.glob("*.json"))]
    while pending:
        node = pending.pop()
        if isinstance(node, dict):
            found.append(node)
            pending += node.values()
        elif isinstance(node, list):
            pending += node
    return found


def listeners_for(matchers: list, action_id: str) -> int:
    return sum(1 for matcher in matchers
               if (matcher.match(action_id) if isinstance(matcher, re.Pattern) else matcher == action_id))
