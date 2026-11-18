from status_moves import choose, data_move, pair, put, resolve
from test_battle import TACKLE, mon

from ypoke.battle import Change, Move, _Arena

SPORE, SLEEP_POWDER, SING, CONFUSE_RAY = data_move(147), data_move(79), data_move(47), data_move(109)
TOXIC, WILL_O_WISP, GLARE, STUN_SPORE = data_move(92), data_move(261), data_move(137), data_move(78)
SWAGGER, FLATTER, TOXIC_THREAD, PSYCHO_SHIFT = data_move(207), data_move(260), data_move(672), data_move(375)
SUBSTITUTE = data_move(164)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)


def fighters(user_types=("normal",), foe_types=("normal",), arena=None):
    arena = arena or _Arena()
    return put(mon("사용자", user_types), arena), put(mon("상대", foe_types), arena, 1), arena


def test_an_ailment_move_gives_its_status_once_and_fails_on_a_foe_that_has_one():
    user, foe, arena = fighters()
    used = resolve(user, foe, SPORE, arena)
    assert used.effect == "inflict" and used.changes == (Change(1, "상대", "sleep"),) and foe.status == "sleep"
    assert resolve(user, foe, WILL_O_WISP, arena, seed=1).failed and foe.status == "sleep"
    assert resolve(user, foe, CONFUSE_RAY, arena).changes == (Change(1, "상대", "confusion"),) and foe.confusion_left
    assert resolve(user, foe, CONFUSE_RAY, arena).failed


def test_types_powders_and_the_foes_substitute_stop_an_ailment_move():
    user, foe, arena = fighters(foe_types=("fire",))
    assert resolve(user, foe, WILL_O_WISP, arena, seed=1).failed and foe.status is None
    user, foe, arena = fighters(foe_types=("grass",))
    assert resolve(user, foe, SLEEP_POWDER, arena, seed=1).failed and foe.status is None
    assert resolve(user, foe, GLARE, arena).effect == "inflict" and foe.status == "paralysis"
    user, foe, arena = fighters()
    resolve(foe, user, SUBSTITUTE, arena)
    assert resolve(user, foe, SPORE, arena).blocked == "substitute" and foe.status is None
    assert not resolve(user, foe, SING, arena, seed=1).failed and foe.status == "sleep"


def test_toxic_never_misses_from_a_poison_type():
    missed = 0
    for seed in range(200):
        user, foe, arena = fighters()
        missed += resolve(user, foe, TOXIC, arena, seed=seed).missed
        user, foe, arena = fighters(user_types=("poison",))
        assert resolve(user, foe, TOXIC, arena, seed=seed).effect == "inflict" and foe.status == "toxic"
    assert 5 < missed < 40


def test_swagger_raises_the_foe_even_when_it_is_confused_already_and_fails_only_when_nothing_lands():
    user, foe, arena = fighters()
    used = resolve(user, foe, SWAGGER, arena)
    assert used.changes == (Change(1, "상대", "confusion"), Change(1, "상대", "attack", 2))
    assert resolve(user, foe, SWAGGER, arena).changes == (Change(1, "상대", "attack", 2),)
    foe.stages["attack"] = 6
    assert resolve(user, foe, SWAGGER, arena).failed
    assert resolve(user, foe, FLATTER, arena).changes == (Change(1, "상대", "special_attack", 1),)


def test_toxic_thread_slows_a_foe_it_cannot_poison():
    user, foe, arena = fighters()
    assert resolve(user, foe, TOXIC_THREAD, arena).changes == (Change(1, "상대", "poison"), Change(1, "상대", "speed", -1))
    user, foe, arena = fighters(foe_types=("steel",))
    assert resolve(user, foe, TOXIC_THREAD, arena).changes == (Change(1, "상대", "speed", -1),)
    foe.stages["speed"] = -6
    assert resolve(user, foe, TOXIC_THREAD, arena).failed


def test_psycho_shift_moves_the_users_status_to_the_foe():
    user, foe, arena = fighters()
    assert resolve(user, foe, PSYCHO_SHIFT, arena).failed
    user.status = "burn"
    used = resolve(user, foe, PSYCHO_SHIFT, arena)
    assert used.changes == (Change(1, "상대", "burn"), Change(0, "사용자", "cure"))
    assert user.status is None and foe.status == "burn"
    user.status = "paralysis"
    assert resolve(user, foe, PSYCHO_SHIFT, arena).failed and user.status == "paralysis"


def test_the_chooser_puts_to_sleep_any_foe_but_paralyzes_only_a_faster_one_and_burns_only_a_physical_one():
    teams, arena = pair((SPORE, TACKLE))
    assert choose(teams, arena) == 0
    teams[1].active.status = "sleep"
    assert choose(teams, arena) == 1
    teams, arena = pair((STUN_SPORE, TACKLE), speed=200)
    assert choose(teams, arena) == 1
    teams, arena = pair((STUN_SPORE, TACKLE), speed=1)
    assert choose(teams, arena) == 0
    teams, arena = pair((WILL_O_WISP, TACKLE), foe_moves=(EMBER,))
    assert choose(teams, arena) == 1
    teams, arena = pair((WILL_O_WISP, TACKLE))
    assert choose(teams, arena) == 0


def test_the_chooser_swaggers_only_a_foe_that_cannot_use_the_raise_and_shifts_only_a_status_it_has():
    teams, arena = pair((SWAGGER, TACKLE), foe_moves=(EMBER,))
    assert choose(teams, arena) == 0
    teams, arena = pair((SWAGGER, TACKLE))
    assert choose(teams, arena) == 1
    teams, arena = pair((PSYCHO_SHIFT, TACKLE))
    assert choose(teams, arena) == 1
    teams[0].active.status = "poison"
    assert choose(teams, arena) == 0
    teams, arena = pair((SLEEP_POWDER, TACKLE), foe_types=("grass",))
    assert choose(teams, arena) == 1
