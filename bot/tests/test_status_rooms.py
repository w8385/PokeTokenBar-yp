from status_moves import choose, data_move, pair, put, resolve
from test_battle import TACKLE, mon

from ypoke import battle, items
from ypoke.battle import FieldEnd, Move, _Arena
from ypoke.effects import hooks

MAGIC_ROOM, WONDER_ROOM = data_move(478), data_move(472)
SWIFT = Move("스피드스타", "normal", 60, physical=False)


def fighters(user_item=None, foe_item=None, **user_stats):
    arena = _Arena()
    user = put(mon("사용자", ("normal",), **user_stats), arena, item=user_item)
    foe = put(mon("상대", ("normal",)), arena, 1, item=foe_item)
    return user, foe, arena


def test_magic_room_idles_every_held_item_for_five_turns_and_a_second_use_ends_it():
    user, foe, arena = fighters("choice-scarf", items.LEFTOVERS)
    speed = user.stat("speed")
    assert resolve(user, foe, MAGIC_ROOM, arena).effect == "magic-room"
    assert user.stat("speed") * 1.5 == speed
    assert hooks.item(foe, "end_of_turn", foe, 1, 1, None) is None
    events = []
    for turn in range(1, 6):
        battle._room_upkeep(turn, arena, events)
    assert events == [FieldEnd(5, "magic-room")] and user.stat("speed") == speed
    resolve(user, foe, MAGIC_ROOM, arena)
    assert resolve(user, foe, MAGIC_ROOM, arena).effect == "magic-room-off" and "magic-room" not in arena.rooms


def test_wonder_room_trades_raw_defense_and_special_defense_but_not_their_stages():
    user, foe, arena = fighters(defense=50, special_defense=120)
    user.stages["defense"] = 2
    resolve(user, foe, WONDER_ROOM, arena)
    assert user.stat("defense") == user.stats["special_defense"] * 2
    assert user.stat("special_defense") == user.stats["defense"]


def test_the_chooser_sets_magic_room_against_a_helpful_item_and_never_ends_its_own_room():
    teams, arena = pair((MAGIC_ROOM, TACKLE))
    user, foe = teams[0].active, teams[1].active
    foe.item = items.LEFTOVERS
    assert choose(teams, arena) == 0
    arena.rooms["magic-room"] = 3
    assert choose(teams, arena) == 1
    del arena.rooms["magic-room"]
    user.item = items.LEFTOVERS
    assert choose(teams, arena) == 1


def test_the_chooser_sets_wonder_room_when_the_swap_guards_it_against_the_foes_kind_of_attack():
    teams, arena = pair((WONDER_ROOM, TACKLE), defense=50, special_defense=120)
    assert choose(teams, arena) == 0
    teams, arena = pair((WONDER_ROOM, TACKLE), (SWIFT,), defense=50, special_defense=120)
    assert choose(teams, arena) == 1
