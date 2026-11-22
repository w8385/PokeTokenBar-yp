"""One move in the bot against Pokémon Showdown's recording of the same move (`tests/showdown/*.json`, written by
`tools/showdown/record.mjs`): same Pokémon, items, abilities and field, every random chance forced the same way.
The state the move leaves is compared; HP only as the sign of its change."""

import json
import random
from pathlib import Path

import pytest
from attacks import attack
from tools import generate_battle_data

from ypoke import battle, battle_data
from ypoke.battle import BaseStats, Combatant, MegaForm, _Arena, _Team

RECORDS = [json.loads(path.read_text()) for path in sorted((Path(__file__).parent / "showdown").glob("*.json"))]
OPEN_DEFECTS = {
    "knock-off-disguise": 1, "thief-disguise": 1, "rocky-helmet-disguise": 1, "air-balloon-disguise": 1,
    "kee-berry-disguise": 1,
    "life-orb-knock-off-last-hp": 2,
    "magician-substitute": 4,
    "double-kick-stamina-breaks-doll": 5, "twineedle-breaks-doll": 5,
    "air-balloon-substitute": 6,
    "core-enforcer-substitute": 7,
    "kee-berry-sheer-force": 8, "color-change-sheer-force": 8,
    "tri-attack-sheer-force": 9, "scale-shot-sheer-force": 9,
    "parental-bond-crunch": 10,
    "blunder-policy-type-immune": 11,
}
LEVEL = 50
PERFECT_IVS = BaseStats(31, 31, 31, 31, 31, 31)
DOLL_HP = {"intact": 10_000, "fragile": 1}
TERRAIN_TURNS = 5
WATCHED_VOLATILES = ("leech-seed", "substitute")
FORM_OF = {"disguise": "busted", "ice-face": "noice"}
MOVE_IDS = {entry["slug"]: int(move_id) for move_id, entry in battle_data.table("moves").items()}


class ForcedChance(random.Random):
    """Every `random() < chance` lands (`lands`) or none does, while a certain one stays certain."""

    def __init__(self, lands: bool):
        super().__init__(0)
        self.draw = 0.0 if lands else 1 - 1e-9

    def random(self) -> float:
        return self.draw


@pytest.mark.parametrize("record", [
    pytest.param(record, id=name, marks=pytest.mark.xfail(
        strict=True, raises=AssertionError, reason=f"defect {OPEN_DEFECTS[name]}") if name in OPEN_DEFECTS else ())
    for record, name in ((record, record["scenario"]["name"]) for record in RECORDS)
])
def test_one_move_leaves_what_showdown_leaves(record):
    assert _bot_outcome(record) == _flat(record["end"])


def test_every_open_defect_names_a_recorded_scenario():
    assert set(OPEN_DEFECTS) <= {record["scenario"]["name"] for record in RECORDS}


def test_every_scenario_is_recorded_at_the_showdown_commit_the_battle_data_comes_from():
    assert {record["scenario"]["name"]: record["showdown"] for record in RECORDS} == {
        record["scenario"]["name"]: generate_battle_data.SHOWDOWN_COMMIT for record in RECORDS}


def _bot_outcome(record: dict) -> dict:
    scenario = record["scenario"]
    specs = (scenario["attacker"], scenario["defender"])
    rng = ForcedChance(scenario.get("chance", True))
    arena = _Arena(rng=rng, turn=1)
    teams = tuple(_Team((_combatant(spec, entry, side),), arena=arena, side=side)
                  for side, (spec, entry) in enumerate(zip(specs, record["pokemon"])))
    arena.teams = arena.weather.teams = teams
    fighters = (teams[0].active, teams[1].active)
    for spec, fighter in zip(specs, fighters):
        _set_up(spec, fighter)
    fighters[1].acted = True
    for side, laid in enumerate(scenario.get("hazards", ({}, {}))):
        arena.hazards[side].update(laid)
    if "terrain" in scenario:
        arena.terrain, arena.terrain_turns = scenario["terrain"], TERRAIN_TURNS
    before = tuple(fighter.hp for fighter in fighters)
    battle._act(1, 0, fighters, 0, arena.weather, rng, arena)
    battle._item_triggers(1, fighters, [])
    return _flat({"sides": [_state(fighter, hp) for fighter, hp in zip(fighters, before)],
                  "hazards": [dict(laid) for laid in arena.hazards], "terrain": arena.terrain})


def _combatant(spec: dict, entry: dict, side: int) -> Combatant:
    return Combatant(
        name=f"side{side}", level=LEVEL, types=tuple(entry["types"]), base=BaseStats(*entry["base"]),
        ivs=PERFECT_IVS, moves=(attack(MOVE_IDS[spec.get("move", "splash")]),), ability=spec.get("ability"),
        weight=entry["weight"],
        forms=tuple(MegaForm(tuple(form["types"]), BaseStats(*form["base"]), kind=form["kind"])
                    for form in entry["forms"]),
    )


def _set_up(spec: dict, fighter) -> None:
    fighter.item, fighter.fresh = spec.get("item"), False
    hp = spec.get("hp", "full")
    if hp != "full":
        fighter.hp = fighter.max_hp // 2 if hp == "half" else hp
    if "substitute" in spec:
        fighter.volatiles["substitute"] = DOLL_HP[spec["substitute"]]
    if spec.get("seeded"):
        fighter.volatiles["leech-seed"] = True


def _state(fighter, hp_before: int) -> dict:
    return {
        "hp": (fighter.hp > hp_before) - (fighter.hp < hp_before), "fainted": fighter.hp == 0, "item": fighter.item,
        "status": fighter.status, "boosts": {key: stages for key, stages in fighter.stages.items() if stages},
        "volatiles": [key for key in WATCHED_VOLATILES if key in fighter.volatiles],
        "ability": fighter.combatant.ability, "types": list(fighter.combatant.types),
        "form": next((form for ability, form in FORM_OF.items() if ability in fighter.once), "base"),
    }


def _flat(end: dict) -> dict:
    """`end` keyed by `attacker.item`, `defender.boosts`, …, so a failure names the facts that differ."""
    sides = {f"{who}.{fact}": value for who, state in zip(("attacker", "defender"), end["sides"])
             for fact, value in state.items()}
    return {**sides, "hazards": end["hazards"], "terrain": end["terrain"]}
