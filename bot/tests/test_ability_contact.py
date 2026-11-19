from dataclasses import replace

import pytest
from attacks import attack
from test_ability_damage import facing
from test_held_items_more import FixedRng

from ypoke import battle, items

TACKLE, EARTHQUAKE, SURF, POWER_UP_PUNCH = attack(33), attack(89), attack(57), attack(612)
WEAK = {"attack": 10, "special_attack": 10}
TRIGGERS, MISSES = 0.25, 0.5


def struck(move, foe_ability=None, user_ability=None, draw=TRIGGERS, foe_item=None, substitute=False, **kwargs):
    """The user's `move` on the foe with every chance draw at `draw`; the action, the user and the foe."""
    user, foe, arena = facing(user_ability, foe_ability, **{**WEAK, **kwargs})
    foe.item = foe_item
    if substitute:
        foe.volatiles["substitute"] = foe.max_hp
    user.combatant = replace(user.combatant, moves=(move,))
    user.pp = [move.pp]
    action = battle._resolve(1, 0, (user, foe), 0, arena.weather, FixedRng(draw), arena)
    return action, user, foe


@pytest.mark.parametrize(("move", "afflicted"), [(TACKLE, True), (EARTHQUAKE, False), (SURF, False)])
def test_static_answers_only_a_contact_move(move, afflicted):
    _, user, _ = struck(move, "static")
    assert (user.status == "paralysis") == afflicted


@pytest.mark.parametrize(("move", "hurt"), [(TACKLE, True), (EARTHQUAKE, False)])
def test_rocky_helmet_answers_only_a_contact_move(move, hurt):
    _, user, _ = struck(move, foe_item=items.ROCKY_HELMET)
    assert (user.hp < user.max_hp) == hurt


@pytest.mark.parametrize(("substitute", "afflicted"), [(True, False), (False, True)])
def test_static_does_not_answer_a_hit_its_substitute_took(substitute, afflicted):
    _, user, _ = struck(POWER_UP_PUNCH, "static", substitute=substitute)
    assert (user.status == "paralysis") == afflicted
