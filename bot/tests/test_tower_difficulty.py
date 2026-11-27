"""The tower's difficulty, pinned loosely: a fixed reference team's win rate per stretch of the climb stays in a band.
The battles run offline on the committed move data and `tower_learnsets.json`; the bands come from
`tools/tower_balance.py` runs and are wide enough for any small engine change, so a test failure means the tower got
much easier or much harder."""

import json
from functools import cache
from pathlib import Path

import pytest

from tools import tower_balance
from ypoke import abilities, foe_moves, pokeapi
from ypoke.upload_server import validate_members

LEARNSETS_TABLE = json.loads(Path(__file__).with_name("tower_learnsets.json").read_text())
FORM_SPECIES = {form_id: species for forms in abilities.FORMS.values() for species, kinds in forms.items()
                for form_id in kinds.values() if form_id is not None}
PARTY = "ref-pseudo"
BANDS = {
    "set1-2": ((range(1, 20), range(4)), 0.85, 1.0),
    "set3-4": ((range(21, 41), range(4)), 0.5, 0.85),
    "owner20": (((20,), range(24)), 0.04, 0.35),
    "set5": ((range(41, 50), range(6)), 0.4, 0.8),
    "owner50": (((50,), range(24)), 0.04, 0.25),
}


class OfflineAPI:
    """Base stats and types of `foe_moves.json`; an ability's form fights with its species' own."""

    def pokemon(self, pokemon_id):
        foe = foe_moves.species(FORM_SPECIES.get(pokemon_id, pokemon_id))
        weight = LEARNSETS_TABLE.get(str(pokemon_id), {}).get("weight", 0)
        return {"name_ko": f"#{pokemon_id}", "types": list(foe.types), "base": dict(foe.stats), "weight": weight}

    def attacking_moves(self, pokemon_id, level, chosen=(), status=False):
        return [{**pokeapi.data_move(move_id), "level": 1, "source": "level"} for move_id in chosen or ()]

    def can_evolve(self, pokemon_id):
        return False


@pytest.mark.parametrize("stretch", sorted(BANDS))
def test_a_reference_team_wins_each_stretch_of_the_climb_within_its_band(stretch):
    (battles, runs), low, high = BANDS[stretch]
    fights = [tower_balance.fight(OfflineAPI(), _team(), run, battle) for battle in battles for run in runs]
    rate = sum(fights) / len(fights)
    assert low <= rate <= high, f"{stretch}: {rate:.0%} outside {low:.0%}..{high:.0%}"


@cache
def _team():
    return validate_members([dict(member) for member in tower_balance.PARTIES[PARTY]], "team")
