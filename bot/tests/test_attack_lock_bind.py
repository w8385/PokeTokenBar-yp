import random

from attacks import attack, draws, duel
from status_moves import pair, resolve
from test_attack_two_turn import act, armed
from test_battle import TACKLE

from ypoke import battle, narration
from ypoke.battle import Action, Change, VolatileEnd, VolatileTick

OUTRAGE, UPROAR, ROLLOUT, BIDE, RAGE = attack(200), attack(253), attack(205), attack(117), attack(99)
WRAP, WHIRLPOOL, RAPID_SPIN, DIVE = attack(35), attack(250), attack(229), attack(291)


def turn_of(user, foe, arena, turn, index=0, rng=None):
    arena.turn = turn
    fighters = (user, foe) if user.side == 0 else (foe, user)
    action = battle._act(turn, user.side, fighters, index, arena.weather, rng or random.Random(turn), arena)
    battle._volatile_upkeep(turn, fighters, [], random.Random(turn))
    return action


def test_outrage_locks_its_user_in_for_two_or_three_turns_then_confuses_it():
    user, foe, arena = duel()
    armed(user, OUTRAGE, TACKLE)
    used = []
    for turn in range(1, 5):
        foe.hp = foe.max_hp
        used.append(turn_of(user, foe, arena, turn, index=1 if turn > 1 else 0))
        if "rampage" not in user.volatiles:
            break
    assert len(used) in (2, 3) and all(action.move == OUTRAGE.name for action in used)
    assert Change(0, user.combatant.name, "rampage") in used[0].changes
    assert used[-1].changes[-1] == Change(0, user.combatant.name, "fatigue") and user.confusion_left > 0
    assert user.pp == [OUTRAGE.pp - 1, TACKLE.pp]


def test_a_lock_the_user_cannot_keep_up_ends_without_confusion():
    user, foe, arena = duel()
    armed(user, OUTRAGE)
    turn_of(user, foe, arena, 1)
    foe.combatant = battle.replace(foe.combatant, types=("fairy",))
    assert turn_of(user, foe, arena, 2).multiplier == 0
    assert "rampage" not in user.volatiles and user.confusion_left == 0
    user, foe, arena = duel()
    armed(user, OUTRAGE)
    turn_of(user, foe, arena, 1)
    user.status, user.sleep_left = "sleep", 2
    assert turn_of(user, foe, arena, 2).blocked == "sleep" and "rampage" not in user.volatiles


def test_rollout_doubles_with_each_hit_for_five_turns_and_a_miss_ends_it():
    user, foe, arena = duel()
    armed(user, ROLLOUT)
    foe.stats["defense"] = 999
    powers, dealt = [], []
    for turn in range(1, 6):
        powers.append(battle._power(user, foe, ROLLOUT, None, 1.0))
        foe.hp = foe.max_hp
        assert not turn_of(user, foe, arena, turn, rng=draws(0.0)).missed
        dealt.append(foe.max_hp - foe.hp)
    assert powers == [30, 60, 120, 240, 480] and "rollout" not in user.volatiles
    assert dealt == sorted(set(dealt))
    turn_of(user, foe, arena, 6, rng=draws(0.0))
    assert turn_of(user, foe, arena, 7, rng=draws(0.95)).missed
    assert "rollout" not in user.volatiles and battle._power(user, foe, ROLLOUT, None, 1.0) == 30


def test_uproar_keeps_its_user_awake_and_wakes_a_sleeping_target():
    user, foe, arena = duel()
    armed(user, UPROAR)
    foe.status, foe.sleep_left = "sleep", 3
    first = turn_of(user, foe, arena, 1)
    assert Change(1, foe.combatant.name, "woke") in first.changes and foe.status is None
    assert not battle._open_to("sleep", user) and battle._open_to("sleep", foe)
    for turn in (2, 3):
        foe.hp = foe.max_hp
        assert turn_of(user, foe, arena, turn).move == UPROAR.name
    assert "uproar" not in user.volatiles and battle._open_to("sleep", user)


def test_bide_stores_two_turns_of_damage_then_strikes_back_double():
    user, foe, arena = duel()
    armed(user, BIDE)
    assert turn_of(user, foe, arena, 1).effect == "bide"
    user.hp -= 20
    assert turn_of(user, foe, arena, 2).effect == "bide"
    user.hp -= 10
    strike = turn_of(user, foe, arena, 3)
    assert foe.max_hp - foe.hp == 60 and not strike.effect and user.pp[0] == BIDE.pp - 1
    user, foe, arena = duel()
    armed(user, BIDE)
    for turn in (1, 2):
        turn_of(user, foe, arena, turn)
    assert turn_of(user, foe, arena, 3).failed and foe.hp == foe.max_hp


def test_rage_raises_attack_for_each_hit_taken_while_the_user_keeps_raging():
    user, foe, arena = duel(hp=255)
    armed(user, RAGE, TACKLE)
    turn_of(user, foe, arena, 1)
    for _ in range(2):
        resolve(foe, user, TACKLE, arena, turn=1)
    raged = turn_of(user, foe, arena, 2)
    assert Change(0, user.combatant.name, "attack", 2) in raged.changes and user.stages["attack"] == 2
    turn_of(user, foe, arena, 3, index=1)
    resolve(foe, user, TACKLE, arena, turn=3)
    assert "rage" not in user.volatiles
    assert Change(0, user.combatant.name, "attack", 1) not in turn_of(user, foe, arena, 4).changes


def test_a_bind_hurts_its_target_each_turn_for_four_or_five_turns_then_lets_go():
    user, foe, arena = duel()
    armed(user, WRAP)
    bound = act(user, foe, arena, seed=_hit_seed(WRAP))
    assert Change(1, foe.combatant.name, "binding") in bound.changes
    foe.hp = foe.max_hp
    events = []
    for turn in range(1, 8):
        battle._volatile_upkeep(turn, (user, foe), events, random.Random(0))
    ticks = [event for event in events if isinstance(event, VolatileTick)]
    assert len(ticks) in (4, 5) and foe.max_hp - foe.hp == len(ticks) * (foe.max_hp // 8)
    assert events[-1] == VolatileEnd(len(ticks) + 1, 1, foe.combatant.name, "binding")


def test_a_bind_ends_once_the_binder_leaves_and_rapid_spin_shakes_it_off():
    teams, arena = pair([WRAP], foe_moves=[RAPID_SPIN])
    user, foe = (team.active for team in teams)
    act(user, foe, arena, seed=_hit_seed(WRAP))
    user.leave()
    events = []
    battle._volatile_upkeep(1, (user, foe), events, random.Random(0))
    assert events == [VolatileEnd(1, 1, foe.combatant.name, "binding")]
    act(user, foe, arena, seed=_hit_seed(WRAP))
    assert "binding" in foe.volatiles
    act(foe, user, arena)
    assert "binding" not in foe.volatiles


def test_whirlpool_hits_a_diving_foe_for_double():
    user, foe, arena = duel()
    armed(foe, DIVE)
    act(foe, user, arena)
    assert battle._hidden(foe, WHIRLPOOL) == 2 and battle._hidden(foe, WRAP) == 0


def test_the_lock_and_bind_lines_read_in_korean():
    bound = Action(1, 0, "A", "B", WRAP.name, changes=(Change(1, "B", "binding"),))
    tired = Action(3, 0, "A", "B", OUTRAGE.name, changes=(Change(0, "A", "fatigue"),))
    started = Action(1, 0, "A", "B", OUTRAGE.name, changes=(Change(0, "A", "rampage"),))
    assert narration._action_line(bound, "▶").endswith("🪢조여졌다")
    assert narration._action_line(tired, "▶").endswith("자신 💫지쳐서 혼란")
    assert narration._action_line(started, "▶").endswith("자신 🔒날뛰기 시작")
    assert narration._action_line(Action(1, 0, "A", "B", BIDE.name, effect="bide"), "▶").endswith("😤참는 중")
    assert narration._event_lines(VolatileTick(2, 1, "B", "binding", 75)) == ["🔴 B 🪢조이기 75%"]
    assert narration._event_lines(VolatileEnd(6, 1, "B", "binding")) == ["🔴 B 🪢조이기 풀려났다"]


def _hit_seed(move):
    return next(seed for seed in range(200) if random.Random(seed).random() * 100 < move.accuracy)
