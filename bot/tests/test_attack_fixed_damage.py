import random

from attacks import attack, duel, first_seed, hit
from status_moves import put, resolve
from test_battle import TACKLE, mon

from ypoke import battle, move_effects, narration
from ypoke.battle import _Arena

SONIC_BOOM, DRAGON_RAGE, SEISMIC_TOSS, NIGHT_SHADE, PSYWAVE = (attack(49), attack(82), attack(69), attack(101),
                                                               attack(149))
SUPER_FANG, RUINATION, ENDEAVOR, FINAL_GAMBIT = attack(162), attack(877), attack(283), attack(515)
COUNTER, MIRROR_COAT, METAL_BURST, COMEUPPANCE = attack(68), attack(243), attack(368), attack(894)
GUILLOTINE, SHEER_COLD = attack(12), attack(329)
SWIFT = attack(129)


def lands(accuracy):
    return first_seed(lambda seed: random.Random(seed).random() * 100 < accuracy)


def misses(accuracy):
    return first_seed(lambda seed: random.Random(seed).random() * 100 >= accuracy)


def test_sonic_boom_dragon_rage_and_seismic_toss_deal_set_damage_whatever_the_stats():
    for move, damage in ((SONIC_BOOM, 20), (DRAGON_RAGE, 40), (SEISMIC_TOSS, 50)):
        for attack_stat in (10, 250):
            user, foe, arena = duel(attack=attack_stat, special_attack=attack_stat)
            for seed in range(5):
                action = hit(user, foe, move, arena, seed=lands(move.accuracy))
                assert foe.max_hp - foe.hp == damage and not action.critical, (move.name, seed)


def test_a_set_damage_move_still_misses_an_immune_type():
    user, foe, arena = duel(foe_types=("normal",))
    action = hit(user, foe, NIGHT_SHADE, arena)
    assert action.multiplier == 0 and foe.hp == foe.max_hp


def test_psywave_deals_half_to_one_and_a_half_times_the_level():
    user, foe, arena = duel()
    dealt = set()
    for seed in range(40):
        hit(user, foe, PSYWAVE, arena, seed=seed)
        dealt.add(foe.max_hp - foe.hp)
    assert min(dealt) >= 25 and max(dealt) <= 75 and len(dealt) > 10


def test_super_fang_and_ruination_halve_the_targets_current_hp():
    for move in (SUPER_FANG, RUINATION):
        user, foe, arena = duel()
        foe.hp = 61
        resolve(user, foe, move, arena, seed=lands(90))
        assert foe.hp == 31
        foe.hp = 1
        resolve(user, foe, move, arena, seed=lands(90))
        assert foe.hp == 0


def test_endeavor_brings_the_target_down_to_the_users_hp_and_fails_otherwise():
    user, foe, arena = duel()
    user.hp = 7
    resolve(user, foe, ENDEAVOR, arena)
    assert foe.hp == 7
    assert resolve(user, foe, ENDEAVOR, arena).failed


def test_final_gambit_deals_the_users_hp_and_faints_it_only_when_it_lands():
    user, foe, arena = duel(foe_types=("water",))
    user.hp = 40
    action = resolve(user, foe, FINAL_GAMBIT, arena)
    assert foe.max_hp - foe.hp == 40 and user.hp == 0 and action.attacker_fainted
    user, foe, arena = duel(foe_types=("ghost",))
    resolve(user, foe, FINAL_GAMBIT, arena)
    assert user.hp == user.max_hp


def test_counter_and_mirror_coat_return_double_the_damage_of_their_own_category():
    user, foe, arena = duel()
    resolve(foe, user, TACKLE, arena, seed=1)
    taken = user.max_hp - user.hp
    assert resolve(user, foe, MIRROR_COAT, arena).failed
    resolve(user, foe, COUNTER, arena)
    assert foe.max_hp - foe.hp == 2 * taken
    user, foe, arena = duel(foe_types=("fire",))
    resolve(foe, user, SWIFT, arena, seed=1)
    taken = user.max_hp - user.hp
    assert resolve(user, foe, COUNTER, arena).failed
    resolve(user, foe, MIRROR_COAT, arena)
    assert foe.max_hp - foe.hp == 2 * taken


def test_metal_burst_and_comeuppance_return_half_again_either_category_and_fail_with_nothing_taken():
    for move in (METAL_BURST, COMEUPPANCE):
        user, foe, arena = duel(foe_types=("fire",) if move is METAL_BURST else ("normal",))
        assert resolve(user, foe, move, arena).failed
        resolve(foe, user, SWIFT, arena, seed=1)
        taken = user.max_hp - user.hp
        resolve(user, foe, move, arena)
        assert foe.max_hp - foe.hp == taken * 3 // 2


def test_the_damage_taken_this_turn_clears_when_the_next_turn_starts():
    teams, arena = _teams()
    teams[0].active.hurt = (True, 30)
    teams[0].start_turn()
    assert teams[0].active.hurt is None


def test_an_ohko_move_knocks_out_on_a_hit_and_says_so():
    user, foe, arena = _leveled(50, 50)
    action = resolve(user, foe, GUILLOTINE, arena, seed=lands(30))
    assert foe.hp == 0 and action.knockout
    assert "💀일격필살" in narration._action_line(action, "🔵")
    user, foe, arena = _leveled(50, 50)
    assert resolve(user, foe, GUILLOTINE, arena, seed=misses(30)).missed


def test_ohko_accuracy_is_30_plus_the_level_gap_and_ignores_accuracy_stages():
    user, foe, arena = _leveled(70, 50)
    user.stages["accuracy"] = -6
    assert resolve(user, foe, GUILLOTINE, arena, seed=lands(50)).knockout
    user, foe, arena = _leveled(70, 50)
    assert resolve(user, foe, GUILLOTINE, arena, seed=misses(50)).missed


def test_an_ohko_move_fails_on_a_higher_level_or_sturdy_target():
    user, foe, arena = _leveled(50, 51)
    assert resolve(user, foe, GUILLOTINE, arena, seed=lands(30)).failed
    user, foe, arena = _leveled(50, 50, ability="sturdy")
    assert resolve(user, foe, GUILLOTINE, arena, seed=lands(30)).failed and foe.hp == foe.max_hp


def test_sheer_cold_fails_on_an_ice_type_and_hits_less_often_from_a_non_ice_user():
    user, foe, arena = _leveled(50, 50, user_types=("ice",), foe_types=("ice",))
    assert resolve(user, foe, SHEER_COLD, arena, seed=lands(30)).failed
    user, foe, arena = _leveled(50, 50)
    seed = first_seed(lambda seed: 20 <= random.Random(seed).random() * 100 < 30)
    assert resolve(user, foe, SHEER_COLD, arena, seed=seed).missed
    user, foe, arena = _leveled(50, 50, user_types=("ice",))
    assert resolve(user, foe, SHEER_COLD, arena, seed=seed).knockout


def test_the_ai_scores_set_damage_as_the_power_that_would_deal_it():
    user, foe, _ = duel()
    assert battle._move_score(user, foe, SEISMIC_TOSS, None) == 50 * 100 * 50 / 22
    user, foe, _ = _leveled(50, 51)
    assert battle._move_score(user, foe, GUILLOTINE, None) == 0
    user, foe, _ = duel()
    assert battle._move_score(user, foe, COUNTER, None) == 0


def test_set_damage_attacks_are_offered_once_their_effect_works():
    assert all(move_effects.attacks(move_id, None, "physical") for move_id in (69, 12, 117))
    assert not move_effects.attacks(622, None, "physical")
    assert not move_effects.attacks(73, None, "status")


def _leveled(user_level, foe_level, user_types=("normal",), foe_types=("normal",), ability=None):
    arena = _Arena()
    user = put(mon("사용자", user_types, level=user_level), arena)
    foe = put(mon("상대", foe_types, level=foe_level), arena, 1, ability=ability)
    return user, foe, arena


def _teams():
    arena = _Arena()
    teams = (battle._Team((mon("사용자", ("normal",)),), arena=arena),
             battle._Team((mon("상대", ("normal",)),), arena=arena, side=1))
    arena.teams = teams
    return teams, arena
