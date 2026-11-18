"""Helpers for the attacking-move family tests: a move as the bot builds it from `data/battle/moves.json`, two
fighters facing each other in an arena, and the seeds where a chance lands or not."""

import random

from status_moves import put, resolve
from test_battle import mon

from ypoke import moves, pokeapi
from ypoke.battle import _Arena


def attack(move_id: int):
    return moves._move(pokeapi.data_move(move_id))


def duel(user_types=("normal",), foe_types=("normal",), **stats):
    arena = _Arena()
    user = put(mon("사용자", user_types, **stats), arena)
    foe = put(mon("상대", foe_types), arena, 1)
    return user, foe, arena


def first_seed(check, seeds=range(200)):
    """The first seed for which `check(seed)` holds."""
    return next(seed for seed in seeds if check(seed))


def hit(user, foe, move, arena, seed=0, turn=1):
    user.hp, foe.hp = user.max_hp, foe.max_hp
    return resolve(user, foe, move, arena, seed=seed, turn=turn)


def draws(*values):
    """An rng whose `random()` returns `values` in order, then 0.99."""
    rng = random.Random(0)
    queue = list(values)
    rng.random = lambda: queue.pop(0) if queue else 0.99
    return rng
