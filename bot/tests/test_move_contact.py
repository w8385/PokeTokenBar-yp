import pytest
from attacks import attack
from status_moves import put
from test_battle import mon
from test_held_items_more import FixedRng

from ypoke import battle, items
from ypoke.battle import _Arena

FLOWER_TRICK, CLOSE_COMBAT, GRASS_KNOT, EARTHQUAKE = attack(870), attack(370), attack(447), attack(89)
BODY_PRESS, POWER_UP_PUNCH, TACKLE = attack(776), attack(612), attack(33)
CHANCES_LAND = 0.0


def struck(move, foe_ability=None, foe_item=None, user_ability=None, user_item=None, substitute=False):
    """The user's `move` on a sturdy foe with every chance draw landing; the action, the user and the foe."""
    arena = _Arena()
    user = put(mon("사용자", ("normal",), moves=(move,), attack=10, special_attack=10), arena,
               item=user_item, ability=user_ability)
    foe = put(mon("상대", ("normal",), hp=255, defense=255, special_defense=255), arena, 1,
              item=foe_item, ability=foe_ability)
    if substitute:
        foe.volatiles["substitute"] = foe.max_hp
    action = battle._resolve(1, 0, (user, foe), 0, arena.weather, FixedRng(CHANCES_LAND), arena)
    return action, user, foe


@pytest.mark.parametrize(("move", "hurt"), [(FLOWER_TRICK, False), (CLOSE_COMBAT, True), (GRASS_KNOT, True),
                                            (EARTHQUAKE, False)])
def test_rocky_helmet_answers_only_a_contact_move(move, hurt):
    action, user, _ = struck(move, foe_item=items.ROCKY_HELMET)
    assert (user.hp < user.max_hp) == hurt
    assert (action.defender_item == items.ROCKY_HELMET) == hurt


@pytest.mark.parametrize(("move", "afflicted"), [(GRASS_KNOT, True), (CLOSE_COMBAT, True), (EARTHQUAKE, False),
                                                 (FLOWER_TRICK, False)])
def test_static_answers_only_a_contact_move(move, afflicted):
    _, user, _ = struck(move, foe_ability="static")
    assert (user.status == "paralysis") == afflicted


@pytest.mark.parametrize(("move", "user_ability", "user_item", "hurt"), [
    (CLOSE_COMBAT, "long-reach", None, False),
    (POWER_UP_PUNCH, None, items.PUNCHING_GLOVE, False),
    (TACKLE, None, items.PUNCHING_GLOVE, True),
    (CLOSE_COMBAT, None, items.PROTECTIVE_PADS, False),
])
def test_long_reach_punching_glove_and_protective_pads_keep_the_user_off_contact(move, user_ability, user_item, hurt):
    _, user, _ = struck(move, foe_item=items.ROCKY_HELMET, user_ability=user_ability, user_item=user_item)
    assert (user.hp < user.max_hp) == hurt


@pytest.mark.parametrize(("substitute", "afflicted"), [(True, False), (False, True)])
def test_static_does_not_answer_a_hit_its_substitute_took(substitute, afflicted):
    _, user, _ = struck(POWER_UP_PUNCH, "static", substitute=substitute)
    assert (user.status == "paralysis") == afflicted


def test_a_focus_sash_holder_hitting_a_rocky_helmet_without_contact_keeps_its_sash():
    arena = _Arena()
    sash = put(mon("마스카나", ("grass", "dark"), moves=(FLOWER_TRICK,), hp=10, defense=10), arena,
               item=items.FOCUS_SASH)
    helmet = put(mon("딩루", ("dark", "ground"), moves=(BODY_PRESS,), hp=255, defense=255), arena, 1,
                 item=items.ROCKY_HELMET)
    battle._resolve(1, 0, (sash, helmet), 0, arena.weather, FixedRng(0.5), arena)
    assert sash.hp == sash.max_hp
    pressed = battle._resolve(1, 1, (sash, helmet), 0, arena.weather, FixedRng(0.5), arena)
    assert (pressed.defender_item, pressed.knockout, sash.hp) == (items.FOCUS_SASH, False, 1)
