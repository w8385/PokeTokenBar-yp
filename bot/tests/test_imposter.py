import random
from dataclasses import replace

import pytest
from status_moves import data_move, put
from test_battle import FLAMETHROWER, mon

from ypoke import battle
from ypoke.battle import (
    AbilityTransform, Action, BaseStats, MegaEvolution, MegaForm, SendOut, _Arena, _Team, _Weather, simulate,
)
from ypoke.gym_battle import _events
from ypoke.narration import battle_log

TRANSFORM = data_move(144)
DITTO_ID, DINGLU_ID, MEGA_ID = 132, 1003, 10034
DITTO = replace(mon("메타몽", ("normal",), hp=48, attack=48, defense=48, special_attack=48, special_defense=48,
                    speed=48, moves=(TRANSFORM,)), ability="imposter", pokemon_id=DITTO_ID)
DINGLU = replace(mon("딩루", ("dark", "ground"), hp=155, attack=110, defense=125, special_attack=55,
                     special_defense=80, speed=45, moves=(FLAMETHROWER,)), pokemon_id=DINGLU_ID)
MEGA = MegaForm(types=("fire", "dragon"), base=BaseStats(78, 130, 111, 130, 85, 100), ability="단단한발톱",
                form_id=MEGA_ID)


def test_imposter_lead_becomes_the_foe_and_fights_with_its_moves():
    result = simulate(((DITTO,), (DINGLU,)), seed=3)
    transform = next(event for event in result.events if isinstance(event, AbilityTransform))
    assert (transform.side, transform.pokemon, transform.ability, transform.into) == (0, "메타몽", "imposter", "딩루")
    assert {event.move for event in result.events if isinstance(event, Action) and event.side == 0} == {
        FLAMETHROWER.name}
    assert any("메타몽 [괴짜] 딩루로 변신" in block for block in battle_log(result))


def test_imposter_replacement_transforms_as_it_comes_in_after_a_faint():
    lead = replace(mon("첫째", ("normal",), level=5), pokemon_id=19)
    result = simulate(((lead, DITTO), (DINGLU,)), seed=3)
    events = result.events
    index = next(i for i, event in enumerate(events) if isinstance(event, SendOut) and event.pokemon == "메타몽")
    assert isinstance(events[index + 1], AbilityTransform) and events[index + 1].into == "딩루"


@pytest.mark.parametrize("state", ["substitute", "transform"])
def test_imposter_fails_on_a_foe_behind_a_substitute_or_transformed(state):
    ditto, _, triggers = entered(state)
    assert not triggers and ditto.combatant.moves == (TRANSFORM,) and "transform" not in ditto.volatiles


def test_imposter_still_copies_a_foe_hidden_in_the_air():
    ditto, foe, _ = entered("semi-invulnerable")
    assert ditto.combatant.moves == (FLAMETHROWER,) and ditto.stats == foe.stats
    assert ditto.pp == [min(5, FLAMETHROWER.pp)] and ditto.combatant.types == ("dark", "ground")


def test_imposter_keeps_the_base_form_it_copied_when_the_foe_mega_evolves_later():
    arena = _Arena()
    teams = (_Team((DITTO,), arena=arena), _Team((replace(DINGLU, mega=MEGA),), arena=arena, side=1))
    arena.teams = teams
    weather = _Weather(None, 0)
    battle._enter_battle((teams[0].active, teams[1].active), weather, random.Random(0))
    copied = dict(teams[0].active.stats)
    events = []
    battle._mega_evolutions(teams, 1, weather, random.Random(0), events)
    assert isinstance(events[0], MegaEvolution) and teams[1].active.stats != copied
    assert teams[0].active.stats == copied and teams[0].active.combatant.types == ("dark", "ground")


def test_imposter_replay_shows_the_foes_form_and_ditto_again_when_it_faints():
    result = simulate(((DITTO,), (replace(DINGLU, level=70),)), seed=3)
    forms = [(event["side"], event["pokemon_id"], event["kind"]) for event in _events(result, ([0], [0]), [None])
             if event["type"] == "form"]
    assert forms == [(0, DINGLU_ID, "transform"), (0, DITTO_ID, "revert")]


def test_imposter_shows_the_form_a_foe_already_took():
    *_, triggers = entered(form_id=MEGA_ID)
    assert [(trigger.form_id, trigger.own_form_id) for trigger in triggers] == [(MEGA_ID, DITTO_ID)]


def entered(state=None, form_id=None):
    """Ditto entering against Dingru that is in `state` and shows `form_id`."""
    arena = _Arena()
    ditto, foe = put(DITTO, arena), put(DINGLU, arena, 1)
    foe.form_id = form_id
    if state:
        foe.volatiles[state] = True
    return ditto, foe, battle._enter_battle((ditto, foe), _Weather(None, 0), random.Random(0), (0,))
