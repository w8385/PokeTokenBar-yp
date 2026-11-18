from dataclasses import replace

import pytest
from attacks import attack, draws, duel
from status_moves import data_move, resolve

from ypoke import battle

TRIPLE_KICK, TRIPLE_AXEL, POPULATION_BOMB = attack(167), attack(813), attack(860)
LOCK_ON = data_move(199)
LANDS, NO_CRIT, MISSES = 0.0, 0.99, 0.99


def test_triple_axel_stops_at_the_first_hit_that_misses():
    user, foe, arena = duel(user_types=("fire",))
    action = _strike(user, foe, TRIPLE_AXEL, arena, draws(LANDS, NO_CRIT, LANDS, NO_CRIT, MISSES))
    assert action.hits == 2 and not action.missed


def test_triple_kick_lands_all_three_hits_when_every_draw_lands():
    user, foe, arena = duel(user_types=("fire",))
    action = _strike(user, foe, TRIPLE_KICK, arena, draws(LANDS, NO_CRIT, LANDS, NO_CRIT, LANDS))
    assert action.hits == 3


def test_population_bomb_hits_ten_times_while_each_hit_lands():
    user, foe, arena = duel(user_types=("fire",))
    assert (POPULATION_BOMB.min_hits, POPULATION_BOMB.max_hits) == (10, 10)
    assert _strike(user, foe, POPULATION_BOMB, arena, draws(*[LANDS, NO_CRIT] * 10)).hits == 10
    user, foe, arena = duel(user_types=("fire",))
    assert _strike(user, foe, POPULATION_BOMB, arena, draws(LANDS, NO_CRIT, LANDS, NO_CRIT, MISSES)).hits == 2


def test_a_sure_hit_draws_for_no_hit():
    user, foe, arena = duel(user_types=("fire",))
    resolve(user, foe, LOCK_ON, arena)
    assert _strike(user, foe, TRIPLE_AXEL, arena, draws()).hits == 3


def test_the_ai_counts_a_hit_only_while_every_earlier_one_landed():
    user, _, _ = duel()
    assert battle._expected_hits(TRIPLE_AXEL, user, 90) == pytest.approx(1 + 0.9 + 0.81)
    assert battle._expected_hits(TRIPLE_AXEL, user, 100) == 3


def _strike(user, foe, move, arena, rng):
    user.hp, foe.hp = user.max_hp, foe.max_hp
    user.combatant = replace(user.combatant, moves=(move,))
    user.pp = [move.pp]
    fighters = (user, foe) if user.side == 0 else (foe, user)
    return battle._resolve(1, user.side, fighters, 0, arena.weather, rng, arena)
