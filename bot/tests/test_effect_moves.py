import random

import pytest

from ypoke import gym_battle
from ypoke.battle import (
    Action, BaseStats, Carry, Combatant, HazardDamage, MegaEvolution, MegaForm, Move, SendOut, TrickRoomEnd,
    YawnSleep, _act, _Fighter, _Team, _Weather, _yawnable, simulate,
)
from ypoke.narration import battle_turns

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100, pp=60)
ROCK_SMASH = Move("바위깨기", "fighting", 120, physical=True, accuracy=90, pp=60)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100, pp=60)
TRICK_ROOM = Move("트릭룸", "psychic", 0, physical=False, effect="trick-room")
STEALTH_ROCK = Move("스텔스록", "rock", 0, physical=False, effect="stealth-rock")
YAWN = Move("하품", "normal", 0, physical=False, effect="yawn")
THUNDER_WAVE = Move("전기자석파", "electric", 0, physical=False, accuracy=100, effect="thunder-wave")
U_TURN = Move("유턴", "bug", 70, physical=True, accuracy=100, pp=60, effect="pivot")


@pytest.mark.parametrize("side", [0, 1])
def test_trick_room_lets_the_slower_pokemon_move_first_for_five_turns(side):
    setter = wall("느림보", ["psychic"], (TRICK_ROOM, TACKLE), speed=20)
    result = simulate(sides(setter, wall("날쌘돌이", speed=150), side), seed=1)
    assert [event.effect for event in actions(result) if event.side == side][0] == "trick-room"
    assert first_mover(result, 1) == 1 - side
    assert [first_mover(result, turn) for turn in range(2, 6)] == [side] * 4
    assert TrickRoomEnd(5) in result.events
    assert first_mover(result, 6) == 1 - side
    assert sum(event.effect == "trick-room" for event in actions(result)) == 1


@pytest.mark.parametrize("side", [0, 1])
def test_trick_room_is_not_set_by_a_team_faster_than_the_foe(side):
    setter = wall("날쌘돌이", ["psychic"], (TRICK_ROOM, TACKLE), speed=150)
    result = simulate(sides(setter, wall("느림보", speed=20), side), seed=1)
    assert not any(event.effect for event in actions(result))


@pytest.mark.parametrize("side", [0, 1])
def test_stealth_rock_hurts_each_entering_foe_by_its_rock_weakness(side):
    setter = mon("돌깔이", ["rock"], (STEALTH_ROCK, ROCK_SMASH), hp=250, attack=255, defense=250, speed=150)
    foes = (mon("선봉", hp=50, attack=10, defense=50), mon("불새", ["fire", "flying"], hp=150, attack=10, defense=50),
            mon("강철", ["steel", "ground"], hp=150, attack=10, defense=50))
    result = simulate(sides((setter,), foes, side), seed=2)
    assert next(event for event in actions(result) if event.side == side).effect == "stealth-rock"
    hazards = [event for event in result.events if isinstance(event, HazardDamage)]
    assert [(event.side, event.pokemon) for event in hazards] == [(1 - side, "불새"), (1 - side, "강철")]
    for event, member, ratio in zip(hazards, foes[1:], (4, 0.25)):
        fighter = _Fighter.enter(member)
        fighter.hp -= max(1, int(fighter.max_hp * ratio / 8))
        assert event.hp == fighter.hp_percent
    assert sum(event.effect == "stealth-rock" for event in actions(result)) == 1


def test_stealth_rock_is_not_set_against_a_foe_with_no_one_left_to_come_in():
    setter = mon("돌깔이", ["rock"], (STEALTH_ROCK, ROCK_SMASH), hp=250, attack=50, defense=250)
    result = simulate((setter, wall("혼자")), seed=2)
    assert not any(event.effect for event in actions(result))


def test_rocks_that_knock_out_an_entering_member_bring_in_the_next_one():
    setter = mon("돌깔이", ["rock"], (STEALTH_ROCK, ROCK_SMASH), hp=250, attack=255, defense=250, speed=150)
    team = (mon("선봉", hp=50, attack=10, defense=50), mon("불새", ["fire", "flying"], attack=10), mon("후발", attack=10))
    result = simulate((team, (setter,)), seed=2, carried=[None, Carry(5, None), None])
    hazard = next(event for event in result.events if isinstance(event, HazardDamage) and event.pokemon == "불새")
    assert hazard.fainted and hazard.hp == 0
    sent = [(event.turn, event.member) for event in result.events if isinstance(event, SendOut) and event.side == 0]
    assert sent[:2] == [(hazard.turn, 1), (hazard.turn, 2)]


@pytest.mark.parametrize("side", [0, 1])
def test_yawn_puts_the_target_to_sleep_at_the_end_of_the_next_turn(side):
    user = wall("하마", moves=(YAWN, TACKLE), speed=150)
    result = simulate(sides(user, wall("상대"), side), seed=3)
    assert actions(result)[0].effect == "yawn"
    assert next(event for event in result.events if isinstance(event, YawnSleep)) == YawnSleep(2, 1 - side, "상대")
    assert sum(event.effect == "yawn" for event in actions(result) if event.turn <= 4) == 1


def test_yawn_is_not_used_on_a_target_that_already_has_a_status():
    result = simulate((wall("마비"), wall("하마", moves=(YAWN, TACKLE))), seed=3, carried=[Carry(100, "paralysis")])
    assert not any(event.effect for event in actions(result))


def test_switching_out_cancels_a_pending_yawn():
    yawner = mon("하마", ["fire"], (YAWN, EMBER), hp=250, attack=10, defense=250, speed=150)
    team = (mon("풀", ["grass"], (U_TURN,), hp=250, attack=10, defense=250, speed=50), wall("후발", ["water"]))
    result = simulate((team, (yawner,)), seed=4)
    first = actions(result)[:2]
    assert [(event.side, event.effect, event.pivoted) for event in first] == [(1, "yawn", False), (0, "", True)]
    assert not any(isinstance(event, YawnSleep) and event.pokemon == "풀" and event.turn == 2 for event in result.events)


def test_a_member_that_switched_out_can_be_made_drowsy_again():
    fighter = _Fighter.enter(mon("풀"))
    fighter.drowsy_at = 2
    fighter.leave()
    assert _yawnable(fighter)


@pytest.mark.parametrize("side", [0, 1])
def test_a_pivot_move_sends_its_user_back_and_the_next_member_in(side):
    pivot = mon("벌레", ["grass"], (U_TURN,), hp=250, attack=10, defense=250, speed=150)
    team = (pivot, wall("후발", ["water"]))
    foe = mon("불꽃", ["fire"], (EMBER,), hp=250, attack=10, defense=250, speed=20)
    result = simulate(sides(team, (foe,), side), seed=5)
    action = actions(result)[0]
    assert (action.side, action.move, action.pivoted) == (side, "유턴", True)
    after = result.events[result.events.index(action) + 1]
    assert after == SendOut(1, side, "후발", 1)


def test_a_pivot_move_with_no_one_waiting_stays_in():
    pivot = mon("벌레", ["grass"], (U_TURN,), speed=150)
    result = simulate((pivot, mon("불꽃", ["fire"], (EMBER,))), seed=5)
    assert not any(event.pivoted for event in actions(result))
    assert not any(isinstance(event, SendOut) for event in result.events)


def test_a_pivot_never_brings_in_the_finale_and_a_benched_member_waits_before_it():
    roster = (mon("A"), mon("B"), mon("C"))
    team = _Team(roster, finale=1)
    assert team.pivot_target() is None
    team = _Team(roster, finale=2)
    assert team.pivot_target() == 1
    team.bench_active()
    assert team.queue == [1, 0, 2]


def test_a_returning_member_keeps_its_hp_and_status_in_the_replay():
    pivot = mon("벌레", ["grass"], (U_TURN,), hp=250, attack=10, defense=250, speed=20)
    team = (pivot, mon("후발", ["water"], hp=20, defense=20))
    foe = mon("불꽃", ["fire"], (EMBER,), hp=250, attack=150, defense=250, speed=150)
    result = simulate((team, (foe,)), seed=6)
    events = gym_battle._events(result, ([0, 1], [0]), [None, None])
    switches = [event for event in events if event["type"] == "switch" and event["side"] == 0]
    assert [event["member"] for event in switches][:3] == [0, 1, 0]
    left = events.index(switches[1])
    left_with = [event["hp"] for event in events[:left] if event["side"] == 0 and "hp" in event][-1]
    assert switches[2]["hp"] == left_with < 100


@pytest.mark.parametrize("side", [0, 1])
def test_thunder_wave_paralyzes_a_faster_foe(side):
    user = wall("피카", ["electric"], (THUNDER_WAVE, TACKLE), speed=20)
    result = simulate(sides(user, wall("날쌘돌이", speed=150), side), seed=7)
    action = next(event for event in actions(result) if event.side == side)
    assert action.effect == "thunder-wave" and action.changes[0].kind == "paralysis"
    assert sum(event.effect == "thunder-wave" for event in actions(result)) == 1


def test_thunder_wave_is_not_used_on_a_slower_foe():
    result = simulate((wall("피카", ["electric"], (THUNDER_WAVE, TACKLE), speed=150), wall("느림보", speed=20)), seed=7)
    assert not any(event.effect for event in actions(result))


@pytest.mark.parametrize("types", [("ground",), ("electric",)])
def test_ground_and_electric_types_are_immune_to_thunder_wave(types):
    user, target = _Fighter.enter(mon("피카", moves=(THUNDER_WAVE,))), _Fighter.enter(mon("과녁", types))
    action = _act(1, 0, (user, target), 0, _Weather(), random.Random(0))
    assert action.failed and target.status is None
    result = simulate((wall("피카", ["electric"], (THUNDER_WAVE, TACKLE), speed=20), wall("과녁", types, speed=150)),
                      seed=7)
    assert not any(event.effect for event in actions(result))


def test_thunder_wave_fails_on_a_target_that_already_has_a_status():
    user = _Fighter.enter(mon("피카", moves=(THUNDER_WAVE,)))
    target = _Fighter.enter(mon("과녁"), Carry(100, "burn"))
    action = _act(1, 0, (user, target), 0, _Weather(), random.Random(0))
    assert action.failed and target.status == "burn"


def test_a_primal_orb_reverts_on_entry_takes_the_mega_slot_and_brings_its_weather():
    primal = MegaForm(types=("ground", "fire"), base=BaseStats(100, 180, 160, 150, 90, 90), ability="끝의대지",
                      ability_id="desolate-land", form_id=10078, kind="primal")
    stone = MegaForm(types=("normal",), base=BaseStats(80, 80, 80, 80, 80, 80), ability=None, kind="mega")
    team = (mon("그란돈", ["ground"], mega=primal), mon("둘째", mega=stone))
    result = simulate((team, (wall("상대", speed=20),)), seed=8)
    forms = [event for event in result.events if isinstance(event, MegaEvolution)]
    assert [(event.pokemon, event.kind) for event in forms] == [("그란돈", "primal")]
    lines = [line for _, turn_lines in battle_turns(result) for line in turn_lines]
    assert any("원시회귀" in line for line in lines)
    assert any("끝의대지" in line for line in lines)


def test_the_log_narrates_each_effect():
    setter = wall("느림보", ["psychic"], (TRICK_ROOM, STEALTH_ROCK, YAWN, TACKLE), speed=20)
    result = simulate(((setter,), (wall("날쌘돌이", speed=150), wall("후발", ["fire", "flying"]))), seed=1)
    text = "\n".join(line for _, turn_lines in battle_turns(result) for line in turn_lines)
    assert "공간이 뒤틀렸다" in text and "돌이 떠 있다" in text and "졸음" in text


def mon(name, types=("normal",), moves=(TACKLE,), level=50, hp=80, attack=80, defense=80, speed=80, mega=None):
    return Combatant(name=name, level=level, types=tuple(types), base=BaseStats(hp, attack, defense, attack, defense, speed),
                     ivs=IVS, moves=tuple(moves), mega=mega)


def wall(name, types=("normal",), moves=(TACKLE,), speed=80):
    return mon(name, types, moves, hp=250, attack=20, defense=250, speed=speed)


def sides(mine, theirs, side):
    """`mine` fights on `side`; returns the pair in simulate's order."""
    return (mine, theirs) if side == 0 else (theirs, mine)


def actions(result):
    return [event for event in result.events if isinstance(event, Action)]


def first_mover(result, turn):
    return next(event.side for event in actions(result) if event.turn == turn)
