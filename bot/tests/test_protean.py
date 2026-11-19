import random
from dataclasses import replace

from status_moves import data_move, put
from test_battle import mon

from ypoke import battle
from ypoke.battle import AbilityRetype, Action, _Arena, _Weather, simulate
from ypoke.narration import battle_log

PLAY_ROUGH, FLOWER_TRICK, SPACIAL_REND, FUTURE_SIGHT = (data_move(move_id) for move_id in (583, 870, 460, 248))
MEOWSCARADA = replace(mon("마스카나", ("grass", "dark"), hp=76, attack=110, defense=70, special_attack=81,
                          special_defense=70, speed=123, moves=(PLAY_ROUGH, FLOWER_TRICK)),
                      ability="protean", pokemon_id=908)
PALKIA = replace(mon("펄기아", ("water", "dragon"), hp=90, attack=120, defense=100, special_attack=150,
                     special_defense=120, speed=100, moves=(SPACIAL_REND,)), pokemon_id=484)
MISSED_SEED = 2
HITTING_SEED = 1


def test_protean_missed_play_rough_still_makes_the_user_fairy_and_immune_to_dragon():
    result = simulate(((replace(MEOWSCARADA, moves=(PLAY_ROUGH,)),), (PALKIA,)), seed=MISSED_SEED)
    first, retype, answer = result.events[0:3]
    assert isinstance(first, Action) and first.side == 0 and first.missed
    assert retype == AbilityRetype(0, "마스카나", "protean", into="fairy")
    assert isinstance(answer, Action) and answer.move == SPACIAL_REND.name and answer.multiplier == 0
    assert any("마스카나 [변환자재] 페어리 타입이 되었다" in block for block in battle_log(result))


def test_protean_names_a_type_without_a_korean_name_by_its_key():
    shadow_rush = battle.Move("섀도러시", "shadow", 55, physical=True, accuracy=100)
    result = simulate(((replace(MEOWSCARADA, moves=(shadow_rush,)),), (PALKIA,)), seed=HITTING_SEED)
    assert any("마스카나 [변환자재] shadow 타입이 되었다" in block for block in battle_log(result))


def test_protean_gives_stab_on_the_new_type():
    plain, _ = struck(replace(MEOWSCARADA, ability="overgrow"), PLAY_ROUGH)
    retyped, user = struck(MEOWSCARADA, PLAY_ROUGH)
    assert user.combatant.types == ("fairy",) and battle._stab(user, PLAY_ROUGH) == battle.STAB_MULTIPLIER
    assert retyped > plain * 1.4


def test_protean_acts_once_per_entry_and_again_after_switching_back_in():
    arena = _Arena()
    user, foe = put(MEOWSCARADA, arena), put(PALKIA, arena, 1)
    strike(user, foe, PLAY_ROUGH, arena)
    strike(user, foe, FLOWER_TRICK, arena)
    assert user.combatant.types == ("fairy",) and len(arena.log) == 1
    user.leave()
    assert user.combatant.types == ("grass", "dark")
    strike(user, foe, FLOWER_TRICK, arena)
    assert user.combatant.types == ("grass",) and arena.log[-1].into == "grass"


def test_protean_skips_a_move_of_its_only_type_and_waits_for_the_next():
    arena = _Arena()
    user, foe = put(replace(MEOWSCARADA, types=("fairy",)), arena), put(PALKIA, arena, 1)
    strike(user, foe, PLAY_ROUGH, arena)
    assert not arena.log
    strike(user, foe, FLOWER_TRICK, arena)
    assert user.combatant.types == ("grass",)


def test_protean_does_nothing_while_terastallized_or_for_future_sight_or_struggle():
    for combatant, move in ((replace(MEOWSCARADA, tera=True), PLAY_ROUGH), (MEOWSCARADA, FUTURE_SIGHT),
                            (MEOWSCARADA, battle.STRUGGLE)):
        arena = _Arena()
        user, foe = put(combatant, arena), put(PALKIA, arena, 1)
        strike(user, foe, move, arena)
        assert user.combatant.types == ("grass", "dark") and not arena.log


def test_protean_waits_while_its_user_sleeps():
    arena = _Arena()
    user, foe = put(MEOWSCARADA, arena), put(PALKIA, arena, 1)
    user.status, user.sleep_left = "sleep", 3
    action = battle._act(1, 0, (user, foe), 0, _Weather(None, 0), random.Random(0), arena)
    assert action.blocked == "sleep" and user.combatant.types == ("grass", "dark") and not arena.log


def struck(combatant, move):
    """The damage `move` from `combatant` deals Palkia, and its user afterwards."""
    arena = _Arena()
    user, foe = put(combatant, arena), put(PALKIA, arena, 1)
    strike(user, foe, move, arena)
    return foe.max_hp - foe.hp, user


def strike(user, foe, move, arena):
    return battle._strike(1, user.side, user, foe, move, (), _Weather(None, 0), random.Random(HITTING_SEED), arena)
