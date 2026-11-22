import random
from dataclasses import replace

from attacks import attack, duel, first_seed, hit
from status_moves import data_move, resolve

from ypoke import battle, narration

HIGH_JUMP_KICK, AXE_KICK, STEEL_BEAM, MIND_BLOWN, CHLOROBLAST = (attack(136), attack(853), attack(796), attack(720),
                                                                attack(835))
PROTECT = data_move(182)
BRAVE_BIRD, FLARE_BLITZ, MATCHA_GOTCHA = attack(413), attack(394), attack(902)


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


def test_the_chooser_weighs_an_hp_cost_against_the_hp_the_user_has_left():
    user, foe, arena = duel()
    free = replace(STEEL_BEAM, id=0)
    full = battle._move_score(user, foe, STEEL_BEAM, None)
    assert full == battle._move_score(user, foe, free, None) * (1 - -(-user.max_hp // 2) / user.hp)
    user.hp = user.max_hp // 2
    assert battle._move_score(user, foe, STEEL_BEAM, None) == 0.0 < battle._move_score(user, foe, free, None)


def test_the_chooser_weighs_recoil_and_a_likely_crash():
    user, foe, arena = duel()
    for move in (BRAVE_BIRD, HIGH_JUMP_KICK):
        free = replace(move, id=0, drain=0)
        assert 0.0 < battle._move_score(user, foe, move, None) < battle._move_score(user, foe, free, None), move.name
    user.hp = 1
    assert battle._move_score(user, foe, BRAVE_BIRD, None) == 0.0


def test_sheer_force_drops_flare_blitzs_burn_but_keeps_its_recoil():
    user, foe, arena = duel()
    burns = first_seed(lambda seed: hit(user, foe, FLARE_BLITZ, arena, seed=seed) and foe.status == "burn")
    forced, foe, arena = duel()
    forced.combatant = replace(forced.combatant, ability="sheer-force")
    hit(forced, foe, FLARE_BLITZ, arena, seed=burns)
    assert foe.status is None and 0 < forced.hp < forced.max_hp


def test_sheer_force_drops_matcha_gotchas_burn_but_keeps_its_drain():
    user, foe, arena = duel()
    user.hp = user.max_hp // 2
    burns = first_seed(lambda seed: hit(user, foe, MATCHA_GOTCHA, arena, seed=seed) and foe.status == "burn")
    forced, foe, arena = duel()
    forced.combatant = replace(forced.combatant, ability="sheer-force")
    forced.hp = forced.max_hp // 2
    hit(forced, foe, MATCHA_GOTCHA, arena, seed=burns)
    assert foe.status is None and forced.hp > forced.max_hp // 2
