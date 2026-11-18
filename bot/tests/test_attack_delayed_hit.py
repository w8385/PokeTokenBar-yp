import random

from attacks import attack, duel, mon
from test_attack_two_turn import act, armed

from ypoke import battle
from ypoke.battle import Action
from status_moves import put

FUTURE_SIGHT, DOOM_DESIRE, PSYCHIC, FLY = attack(248), attack(353), attack(94), attack(19)


def test_future_sight_lands_at_the_end_of_the_second_turn_after():
    user, foe, arena = duel()
    armed(user, FUTURE_SIGHT)
    sent = act(user, foe, arena)
    assert (sent.effect, sent.defender_hp) == ("delayed-hit", 100)
    assert [_upkeep(user, foe, turn) for turn in (1, 2)] == [[], []]
    landed = _upkeep(user, foe, 3)
    assert [(type(event), event.move, event.defender_hp < 100) for event in landed] == [
        (Action, FUTURE_SIGHT.name, True)]
    assert arena.pending == [{}, {}]


def test_a_second_one_fails_while_one_is_pending():
    user, foe, arena = duel()
    armed(user, DOOM_DESIRE, FUTURE_SIGHT)
    act(user, foe, arena)
    assert act(user, foe, arena, index=1).failed
    assert battle._move_score(user, foe, FUTURE_SIGHT, None) == 0.0


def test_it_passes_protect_and_hits_whoever_replaced_the_target():
    user, foe, arena = duel()
    armed(user, FUTURE_SIGHT)
    act(user, foe, arena)
    _upkeep(user, foe, 1)
    _upkeep(user, foe, 2)
    newcomer = put(mon("교체", ("normal",)), arena, 1)
    newcomer.volatiles["protect"] = True
    landed = _upkeep(user, newcomer, 3)
    assert landed[0].defender == newcomer.combatant.name and newcomer.hp < newcomer.max_hp
    assert foe.hp == foe.max_hp


def test_it_lands_from_a_user_that_left_the_field():
    user, foe, arena = duel()
    armed(user, FUTURE_SIGHT)
    act(user, foe, arena)
    user.leave()
    for turn in (1, 2, 3):
        _upkeep(user, foe, turn)
    assert foe.hp < foe.max_hp
    armed(user, FUTURE_SIGHT)
    assert act(user, foe, arena, turn=4).effect == "delayed-hit"


def test_it_lands_from_a_fainted_user_without_fainting_it_again():
    user, foe, arena = duel()
    armed(user, FUTURE_SIGHT)
    act(user, foe, arena)
    user.hp = 0
    landed = [event for turn in (1, 2, 3) for event in _upkeep(user, foe, turn)]
    assert foe.hp < foe.max_hp and not landed[0].attacker_fainted


def test_a_release_that_misses_a_hidden_target_leaves_the_next_one_delayed():
    user, foe, arena = duel()
    armed(user, FUTURE_SIGHT)
    act(user, foe, arena)
    foe.volatiles["semi-invulnerable"] = FLY
    landed = [event for turn in (1, 2, 3) for event in _upkeep(user, foe, turn)]
    assert landed[0].missed and foe.hp == foe.max_hp
    del foe.volatiles["semi-invulnerable"]
    assert act(user, foe, arena, turn=4).effect == "delayed-hit"


def test_the_chooser_counts_half_of_a_delayed_hit():
    user, foe, arena = duel()
    now = battle._move_score(user, foe, PSYCHIC, None)
    later = battle._move_score(user, foe, FUTURE_SIGHT, None)
    assert later == now * FUTURE_SIGHT.power / PSYCHIC.power / 2


def _upkeep(user, foe, turn):
    events = []
    battle._terrain_upkeep(turn, (user, foe) if user.side == 0 else (foe, user), events, random.Random(0))
    return events
