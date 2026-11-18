import random

from attacks import attack, duel
from status_moves import choose, data_move, pair
from test_attack_lock_bind import turn_of
from test_attack_two_turn import act, armed
from test_battle import TACKLE

from ypoke import battle, narration
from ypoke.battle import Action, Change
from ypoke.effects import hooks

SUCKER_PUNCH, UPPER_HAND, QUICK_ATTACK, FAKE_OUT = attack(389), attack(918), attack(98), attack(252)
FOCUS_PUNCH, SHELL_TRAP, BEAK_BLAST, SURF = attack(264), attack(704), attack(690), attack(57)
LAST_RESORT, BELCH, SYNCHRONOISE, POLTERGEIST = attack(387), attack(562), attack(485), attack(809)
DREAM_EATER, SNORE, BODY_SLAM, GIGATON_HAMMER, GLAIVE_RUSH = attack(138), attack(173), attack(34), attack(893), attack(862)
THUNDER_WAVE = data_move(86)


def foe_picks(foe, *moves, picked=0):
    armed(foe, *moves)
    foe.choice = picked


def test_sucker_punch_hits_a_foe_about_to_attack_but_fails_on_a_status_move_or_once_the_foe_moved():
    user, foe, arena = duel()
    armed(user, SUCKER_PUNCH)
    foe_picks(foe, TACKLE, THUNDER_WAVE)
    assert act(user, foe, arena).defender_hp < 100
    foe_picks(foe, TACKLE, THUNDER_WAVE, picked=1)
    assert act(user, foe, arena).failed and battle._move_score(user, foe, SUCKER_PUNCH, None) == 0
    foe_picks(foe, TACKLE)
    foe.acted = True
    assert act(user, foe, arena).failed


def test_upper_hand_needs_a_raised_priority_attack_and_flinches_the_foe():
    user, foe, arena = duel()
    armed(user, UPPER_HAND)
    foe_picks(foe, TACKLE)
    assert act(user, foe, arena).failed
    foe_picks(foe, QUICK_ATTACK)
    assert act(user, foe, arena).defender_hp < 100 and "flinch" in foe.volatiles


def test_fake_out_works_on_the_first_turn_only():
    user, foe, arena = duel()
    armed(user, FAKE_OUT, TACKLE)
    assert battle._move_score(user, foe, FAKE_OUT, None) > 0
    assert act(user, foe, arena).defender_hp < 100 and "flinch" in foe.volatiles
    assert act(user, foe, arena, turn=2).failed and battle._move_score(user, foe, FAKE_OUT, None) == 0
    user.leave()
    assert battle._move_score(user, foe, FAKE_OUT, None) > 0


def test_focus_punch_loses_focus_once_hit_and_the_chooser_saves_it_for_a_foe_that_does_not_attack():
    user, foe, arena = duel()
    armed(user, FOCUS_PUNCH)
    user.hit_by_foe = True
    lost = act(user, foe, arena)
    assert (lost.failed, lost.blocked, foe.hp) == (True, "lost-focus", foe.max_hp)
    user.hit_by_foe = False
    assert act(user, foe, arena).defender_hp < 100
    foe_picks(foe, TACKLE, THUNDER_WAVE)
    assert battle._move_score(user, foe, FOCUS_PUNCH, None) == 0
    foe.choice = 1
    assert battle._move_score(user, foe, FOCUS_PUNCH, None) > 0


def test_shell_trap_goes_off_only_after_a_physical_hit_and_beak_blast_burns_the_hitter():
    user, foe, arena = duel()
    armed(user, SHELL_TRAP, BEAK_BLAST)
    assert act(user, foe, arena).blocked == "shell-trap"
    user.hurt = (False, 10)
    assert act(user, foe, arena).failed
    user.hurt = (True, 10)
    assert act(user, foe, arena).defender_hp < 100
    foe_picks(foe, SURF)
    assert battle._move_score(user, foe, SHELL_TRAP, None) == 0
    burnt = act(user, foe, arena, index=1)
    assert Change(1, foe.combatant.name, "burn") in burnt.changes and foe.status == "burn"
    user, foe, arena = duel()
    armed(user, BEAK_BLAST)
    assert act(user, foe, arena).changes == () and foe.status is None


def test_last_resort_waits_for_every_other_move_and_belch_for_a_berry():
    user, foe, arena = duel()
    armed(user, LAST_RESORT, TACKLE)
    assert act(user, foe, arena).failed
    user.pp[1] -= 1
    assert act(user, foe, arena).defender_hp < 100
    armed(user, LAST_RESORT)
    assert act(user, foe, arena).failed
    armed(user, BELCH)
    assert act(user, foe, arena).failed
    user.hp, user.item = 1, "sitrus-berry"
    hooks.call("items", "sitrus-berry", "eaten", user, 0, 1)
    assert user.ate_berry and not act(user, foe, arena, seed=_hit_seed(BELCH)).failed


def test_synchronoise_poltergeist_and_dream_eater_need_their_target():
    user, foe, arena = duel(user_types=("psychic",))
    armed(user, SYNCHRONOISE, POLTERGEIST, DREAM_EATER)
    assert act(user, foe, arena).failed
    foe.combatant = battle.replace(foe.combatant, types=("psychic",))
    assert not act(user, foe, arena).failed
    assert act(user, foe, arena, index=1).failed
    foe.item = "leftovers"
    assert not act(user, foe, arena, index=1, seed=_hit_seed(POLTERGEIST)).failed
    assert act(user, foe, arena, index=2).failed
    foe.combatant = battle.replace(foe.combatant, types=("normal",))
    foe.status, foe.sleep_left, user.hp = "sleep", 3, 1
    assert act(user, foe, arena, index=2).drained and user.hp > 1


def test_snore_works_only_asleep_and_a_sleeping_chooser_picks_it():
    user, foe, arena = duel()
    armed(user, SNORE)
    assert act(user, foe, arena).failed
    user.status, user.sleep_left = "sleep", 2
    assert act(user, foe, arena).defender_hp < 100 and user.status == "sleep"
    teams, arena = pair([BODY_SLAM, SNORE])
    assert choose(teams, arena) == 0
    teams[0].active.status, teams[0].active.sleep_left = "sleep", 2
    assert choose(teams, arena) == 1


def test_gigaton_hammer_cannot_be_used_twice_in_a_row():
    user, foe, arena = duel(hp=255)
    armed(user, GIGATON_HAMMER, TACKLE)
    foe.hp = foe.max_hp = 999
    assert not turn_of(user, foe, arena, 1).failed
    assert battle._move_score(user, foe, GIGATON_HAMMER, None) == 0
    assert turn_of(user, foe, arena, 2).failed
    turn_of(user, foe, arena, 3, index=1)
    assert not turn_of(user, foe, arena, 4).failed


def test_glaive_rush_leaves_its_user_open_to_sure_double_hits_until_the_next_turn_ends():
    user, foe, arena = duel()
    armed(user, GLAIVE_RUSH)
    before = battle._unrolled_damage(foe, user, TACKLE, 1.0, None)
    act(user, foe, arena)
    assert battle._unrolled_damage(foe, user, TACKLE, 1.0, None) == 2 * before and battle._sure_hit(foe, user)
    for turn in (1, 2):
        battle._volatile_upkeep(turn, (user, foe), [], random.Random(0))
    assert "glaive-rush" not in user.volatiles and not battle._sure_hit(foe, user)


def test_the_lost_focus_and_shell_trap_lines_read_in_korean():
    lost = Action(1, 0, "A", "B", FOCUS_PUNCH.name, failed=True, blocked="lost-focus")
    trap = Action(1, 0, "A", "B", SHELL_TRAP.name, failed=True, blocked="shell-trap")
    assert narration._action_line(lost, "▶").endswith("😵집중이 흐트러졌다")
    assert narration._action_line(trap, "▶").endswith("🐚트랩이 터지지 않았다")


def _hit_seed(move):
    return next(seed for seed in range(200) if random.Random(seed).random() * 100 < move.accuracy)
