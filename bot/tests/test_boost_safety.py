import pytest
from attacks import attack
from status_moves import choose, data_move, pair

from ypoke.effects import hooks

CLOSE_COMBAT = attack(370)
SWORDS_DANCE, DRAGON_DANCE = data_move(14), data_move(349)
FRAIL = {"hp": 10, "defense": 10, "special_defense": 10}
BULKY = {"hp": 255, "defense": 255, "special_defense": 255}


@pytest.mark.parametrize("boost", [SWORDS_DANCE, DRAGON_DANCE])
@pytest.mark.parametrize(("stats", "item", "wanted"),
                         [(BULKY, None, True), (FRAIL, None, False), (FRAIL, "focus-sash", True)])
def test_a_boost_is_picked_only_when_the_foe_cannot_surely_knock_the_user_out_first(boost, stats, item, wanted):
    teams, arena = pair((boost, CLOSE_COMBAT), foe_moves=(CLOSE_COMBAT,), **stats)
    teams[0].active.item = item
    assert hooks.move(boost, "wanted", teams[0], teams[1], 0, arena, None, default=False) is wanted
    assert choose(teams, arena) == (0 if wanted else 1)


def test_a_sash_that_is_spent_below_full_hp_no_longer_makes_a_boost_safe():
    teams, arena = pair((SWORDS_DANCE, CLOSE_COMBAT), foe_moves=(CLOSE_COMBAT,), **FRAIL)
    user = teams[0].active
    user.item, user.hp = "focus-sash", user.max_hp - 1
    assert choose(teams, arena) == 1
