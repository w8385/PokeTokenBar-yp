import random
from dataclasses import replace

from attacks import attack, duel, first_seed, hit
from status_moves import data_move, resolve

from ypoke import battle, narration

HIGH_JUMP_KICK, AXE_KICK, STEEL_BEAM, MIND_BLOWN, CHLOROBLAST = (attack(136), attack(853), attack(796), attack(720),
                                                                attack(835))
PROTECT = data_move(182)


def misses(accuracy):
    return first_seed(lambda seed: random.Random(seed).random() * 100 >= accuracy)


def hits(accuracy):
    return first_seed(lambda seed: random.Random(seed).random() * 100 < accuracy)


def test_high_jump_kick_crashes_for_half_the_users_max_hp_on_a_miss():
    user, foe, arena = duel()
    action = hit(user, foe, HIGH_JUMP_KICK, arena, seed=misses(90))
    assert action.missed and user.hp == user.max_hp - user.max_hp // 2
    assert [change.kind for change in action.changes] == ["crash"]
    assert "빗나감 자신 💥크래시 데미지" in narration._action_line(action, "🔵")


def test_high_jump_kick_crashes_on_an_immune_target_and_into_protect():
    user, foe, arena = duel(foe_types=("ghost",))
    action = hit(user, foe, HIGH_JUMP_KICK, arena, seed=hits(90))
    assert action.multiplier == 0 and user.hp == user.max_hp - user.max_hp // 2
    user, foe, arena = duel()
    resolve(foe, user, PROTECT, arena)
    action = resolve(user, foe, HIGH_JUMP_KICK, arena)
    assert action.blocked == "protect" and user.hp == user.max_hp - user.max_hp // 2


def test_a_crash_move_that_hits_costs_nothing_and_a_crash_can_knock_its_user_out():
    user, foe, arena = duel()
    hit(user, foe, HIGH_JUMP_KICK, arena, seed=hits(90))
    assert user.hp == user.max_hp
    user.hp = user.max_hp // 2
    assert resolve(user, foe, HIGH_JUMP_KICK, arena, seed=misses(90)).attacker_fainted


def test_axe_kick_crashes_and_may_confuse():
    user, foe, arena = duel()
    hit(user, foe, AXE_KICK, arena, seed=misses(90))
    assert user.hp < user.max_hp and (AXE_KICK.ailment, AXE_KICK.ailment_chance) == ("confusion", 30)


def test_steel_beam_and_mind_blown_cost_half_the_max_hp_rounded_up_hit_or_miss():
    for move, accuracy in ((STEEL_BEAM, 95), (MIND_BLOWN, 100)):
        for seed in (hits(accuracy), misses(accuracy)) if accuracy < 100 else (0,):
            user, foe, arena = duel(user_types=("steel",))
            action = _act(user, foe, move, arena, seed)
            assert user.hp == user.max_hp - -(-user.max_hp // 2)
            assert action.changes[-1].kind == "hp-cost"


def test_an_hp_cost_move_can_knock_its_user_out():
    user, foe, arena = duel()
    user.hp = user.max_hp // 2
    assert _act(user, foe, MIND_BLOWN, arena, 0).attacker_fainted


def test_chloroblast_costs_half_the_max_hp_only_when_it_hits():
    user, foe, arena = duel()
    _act(user, foe, CHLOROBLAST, arena, misses(95))
    assert user.hp == user.max_hp
    _act(user, foe, CHLOROBLAST, arena, hits(95))
    assert user.hp == user.max_hp - -(-user.max_hp // 2)


def test_an_ordinary_miss_reads_as_before():
    user, foe, arena = duel()
    action = resolve(user, foe, attack(126), arena, seed=misses(85))
    assert narration._action_line(action, "🔵").endswith("→ 빗나감")


def _act(user, foe, move, arena, seed):
    user.combatant = replace(user.combatant, moves=(move,))
    user.pp = [move.pp]
    return battle._act(1, 0, (user, foe), 0, arena.weather, random.Random(seed), arena)
