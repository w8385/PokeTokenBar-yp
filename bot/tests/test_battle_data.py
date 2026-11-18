import copy
import json
import os

import pytest

from ypoke import abilities, battle_data, items, mega_stones, move_effects, move_power, pokeapi, tera_forms

BASELINE = battle_data.DATA_DIR / "coverage-baseline.json"
BOT_KEYS = {
    "items": items.EFFECT_KEYS | mega_stones.ITEM_EFFECT_KEYS | tera_forms.EFFECT_KEYS,
    "abilities": abilities.EFFECT_KEYS,
    "moves": move_effects.EFFECT_KEYS | move_power.EFFECT_KEYS | pokeapi.EFFECT_KEYS | {mega_stones.DRAGON_ASCENT},
}


def test_every_entry_is_classified_and_the_todo_list_only_shrinks():
    data = _data()
    for kind, counts in coverage_counts(data).items():
        print(f"{kind}: {counts}")
    assert coverage_errors(data, json.loads(BASELINE.read_text()), BOT_KEYS) == []


def test_a_new_todo_entry_fails_the_ratchet():
    data, baseline = _data(), _baseline()
    data["items"]["leftovers"]["effect"] = "todo"
    assert any("leftovers" in error and "not in the baseline" in error
               for error in coverage_errors(data, baseline, BOT_KEYS))


def test_a_baseline_id_that_is_no_longer_todo_fails_the_ratchet():
    data, baseline = _data(), _baseline()
    stale = baseline["abilities"]["todo"][0]
    data["abilities"][stale]["effect"] = {"inert": "test"}
    assert any(stale in error and "no longer todo" in error for error in coverage_errors(data, baseline, BOT_KEYS))


def test_an_effect_key_the_bot_lacks_fails():
    data = _data()
    data["moves"]["1"]["effect"] = ["damage", "made-up-key"]
    assert any("made-up-key" in error for error in coverage_errors(data, _baseline(), BOT_KEYS))


def test_a_bot_key_no_entry_names_fails():
    keys = {**BOT_KEYS, "abilities": BOT_KEYS["abilities"] | {"unused-key"}}
    assert any("unused-key" in error for error in coverage_errors(_data(), _baseline(), keys))


@pytest.mark.parametrize("effect", [None, 5, {"inert": ""}, [], ["todo"]])
def test_a_malformed_effect_fails(effect):
    data = _data()
    data["items"]["leftovers"]["effect"] = effect
    assert any("leftovers" in error and "malformed" in error for error in coverage_errors(data, _baseline(), BOT_KEYS))


def test_the_files_round_trip_through_the_loader_unchanged(tmp_path, monkeypatch):
    texts = {kind: battle_data.path(kind).read_text() for kind in battle_data.KINDS}
    monkeypatch.setattr(battle_data, "DATA_DIR", tmp_path)
    for kind, text in texts.items():
        battle_data.write(kind, json.loads(text))
        assert battle_data.path(kind).read_text() == text


@pytest.mark.skipif(not os.environ.get("WRITE_BASELINE"), reason="WRITE_BASELINE=1 rewrites the baseline")
def test_write_baseline():
    data = _data()
    baseline = {kind: {"counts": counts, "todo": sorted(_todo_names(data[kind]))}
                for kind, counts in coverage_counts(data).items()}
    BASELINE.write_text(json.dumps(baseline, indent=1, ensure_ascii=False) + "\n")


def coverage_errors(data: dict, baseline: dict, bot_keys: dict) -> list[str]:
    """Why the data breaks the coverage rules, empty when it holds: every entry is classified, todo only shrinks,
    every key exists in the bot and every bot key is used."""
    errors = []
    for kind, entries in data.items():
        errors += [f"{kind} {name}: malformed effect {entry.get('effect')!r}" for name, entry in entries.items()
                   if not _well_formed(entry.get("effect"))]
        todo, listed = _todo_names(entries), set(baseline[kind]["todo"])
        errors += [f"{kind} {name}: todo but not in the baseline" for name in sorted(todo - listed)]
        errors += [f"{kind} {name}: in the baseline but no longer todo" for name in sorted(listed - todo)]
        used = {key for entry in entries.values() if _well_formed(entry.get("effect"))
                for key in battle_data.keys(entry)}
        errors += [f"{kind}: effect key {key} is not in the bot" for key in sorted(used - bot_keys[kind])]
        errors += [f"{kind}: bot key {key} is named by no entry" for key in sorted(bot_keys[kind] - used)]
        if baseline[kind]["counts"] != coverage_counts(data)[kind]:
            errors.append(f"{kind}: counts {coverage_counts(data)[kind]} differ from the baseline")
    return errors


def coverage_counts(data: dict) -> dict:
    return {kind: {"implemented": sum(not battle_data.is_inert(entry) and not battle_data.is_todo(entry)
                                      for entry in entries.values()),
                   "inert": sum(battle_data.is_inert(entry) for entry in entries.values()),
                   "todo": sum(battle_data.is_todo(entry) for entry in entries.values())}
            for kind, entries in data.items()}


def _todo_names(entries: dict) -> set[str]:
    return {name for name, entry in entries.items() if battle_data.is_todo(entry)}


def _well_formed(effect) -> bool:
    if isinstance(effect, dict):
        return set(effect) == {"inert"} and isinstance(effect["inert"], str) and bool(effect["inert"])
    if isinstance(effect, str):
        return bool(effect)
    return (isinstance(effect, list) and all(isinstance(key, str) and key for key in effect)
            and any(key != battle_data.TODO for key in effect))


def _data() -> dict:
    return {kind: copy.deepcopy(battle_data.table(kind)) for kind in battle_data.KINDS}


def _baseline() -> dict:
    return json.loads(BASELINE.read_text())
