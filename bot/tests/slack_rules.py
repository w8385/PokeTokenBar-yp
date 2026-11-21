"""Slack's Block Kit rules for a message, as far as the bot's screens can break them. Slack rejects a whole screen that
breaks one (the response URL answers an error the SDK does not raise), so a screen is checked as a unit."""

ACTIONS_ELEMENTS = {"button", "static_select", "external_select", "overflow", "checkboxes", "radio_buttons",
                    "datepicker", "timepicker"}
MAX_BLOCKS, MAX_ID, MAX_OPTIONS, MAX_OPTION_TEXT, MAX_OPTION_VALUE = 50, 255, 100, 75, 150
MAX_SECTION_TEXT, MAX_ACTIONS, MAX_CONTEXT, MAX_BUTTON_VALUE, MAX_PLACEHOLDER = 3000, 25, 10, 2000, 150


def violations(blocks: list[dict]) -> list[str]:
    problems = []
    if len(blocks) > MAX_BLOCKS:
        problems.append(f"{len(blocks)} blocks")
    block_ids = [block["block_id"] for block in blocks if "block_id" in block]
    problems += [f"block_id {block_id!r} twice" for block_id in set(block_ids) if block_ids.count(block_id) > 1]
    for index, block in enumerate(blocks):
        problems += [f"block {index} ({block['type']}): {problem}" for problem in _block(block)]
    return problems


def _block(block: dict) -> list[str]:
    problems = []
    if len(block.get("block_id", "")) > MAX_ID:
        problems.append("block_id too long")
    if block["type"] == "section":
        if len(block.get("text", {}).get("text", "")) > MAX_SECTION_TEXT:
            problems.append("text too long")
        if "accessory" in block:
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
    elif block["type"] == "context" and not 1 <= len(block["elements"]) <= MAX_CONTEXT:
        problems.append(f"{len(block['elements'])} elements")
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
    if kind == "overflow" and not 2 <= len(element["options"]) <= 5:
        problems.append(f"overflow has {len(element['options'])} options")
    if kind in ("static_select", "multi_static_select"):
        problems += _choices(element)
    return problems


def _choices(select: dict) -> list[str]:
    groups = select.get("option_groups", [])
    options = [*select.get("options", []), *(option for group in groups for option in group["options"])]
    problems = []
    if "options" in select and groups:
        problems.append("both options and option_groups")
    if not 1 <= len(options) <= MAX_OPTIONS:
        problems.append(f"{len(options)} options")
    for group in groups:
        if len(group["label"]["text"]) > MAX_OPTION_TEXT:
            problems.append("group label too long")
    for option in options:
        if len(option["text"]["text"]) > MAX_OPTION_TEXT:
            problems.append(f"option text {option['text']['text']!r} too long")
        if len(option["value"]) > MAX_OPTION_VALUE:
            problems.append(f"option value {option['value']!r} too long")
    values = [option["value"] for option in options]
    problems += [f"option value {value!r} twice" for value in set(values) if values.count(value) > 1]
    initial = [*select.get("initial_options", []), *([select["initial_option"]] if "initial_option" in select else [])]
    problems += [f"initial option {option['value']!r} is not an option" for option in initial
                 if option not in options]
    return problems
