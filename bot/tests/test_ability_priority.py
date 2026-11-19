import random
from dataclasses import replace

import pytest
from attacks import attack
from status_moves import resolve
from test_ability_damage import TACKLE, facing
from test_battle import mon
from test_held_items_more import FixedRng

from ypoke import battle
from ypoke.battle import (
    AbilityAct,
    Action,
    _enter_battle,
    _Fighter,
    _quick_claws,
    _turn_order,
    _Weather,
)
from ypoke.narration import battle_turns

THUNDER_WAVE, SWORDS_DANCE, RECOVER, GIGA_DRAIN = attack(86), attack(14), attack(105), attack(202)
EXPLOSION, MIND_BLOWN, STEEL_BEAM = attack(153), attack(720), attack(796)
FEATHER_DANCE, PETAL_DANCE, DRAGON_DANCE, QUICK_ATTACK = attack(297), attack(80), attack(349), attack(98)


@pytest.mark.parametrize(("ability", "move", "priority"), [
    ("prankster", THUNDER_WAVE, 1), ("prankster", SWORDS_DANCE, 1), ("prankster", TACKLE, 0),
    ("triage", RECOVER, 3), ("triage", GIGA_DRAIN, 3), ("triage", TACKLE, 0), (None, RECOVER, 0),
])
def test_the_ability_raises_the_priority_of_its_moves_only(ability, move, priority):
    user, _, _ = facing(ability)
    assert battle._move_priority(user, move) == priority


def test_a_prankster_status_move_fails_on_a_dark_foe_only_when_aimed_at_it():
    user, foe, arena = facing("prankster", foe_types=("dark",))
    action = resolve(user, foe, THUNDER_WAVE, arena)
    assert (action.failed, action.blocked, foe.status) == (True, "prankster", None)
    assert battle._wasted_on(user, foe, THUNDER_WAVE)
    resolve(user, foe, SWORDS_DANCE, arena)
    assert user.stages["attack"] == 2
    user, foe, arena = facing("prankster")
    resolve(user, foe, THUNDER_WAVE, arena)
    assert foe.status == "paralysis"


@pytest.mark.parametrize(("move", "blocked"), [(THUNDER_WAVE, "dazzling"), (SWORDS_DANCE, "")])
def test_a_priority_block_stops_a_prankster_move_only_when_it_is_aimed_at_the_holder(move, blocked):
    user, foe, arena = facing("prankster", "dazzling")
    assert resolve(user, foe, move, arena).blocked == blocked


@pytest.mark.parametrize(("ability", "move", "order"), [
    ("stall", TACKLE, (1, 0)), ("stall", QUICK_ATTACK, (0, 1)), (None, TACKLE, (0, 1)),
    ("mycelium-might", THUNDER_WAVE, (1, 0)), ("mycelium-might", TACKLE, (0, 1)),
])
def test_the_ability_moves_its_faster_holder_last_in_its_bracket(ability, move, order):
    fast = _Fighter.enter(replace(mon("빠름", ("normal",), moves=(move,), speed=200), ability=ability))
    slow = _Fighter.enter(mon("느림", ("normal",), speed=10))
    assert _turn_order((fast, slow), (0, 0), random.Random(0)) == order


@pytest.mark.parametrize(("ability", "status"), [("mycelium-might", "paralysis"), (None, None)])
def test_mycelium_might_leaves_the_targets_ability_out_of_a_status_move(ability, status):
    user, foe, arena = facing(ability, "volt-absorb")
    resolve(user, foe, THUNDER_WAVE, arena)
    assert foe.status == status


def test_quick_draw_may_put_its_holder_first_with_an_attack_only():
    slow = _Fighter.enter(replace(mon("느림", ("normal",), speed=10), ability="quick-draw"))
    fast = _Fighter.enter(mon("빠름", ("normal",), speed=200))
    events = []
    assert _quick_claws(1, (slow, fast), (0, 0), None, FixedRng(0.1), events) == (True, False)
    assert [(type(event), event.effect) for event in events] == [(AbilityAct, "first")]
    assert _quick_claws(1, (slow, fast), (0, 0), None, FixedRng(0.5), []) == (False, False)
    slow.combatant = replace(slow.combatant, moves=(SWORDS_DANCE,))
    assert _quick_claws(1, (slow, fast), (0, 0), None, FixedRng(0.1), []) == (False, False)


def test_unburden_doubles_speed_once_the_item_it_entered_with_is_gone():
    user, foe, _ = facing("unburden")
    user.item = "sitrus-berry"
    _enter_battle((user, foe), _Weather(), random.Random(0))
    speed = user.stat("speed")
    user.item = None
    assert user.stat("speed") == 2 * speed
    user.leave()
    _enter_battle((user, foe), _Weather(), random.Random(0))
    assert user.stat("speed") == speed
    bare, foe, _ = facing("unburden")
    _enter_battle((bare, foe), _Weather(), random.Random(0))
    assert bare.stat("speed") == speed


@pytest.mark.parametrize(("ability", "weather", "doubled"), [
    ("slush-rush", "snow", True), ("slush-rush", "hail", True), ("slush-rush", "rain", False),
    ("sand-rush", "sandstorm", True), ("sand-rush", "snow", False),
])
def test_a_weather_rush_doubles_speed_in_its_weather(ability, weather, doubled):
    user, _, _ = facing(ability)
    plain, _, _ = facing()
    assert user.stat("speed", weather) == plain.stat("speed", weather) * (2 if doubled else 1)


def test_sand_rush_keeps_off_the_sandstorm_chip():
    rusher, _, _ = facing("sand-rush")
    plain, _, _ = facing()
    assert not battle._chipped_by(rusher, "sandstorm") and battle._chipped_by(plain, "sandstorm")


def test_truant_acts_then_loafs_and_starts_over_on_entering():
    user, foe, arena = facing("truant", attack=10)
    moved = [resolve(user, foe, TACKLE, arena).move for _ in range(3)]
    assert moved == [TACKLE.name, "", TACKLE.name]
    assert resolve(user, foe, TACKLE, arena).blocked == "truant"
    user.leave()
    assert resolve(user, foe, TACKLE, arena).move == TACKLE.name


@pytest.mark.parametrize(("ability", "move", "paid"), [
    ("pressure", TACKLE, 2), ("pressure", THUNDER_WAVE, 2), ("pressure", SWORDS_DANCE, 1), (None, TACKLE, 1),
])
def test_pressure_charges_an_extra_pp_for_a_move_aimed_at_the_holder(ability, move, paid):
    user, foe, arena = facing(None, ability)
    resolve(user, foe, move, arena)
    assert move.pp - user.pp[0] == paid


@pytest.mark.parametrize("move", [EXPLOSION, MIND_BLOWN])
def test_damp_stops_a_self_ko_move_and_its_user_stays_in(move):
    user, foe, arena = acting(move, "damp")
    action = battle._act(1, 0, (user, foe), 0, _Weather(), random.Random(0), arena)
    assert (action.failed, action.blocked) == (True, "damp")
    assert (user.hp, foe.hp) == (user.max_hp, foe.max_hp)
    assert battle._wasted_on(user, foe, move)


@pytest.mark.parametrize(("move", "foe_ability"), [(EXPLOSION, None), (STEEL_BEAM, "damp")])
def test_a_self_ko_or_hp_cost_move_goes_off_where_damp_does_not_cover_it(move, foe_ability):
    user, foe, arena = acting(move, foe_ability)
    action = battle._act(1, 0, (user, foe), 0, _Weather(), random.Random(0), arena)
    assert not action.blocked and user.hp < user.max_hp


def test_a_dancer_repeats_the_foes_dance_and_aims_it_back():
    user, dancer, _, copied = danced(FEATHER_DANCE)
    assert [type(event) for event in copied] == [AbilityAct, Action]
    assert copied[0].effect == "dance" and (copied[1].side, copied[1].move_id) == (1, FEATHER_DANCE.id)
    assert dancer.stages["attack"] == -2 and user.stages["attack"] == -2


def test_a_dancer_copies_a_self_boost_asleep_without_paying_pp():
    _, dancer, _, copied = danced(DRAGON_DANCE, asleep=True)
    assert copied and dancer.stages["attack"] == dancer.stages["speed"] == 1
    assert dancer.pp == [move.pp for move in dancer.combatant.moves]


def test_a_dancer_is_not_locked_into_a_copied_petal_dance():
    _, dancer, _, copied = danced(PETAL_DANCE)
    assert copied and not dancer.volatiles
    assert all(change.kind != "rampage" for change in copied[1].changes)


@pytest.mark.parametrize(("move", "ability", "blocked"), [
    (SWORDS_DANCE, None, False), (TACKLE, "dancer", False), (SWORDS_DANCE, "dancer", True),
])
def test_nothing_is_copied_without_a_dance_dancer_or_a_used_move(move, ability, blocked):
    _, dancer, _, copied = danced(move, ability=ability, blocked=blocked)
    assert copied == () and sum(dancer.stages.values()) == 0


@pytest.mark.parametrize(("event", "line"), [
    (Action(1, 0, "사용자", "상대", THUNDER_WAVE.name, failed=True, blocked="prankster"),
     "🔵 사용자 › 전기자석파 → [짓궂은마음] 악 타입에는 통하지 않았다"),
    (Action(1, 0, "사용자", "상대", EXPLOSION.name, failed=True, blocked="damp"), "🔵 사용자 › 대폭발 → [습기]에 막힘"),
    (AbilityAct(1, 1, "상대", "dancer", effect="dance"), "🔴 상대 [무희] 따라 춤췄다"),
])
def test_the_lines_name_the_ability(event, line):
    opening = Action(1, 0, "사용자", "상대", TACKLE.name)
    [(_, lines)] = battle_turns(battle.BattleResult(winner=0, turns=1, events=[opening, event]))
    assert lines[1:] == [line]


def acting(move, foe_ability):
    user, foe, arena = facing(None, foe_ability, attack=10, special_attack=10)
    user.combatant = replace(user.combatant, moves=(move,))
    user.pp = [move.pp]
    return user, foe, arena


def danced(move, ability="dancer", asleep=False, blocked=False):
    """The user dances at a foe holding `ability`; the user, the foe and what the foe copied."""
    user, dancer, arena = facing(None, ability, attack=10, special_attack=10)
    dancer.combatant = replace(dancer.combatant, moves=(TACKLE,))
    dancer.pp = [TACKLE.pp]
    if asleep:
        dancer.status, dancer.sleep_left = "sleep", 3
    action = resolve(user, dancer, move, arena)
    if blocked:
        action = replace(action, move="", blocked="paralysis")
    copied = battle._danced(1, 0, (user, dancer), action, 0, _Weather(), random.Random(0), arena)
    return user, dancer, arena, copied
