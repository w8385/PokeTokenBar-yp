import ast
import logging
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from slack_sdk.errors import SlackApiError

from ypoke import blocks as kit
from ypoke.blocks import BlockError

PACKAGE = Path(kit.__file__).parent
SLACK_TYPES = {"section", "actions", "context", "divider", "header", "image", "input", "rich_text", "button",
               "static_select", "external_select", "multi_static_select", "multi_external_select", "overflow",
               "checkboxes", "radio_buttons", "datepicker", "timepicker", "mrkdwn", "plain_text", "modal", "home"}
SENDERS = {"respond", "send", "say"}
SLACK_ENTRY_POINTS = {"transport", "__main__"}
LOG_TAIL = 2000


def test_no_module_writes_a_slack_block_by_hand():
    assert [finding for path in modules() for finding in block_literals(path.read_text(), path.name)] == []


def test_no_module_sends_to_slack_except_through_blocks_send():
    assert [finding for path in modules() for finding in direct_sends(path.read_text(), path.name)] == []


def test_only_the_slack_entry_points_need_the_slack_libraries_to_import():
    names = [f"ypoke.{path.stem}" for path in sorted(PACKAGE.glob("*.py"))
             if path.stem not in SLACK_ENTRY_POINTS and not path.stem.startswith("_")]
    assert "ypoke.gyms" in names and "ypoke.blocks" in names
    blocked = "import importlib, sys\nsys.modules.update(slack_sdk=None, slack_bolt=None)\n" + "".join(
        f"importlib.import_module({name!r})\n" for name in names)
    result = subprocess.run([sys.executable, "-c", blocked], cwd=PACKAGE.parent, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr[-LOG_TAIL:]


def test_the_scans_catch_a_hand_written_block_and_a_direct_send():
    assert block_literals('blocks = [{"type": "section", "text": text}]', "screen.py") == ["screen.py:1 section"]
    assert direct_sends("client.chat_postMessage(channel=c, text=t)", "card.py") == ["card.py:1 chat_postMessage"]
    assert direct_sends("respond(text=t)", "card.py") == ["card.py:1 respond"]
    assert direct_sends("WebhookClient(url).send(text=t)", "card.py") == ["card.py:1 send"]
    assert direct_sends("kit.send(client.chat_update, 'card', text=t)", "card.py") == []


def test_a_label_past_slacks_limit_is_cut_but_a_long_value_raises():
    assert kit.option("가" * 80, "v")["text"]["text"] == "가" * 75
    assert kit.button("가" * 80, "go", "v")["text"]["text"] == "가" * 75
    with pytest.raises(BlockError):
        kit.option("label", "v" * 151)
    with pytest.raises(BlockError):
        kit.button("label", "go", "v" * 2001)


def test_a_select_needs_between_one_and_a_hundred_distinct_options():
    with pytest.raises(BlockError):
        kit.static_select("pick", "고르기", [])
    with pytest.raises(BlockError):
        kit.static_select("pick", "고르기", [kit.option(str(n), str(n)) for n in range(101)])
    with pytest.raises(BlockError):
        kit.static_select("pick", "고르기", [kit.option("a", "same"), kit.option("b", "same")])
    with pytest.raises(BlockError):
        kit.static_select("pick", "고르기", [kit.option("a", "a")], initial_option=kit.option("b", "b"))


def test_an_overflow_holds_two_to_five_options():
    with pytest.raises(BlockError):
        kit.overflow("order", [kit.option("a", "a")])
    with pytest.raises(BlockError):
        kit.overflow("order", [kit.option(str(n), str(n)) for n in range(6)])


def test_a_typed_search_select_takes_its_picks_within_max_selected_items():
    picks = [kit.option(str(n), str(n)) for n in range(5)]
    with pytest.raises(BlockError):
        kit.multi_external_select("moves", "기술", max_selected_items=4, initial_options=picks)


def test_an_actions_block_takes_no_duplicate_action_id_and_no_multi_select():
    with pytest.raises(BlockError):
        kit.actions([kit.button("a", "go", "1"), kit.button("b", "go", "2")])
    with pytest.raises(BlockError):
        kit.actions([kit.multi_external_select("moves", "기술", max_selected_items=4)])
    with pytest.raises(BlockError):
        kit.actions([kit.button(str(n), f"go{n}", "v") for n in range(26)])


def test_a_section_and_a_context_keep_within_slacks_sizes():
    with pytest.raises(BlockError):
        kit.section("가" * 3001)
    with pytest.raises(BlockError):
        kit.section(fields=["가" * 2001])
    with pytest.raises(BlockError):
        kit.section("text", accessory=kit.divider())
    with pytest.raises(BlockError):
        kit.context(*(["note"] * 11))
    with pytest.raises(BlockError):
        kit.context(kit.button("a", "go", "v"))
    with pytest.raises(BlockError):
        kit.section("text", block_id="b" * 256)


def test_a_message_takes_no_block_id_twice_and_at_most_fifty_blocks():
    assert kit.violations([kit.section("a", block_id="x"), kit.section("b", block_id="x")]) == ["block_id 'x' twice"]
    assert kit.violations([kit.divider()] * 51) == ["51 blocks"]


def test_send_returns_slacks_reply_and_logs_a_refusal_without_the_message(caplog):
    refusal = SimpleNamespace(status_code=400, body="invalid_blocks")
    with caplog.at_level(logging.WARNING):
        assert kit.send(lambda **message: refusal, "lineup_moves", text="secret-token", blocks=[]) is refusal
    assert [record.getMessage() for record in caplog.records] == [
        'response url rejected lineup_moves: status=400 body="invalid_blocks"']


def test_send_logs_a_broken_rule_and_still_sends(caplog):
    sent = []
    with caplog.at_level(logging.WARNING):
        kit.send(lambda **message: sent.append(message), "screen", blocks=[kit.divider()] * 51)
    assert len(sent) == 1
    assert [record.getMessage() for record in caplog.records] == ['blocks break slack rules screen: "51 blocks"']


def test_send_logs_the_error_slack_names_and_still_raises(caplog):
    def refuse(**message):
        raise SlackApiError("refused", {"ok": False, "error": "not_in_channel"})

    with caplog.at_level(logging.WARNING), pytest.raises(SlackApiError):
        kit.send(refuse, "result card", channel="C1", text="card")
    assert [record.getMessage() for record in caplog.records] == ['slack rejected result card: error="not_in_channel"']


def test_send_checks_blocks_slack_sent_back_without_failing(caplog):
    echoed = [{"type": "section", "fields": [{"type": "mrkdwn"}]}]
    with caplog.at_level(logging.WARNING):
        kit.send(lambda **message: {"ok": True}, "rematch card", blocks=echoed)
    assert [record.getMessage() for record in caplog.records] == [
        'blocks break slack rules rematch card: "blocks could not be checked"']


def modules() -> list[Path]:
    return [path for path in sorted(PACKAGE.rglob("*.py")) if path.name != "blocks.py"]


def block_literals(source: str, name: str) -> list[str]:
    return [f"{name}:{node.lineno} {value.value}" for node in ast.walk(ast.parse(source)) if isinstance(node, ast.Dict)
            for key, value in zip(node.keys, node.values)
            if isinstance(key, ast.Constant) and key.value == "type"
            and isinstance(value, ast.Constant) and value.value in SLACK_TYPES]


def direct_sends(source: str, name: str) -> list[str]:
    findings = []
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id in SENDERS:
            findings.append(f"{name}:{node.lineno} {func.id}")
        elif isinstance(func, ast.Attribute) and (
                func.attr.startswith(("chat_", "views_"))
                or (func.attr == "send" and not (isinstance(func.value, ast.Name) and func.value.id == "kit"))):
            findings.append(f"{name}:{node.lineno} {func.attr}")
    return findings
