import random

import pytest
from test_ability_items import holding
from test_battle import TACKLE
from test_effect_moves import SWORDS_DANCE
from status_moves import data_move, resolve

from ypoke import battle, items
from ypoke.battle import ItemEffect
from ypoke.effects import hooks
from ypoke.narration import battle_log

EARTHQUAKE, GROWL, SOLAR_BEAM, HYPER_VOICE = data_move(89), data_move(45), data_move(76), data_move(304)
WILD_SHOT = battle.Move("빗나감", "normal", 40, physical=True, accuracy=1)


def test_an_air_balloon_floats_over_ground_moves_until_a_hit_pops_it():
    user, holder, arena = holding(foe_item="air-balloon")
    action = resolve(user, holder, EARTHQUAKE, arena)
    assert action.multiplier == 0 and holder.item == "air-balloon" and not battle._grounded(holder)
    resolve(user, holder, GROWL, arena)
    holder.volatiles["substitute"] = holder.max_hp
    resolve(user, holder, TACKLE, arena)
    assert holder.item == "air-balloon"
    del holder.volatiles["substitute"]
    resolve(user, holder, TACKLE, arena)
    assert holder.item is None and battle._grounded(holder)
    assert ItemEffect(1, 1, holder.combatant.name, "air-balloon", "popped") in arena.log


@pytest.mark.parametrize(("item", "kind", "stat"), [(slug, *entry) for slug, entry in
                                                     sorted(items.HIT_STAT_ITEMS.items())])
def test_a_hit_of_its_type_spends_the_item_on_a_stat_and_another_type_does_not(item, kind, stat):
    user, holder, arena = holding(foe_item=item)
    resolve(user, holder, TACKLE, arena)
    assert holder.item == item and holder.stages[stat] == 0
    resolve(user, holder, battle.Move("기술", kind, 20, physical=True, accuracy=100), arena)
    assert holder.item is None and holder.stages[stat] == 1


def test_blunder_policy_sharply_raises_speed_after_a_miss_only():
    holder, foe, arena = holding(item="blunder-policy")
    resolve(holder, foe, TACKLE, arena)
    assert holder.item == "blunder-policy"
    action = resolve(holder, foe, WILD_SHOT, arena)
    assert action.missed and holder.item is None and holder.stages["speed"] == items.BLUNDER_POLICY_STAGES


def test_throat_spray_raises_special_attack_after_a_sound_move_only():
    holder, foe, arena = holding(item="throat-spray")
    act(holder, foe, TACKLE, arena)
    assert holder.item == "throat-spray"
    act(holder, foe, HYPER_VOICE, arena)
    assert holder.item is None and holder.stages["special_attack"] == 1


def test_adrenaline_orb_raises_speed_when_intimidated():
    user, holder, arena = holding(ability="intimidate", foe_item="adrenaline-orb")
    hooks.ability(user, "on_entry", user, holder, 0, arena.weather)
    assert holder.item is None and holder.stages["speed"] == 1
    _, plain, _ = holding(foe_item="adrenaline-orb")
    assert update(plain) is None and plain.item == "adrenaline-orb"


def test_room_service_lowers_speed_under_trick_room_only():
    holder, _, arena = holding(item="room-service")
    assert update(holder) is None and holder.item == "room-service"
    arena.trick_room = 5
    update(holder)
    assert holder.item is None and holder.stages["speed"] == -1


def test_mirror_herb_copies_the_foes_raises_once_its_action_is_over():
    holder, foe, arena = holding(item="mirror-herb")
    assert update(holder) is None and holder.item == "mirror-herb"
    resolve(foe, holder, SWORDS_DANCE, arena)
    assert holder.stages["attack"] == 0
    event = update(holder)
    assert holder.item is None and holder.stages["attack"] == 2
    assert event.changes == (battle.Change(0, holder.combatant.name, "attack", 2),)


@pytest.mark.parametrize("state", ["taunt", "encore", "torment", "disable", "heal-block"])
def test_mental_herb_ends_a_move_limiting_state(state):
    holder, _, _ = holding(item="mental-herb")
    assert update(holder) is None and holder.item == "mental-herb"
    holder.volatiles[state] = 3
    update(holder)
    assert state not in holder.volatiles and holder.item is None


def test_power_herb_lets_a_charge_move_hit_at_once_and_the_chooser_counts_the_whole_hit():
    holder, foe, arena = holding(item="power-herb")
    assert hooks.move(SOLAR_BEAM, "score_share", None, holder) == 1.0
    action = resolve(holder, foe, SOLAR_BEAM, arena)
    assert not action.effect and foe.hp < foe.max_hp and holder.item is None
    assert ItemEffect(1, 0, holder.combatant.name, "power-herb", "charged") in arena.log
    plain, foe, arena = holding()
    assert hooks.move(SOLAR_BEAM, "score_share", None, plain) < 1.0
    assert resolve(plain, foe, SOLAR_BEAM, arena).effect == "charge-turn" and foe.hp == foe.max_hp


def test_the_log_names_the_item_that_acted():
    events = (ItemEffect(1, 0, "사용자", "air-balloon", "popped"), ItemEffect(1, 0, "사용자", "power-herb", "charged"),
              ItemEffect(1, 0, "사용자", "throat-spray", "used", (battle.Change(0, "사용자", "special_attack", 1),)))
    log = "".join(battle_log(battle.BattleResult(0, 1, events, ((50,), (50,)))))
    assert "사용자 @풍선 터짐" in log and "사용자 @파워풀허브 써서 바로 공격" in log and "@목스프레이 발동" in log


def update(holder):
    return hooks.item(holder, "on_update", holder, holder.side, 1)


def act(user, target, move, arena, seed=0):
    user.combatant = battle.replace(user.combatant, moves=(move, *user.combatant.moves[1:]))
    user.pp = [move.pp, *user.pp[1:]]
    fighters = (user, target) if user.side == 0 else (target, user)
    return battle._act(1, user.side, fighters, 0, arena.weather, random.Random(seed), arena)
