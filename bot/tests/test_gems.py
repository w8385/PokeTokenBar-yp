from dataclasses import replace

import pytest
from test_ability_items import holding
from test_battle import TACKLE
from status_moves import data_move, resolve

from ypoke import battle, items
from ypoke.battle import ItemEffect
from ypoke.narration import battle_log

GROWL = data_move(45)


def struck(gem, move, foe_types=("normal",)):
    user, foe, arena = holding(item=gem)
    foe.combatant = replace(foe.combatant, types=foe_types)
    resolve(user, foe, move, arena)
    return foe.max_hp - foe.hp, user, arena


@pytest.mark.parametrize("gem", sorted(items.GEMS))
def test_every_gem_is_spent_on_a_damaging_move_of_its_type_only(gem):
    kind = items.GEMS[gem]
    _, user, arena = struck(gem, battle.Move("기술", kind, 40, physical=True, accuracy=100), foe_types=("fairy",)
                            if kind in ("normal", "fighting", "ground", "ghost", "electric") else ("normal",))
    assert user.item is None and user.primed is None
    assert ItemEffect(1, 0, user.combatant.name, gem, "spent") in arena.log
    other = "dragon" if kind != "dragon" else "fire"
    _, kept, _ = struck(gem, battle.Move("기술", other, 40, physical=True, accuracy=100))
    assert kept.item == gem


def test_a_gem_raises_the_power_of_that_one_move():
    plain, _, _ = struck(None, TACKLE)
    gemmed, _, _ = struck("normal-gem", TACKLE)
    assert gemmed > plain
    assert gemmed == pytest.approx(plain * items.GEM_MULTIPLIER, abs=2)


def test_a_gem_stays_on_a_status_move_and_on_an_immune_target():
    _, user, _ = struck("normal-gem", GROWL)
    assert user.item == "normal-gem"
    _, user, _ = struck("normal-gem", TACKLE, foe_types=("ghost",))
    assert user.item == "normal-gem"


def test_the_log_says_the_gem_was_used():
    event = ItemEffect(1, 0, "사용자", "fire-gem", "spent")
    log = "".join(battle_log(battle.BattleResult(0, 1, (event,), ((50,), (50,)))))
    assert "사용자 @불꽃주얼 써서 위력↑" in log
