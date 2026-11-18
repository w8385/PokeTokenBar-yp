"""Helpers for the status-move family tests: a move built from its `data/battle/moves.json` entry, a fighter on a
side of an arena, and one move resolved or chosen."""

import random
from dataclasses import replace

from test_battle import TACKLE, mon

from ypoke import battle, battle_data
from ypoke.battle import Move, _Arena, _Fighter, _Team, _Weather
from ypoke.move_effects import EFFECTS


def data_move(move_id: int) -> Move:
    entry = battle_data.table("moves")[str(move_id)]
    return Move(entry["names"]["ko"], entry["type"], entry["power"] or 0, physical=entry["class"] == "physical",
                accuracy=entry["accuracy"], pp=entry["pp"], priority=entry["priority"], effect=EFFECTS.get(move_id),
                id=move_id)


def put(combatant, arena, side=0, item=None, ability=None):
    fighter = _Fighter.enter(replace(combatant, ability=ability) if ability else combatant)
    fighter.item = item
    fighter.arena, fighter.side = arena, side
    return fighter


def resolve(user, target, move, arena, weather=None, seed=0, turn=1):
    user.combatant = replace(user.combatant, moves=(move, *user.combatant.moves[1:]))
    user.pp = [move.pp, *user.pp[1:]]
    fighters = (user, target) if user.side == 0 else (target, user)
    return battle._resolve(turn, user.side, fighters, 0, weather or arena.weather, random.Random(seed), arena)


def pair(user_moves, foe_moves=(TACKLE,), arena=None, user_types=("normal",), foe_types=("normal",), **stats):
    """Two one-member teams facing each other in `arena`."""
    arena = arena or _Arena()
    teams = (_Team((mon("사용자", user_types, moves=tuple(user_moves), **stats),), arena=arena),
             _Team((mon("상대", foe_types, moves=tuple(foe_moves)),), arena=arena, side=1))
    arena.teams = teams
    return teams, arena


def choose(teams, arena, side=0, weather=None):
    return battle._choose(teams, side, arena, weather)


def weather(kind):
    return _Weather(kind, 5)
