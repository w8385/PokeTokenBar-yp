"""Slack Block Kit pieces as plain dicts, each checked against Slack's rules when built, and `send`, the one way a
message reaches Slack. Slack rejects a whole message that breaks one rule, and a response URL answers that
rejection instead of raising, so both the pieces and the sent message are checked."""

import json
import logging
from collections.abc import Callable, Iterable

from slack_sdk.errors import SlackApiError

ACTIONS_ELEMENTS = {"button", "static_select", "external_select", "overflow", "checkboxes", "radio_buttons",
                    "datepicker", "timepicker"}
ACCESSORY_ELEMENTS = ACTIONS_ELEMENTS | {"image", "multi_static_select", "multi_external_select"}
CONTEXT_ELEMENTS = {"image", "mrkdwn", "plain_text"}
MAX_BLOCKS, MAX_ID, MAX_OPTIONS, MAX_OPTION_TEXT, MAX_OPTION_VALUE = 50, 255, 100, 75, 150
MAX_SECTION_TEXT, MAX_ACTIONS, MAX_CONTEXT, MAX_BUTTON_VALUE, MAX_PLACEHOLDER = 3000, 25, 10, 2000, 150
MAX_FIELDS, MAX_FIELD_TEXT, MAX_HEADER_TEXT = 10, 2000, 150
LOG_LIMIT = 200

log = logging.getLogger(__name__)


class BlockError(ValueError):
    """A piece Slack would refuse."""


def mrkdwn(text: str) -> dict:
    return {"type": "mrkdwn", "text": text}


def plain(text: str) -> dict:
    return {"type": "plain_text", "text": text}


def option(text: str, value: str) -> dict:
    """A label longer than Slack allows is cut; a long value raises, since a cut value would mean another thing."""
    return _checked(_option, {"text": plain(text[:MAX_OPTION_TEXT]), "value": value})


def option_group(label: str, options: list[dict]) -> dict:
    if len(label) > MAX_OPTION_TEXT or not 1 <= len(options) <= MAX_OPTIONS:
        raise BlockError(f"option group {label!r}")
    return {"label": plain(label), "options": options}


def button(text: str, action_id: str, value: str | None = None, *, style: str | None = None,
           url: str | None = None) -> dict:
    element = {"type": "button", "action_id": action_id, "text": plain(text[:MAX_OPTION_TEXT])}
    if value is not None:
        element["value"] = value
    if style is not None:
        element["style"] = style
    if url is not None:
        element["url"] = url
    return _checked(_element, element)


def static_select(action_id: str, placeholder: str, options: list[dict] | None = None, *,
                  option_groups: list[dict] | None = None, initial_option: dict | None = None) -> dict:
    element = {"type": "static_select", "action_id": action_id, "placeholder": plain(placeholder)}
    if options is not None:
        element["options"] = options
    if option_groups is not None:
        element["option_groups"] = option_groups
    if initial_option is not None:
        element["initial_option"] = initial_option
    return _checked(_element, element)


def external_select(action_id: str, placeholder: str, *, initial_option: dict | None = None,
                    min_query_length: int = 0) -> dict:
    """A select whose options come from an options request for `action_id`."""
    element = {"type": "external_select", "action_id": action_id, "placeholder": plain(placeholder),
               "min_query_length": min_query_length}
    if initial_option is not None:
        element["initial_option"] = initial_option
    return _checked(_element, element)


def multi_external_select(action_id: str, placeholder: str, *, max_selected_items: int,
                          initial_options: list[dict] | None = None, min_query_length: int = 0) -> dict:
    element = {"type": "multi_external_select", "action_id": action_id, "placeholder": plain(placeholder),
               "min_query_length": min_query_length, "max_selected_items": max_selected_items}
    if initial_options:
        element["initial_options"] = initial_options
    return _checked(_element, element)


def overflow(action_id: str, options: list[dict]) -> dict:
    return _checked(_element, {"type": "overflow", "action_id": action_id, "options": options})


def image(url: str, alt_text: str) -> dict:
    """An image element: a section's accessory or a context element."""
    return {"type": "image", "image_url": url, "alt_text": alt_text}


def section(text: str | None = None, *, block_id: str | None = None, accessory: dict | None = None,
            fields: Iterable[str] | None = None) -> dict:
    block = {"type": "section"}
    if block_id is not None:
        block["block_id"] = block_id
    if text is not None:
        block["text"] = mrkdwn(text)
    if fields is not None:
        block["fields"] = [mrkdwn(field) for field in fields]
    if accessory is not None:
        block["accessory"] = accessory
    return _checked(_block, block)


def actions(elements: list[dict], *, block_id: str | None = None) -> dict:
    block = {"type": "actions", "elements": elements}
    if block_id is not None:
        block["block_id"] = block_id
    return _checked(_block, block)


def context(*elements: str | dict) -> dict:
    """Each `str` is a mrkdwn text; a dict is an element as built (an `image`)."""
    return _checked(_block, {"type": "context",
                             "elements": [mrkdwn(element) if isinstance(element, str) else element
                                          for element in elements]})


def divider() -> dict:
    return {"type": "divider"}


def header(text: str) -> dict:
    return _checked(_block, {"type": "header", "text": plain(text)})


def file_image(file_id: str, alt_text: str, title: str) -> dict:
    """An image block of a file uploaded to Slack."""
    return {"type": "image", "slack_file": {"id": file_id}, "alt_text": alt_text, "title": plain(title)}


def send(call: Callable, source: str, **message):
    """Send `message` with `call`: a WebClient method (`chat_postMessage`, `chat_postEphemeral`, `chat_update`,
    `views_*`), a response URL's `respond` or a webhook's `send`. Logs a broken rule and Slack's refusal in one line
    each, never the message; returns Slack's reply, and a WebClient refusal still raises."""
    view = message.get("view") or {}
    try:
        problems = violations(message.get("blocks") or view.get("blocks") or [])
    except (KeyError, TypeError, AttributeError):
        problems = ["blocks could not be checked"]
    if problems:
        log.warning("blocks break slack rules %s: %s", source, _quoted("; ".join(problems)))
    try:
        response = call(**message)
    except SlackApiError as error:
        log.warning("slack rejected %s: error=%s", source, _quoted(error.response.get("error")))
        raise
    status = getattr(response, "status_code", 200)
    if status != 200:
        log.warning("response url rejected %s: status=%s body=%s", source, status,
                    _quoted(getattr(response, "body", "")))
    return response


def violations(blocks: list[dict]) -> list[str]:
    """Every rule `blocks` breaks as one message."""
    problems = []
    if len(blocks) > MAX_BLOCKS:
        problems.append(f"{len(blocks)} blocks")
    block_ids = [block["block_id"] for block in blocks if "block_id" in block]
    problems += [f"block_id {block_id!r} twice" for block_id in set(block_ids) if block_ids.count(block_id) > 1]
    for index, block in enumerate(blocks):
        problems += [f"block {index} ({block['type']}): {problem}" for problem in _block(block)]
    return problems


def _checked(rules: Callable[[dict], list[str]], piece: dict) -> dict:
    problems = rules(piece)
    if problems:
        raise BlockError("; ".join(problems))
    return piece


def _quoted(value: object) -> str:
    return json.dumps(str(value)[:LOG_LIMIT], ensure_ascii=False)


def _block(block: dict) -> list[str]:
    problems = []
    if len(block.get("block_id", "")) > MAX_ID:
        problems.append("block_id too long")
    if block["type"] == "section":
        if len(block.get("text", {}).get("text", "")) > MAX_SECTION_TEXT:
            problems.append("text too long")
        fields = block.get("fields", [])
        if len(fields) > MAX_FIELDS:
            problems.append(f"{len(fields)} fields")
        problems += ["field too long" for field in fields if len(field["text"]) > MAX_FIELD_TEXT]
        if "accessory" in block:
            if block["accessory"]["type"] not in ACCESSORY_ELEMENTS:
                problems.append(f"{block['accessory']['type']} is not allowed as an accessory")
            problems += _element(block["accessory"])
    elif block["type"] == "actions":
        elements = block["elements"]
        action_ids = [element["action_id"] for element in elements if "action_id" in element]
        if not 1 <= len(elements) <= MAX_ACTIONS:
            problems.append(f"{len(elements)} elements")
        problems += [f"action_id {action_id!r} twice" for action_id in set(action_ids) if action_ids.count(action_id) > 1]
        for element in elements:
            if element["type"] not in ACTIONS_ELEMENTS:
                problems.append(f"{element['type']} is not allowed in an actions block")
            problems += _element(element)
    elif block["type"] == "context":
        if not 1 <= len(block["elements"]) <= MAX_CONTEXT:
            problems.append(f"{len(block['elements'])} elements")
        problems += [f"{element['type']} is not allowed in a context block" for element in block["elements"]
                     if element["type"] not in CONTEXT_ELEMENTS]
    elif block["type"] == "header" and len(block["text"]["text"]) > MAX_HEADER_TEXT:
        problems.append("header too long")
    return problems


def _element(element: dict) -> list[str]:
    problems = []
    kind = element["type"]
    if len(element.get("action_id", "")) > MAX_ID:
        problems.append(f"{kind}: action_id too long")
    if len(element.get("placeholder", {}).get("text", "")) > MAX_PLACEHOLDER:
        problems.append(f"{kind}: placeholder too long")
    if kind == "button":
        if len(element["text"]["text"]) > MAX_OPTION_TEXT:
            problems.append("button text too long")
        if len(element.get("value", "")) > MAX_BUTTON_VALUE:
            problems.append("button value too long")
    if kind == "overflow":
        if not 2 <= len(element["options"]) <= 5:
            problems.append(f"overflow has {len(element['options'])} options")
        problems += [problem for choice in element["options"] for problem in _option(choice)]
    if kind in ("static_select", "multi_static_select"):
        problems += _choices(element)
    if kind in ("external_select", "multi_external_select"):
        problems += _typed_choices(element)
    return problems


def _typed_choices(select: dict) -> list[str]:
    """A select whose options come from an options request: no inline options, and its picked options are well formed."""
    problems = []
    if "options" in select or "option_groups" in select:
        problems.append("inline options on a typed-search select")
    if not isinstance(select.get("min_query_length"), int):
        problems.append("min_query_length missing")
    initial = [*select.get("initial_options", []), *([select["initial_option"]] if "initial_option" in select else [])]
    if len(initial) > select.get("max_selected_items", 1):
        problems.append(f"{len(initial)} initial options over max_selected_items")
    for choice in initial:
        if _option(choice):
            problems.append(f"initial option {choice['value']!r} too long")
    return problems


def _choices(select: dict) -> list[str]:
    groups = select.get("option_groups", [])
    options = [*select.get("options", []), *(choice for group in groups for choice in group["options"])]
    problems = []
    if "options" in select and groups:
        problems.append("both options and option_groups")
    if not 1 <= len(options) <= MAX_OPTIONS:
        problems.append(f"{len(options)} options")
    for group in groups:
        if len(group["label"]["text"]) > MAX_OPTION_TEXT:
            problems.append("group label too long")
    for choice in options:
        problems += _option(choice)
    values = [choice["value"] for choice in options]
    problems += [f"option value {value!r} twice" for value in set(values) if values.count(value) > 1]
    initial = [*select.get("initial_options", []), *([select["initial_option"]] if "initial_option" in select else [])]
    problems += [f"initial option {choice['value']!r} is not an option" for choice in initial
                 if choice not in options]
    return problems


def _option(choice: dict) -> list[str]:
    problems = []
    if len(choice["text"]["text"]) > MAX_OPTION_TEXT:
        problems.append(f"option text {choice['text']['text']!r} too long")
    if len(choice["value"]) > MAX_OPTION_VALUE:
        problems.append(f"option value {choice['value']!r} too long")
    return problems
