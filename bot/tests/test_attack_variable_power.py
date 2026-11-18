import random
import re
from dataclasses import replace
from pathlib import Path

import pytest
from attacks import attack, duel, hit
from status_moves import data_move, put, resolve
from test_battle import IVS, TACKLE, mon

from ypoke import battle, battle_data, move_effects, move_power, narration
from ypoke.battle import Carry, Change, _Arena, _Team
from ypoke.effects import hooks

LOW_KICK, HEAVY_SLAM, FLAIL, WRING_OUT, HARD_PRESS = attack(67), attack(484), attack(175), attack(378), attack(912)
RETURN, FRUSTRATION, ELECTRO_BALL, GYRO_BALL = attack(216), attack(218), attack(486), attack(360)
TRUMP_CARD, PUNISHMENT, SPIT_UP, HIDDEN_POWER = attack(376), attack(386), attack(255), attack(237)
MAGNITUDE, PRESENT, FICKLE_BEAM = attack(222), attack(217), attack(907)
FURY_CUTTER, ECHOED_VOICE, ASSURANCE = attack(210), attack(497), attack(372)
FUSION_FLARE, FUSION_BOLT, BEAT_UP = attack(558), attack(559), attack(251)
STOCKPILE = data_move(254)
SOURCE = Path(__file__).resolve().parents[1] / "ypoke"


def power(move, user, foe, hit=0, weather=None):
    return move_power.power(move, user, foe, weather, 1.0, hit)


def test_low_kick_grows_with_the_targets_weight_and_heavy_slam_with_the_weight_ratio():
    user, foe, _ = duel()
    for weight, expected in ((99, 20), (100, 40), (499, 60), (999, 80), (1999, 100), (2000, 120)):
        foe.combatant = replace(foe.combatant, weight=weight)
        assert power(LOW_KICK, user, foe) == expected, weight
    user.combatant = replace(user.combatant, weight=1000)
    for weight, expected in ((200, 120), (250, 100), (333, 80), (500, 60), (501, 40), (2000, 40)):
        foe.combatant = replace(foe.combatant, weight=weight)
        assert power(HEAVY_SLAM, user, foe) == expected, weight


def test_flail_grows_as_the_users_hp_falls_and_wring_out_shrinks_with_the_targets():
    user, foe, _ = duel()
    for share, expected in ((1.0, 20), (0.5, 40), (0.3, 80), (0.15, 100), (0.08, 150), (0.01, 200)):
        user.hp = max(1, int(user.max_hp * share))
        assert power(FLAIL, user, foe) == expected, share
    foe.hp = foe.max_hp
    assert (power(WRING_OUT, user, foe), power(HARD_PRESS, user, foe)) == (120, 100)
    foe.hp = foe.max_hp // 2
    assert power(WRING_OUT, user, foe) == 120 * foe.hp // foe.max_hp
    foe.hp = 1
    assert power(WRING_OUT, user, foe) == 1


def test_return_and_frustration_take_their_power_at_the_highest_friendship():
    user, foe, _ = duel()
    assert (power(RETURN, user, foe), power(FRUSTRATION, user, foe)) == (102, 1)


def test_electro_ball_grows_with_the_users_speed_over_the_targets_and_gyro_ball_with_the_reverse():
    user, foe, _ = duel()
    foe.stats["speed"] = 100
    for speed, expected in ((400, 150), (300, 120), (200, 80), (100, 60), (99, 40)):
        user.stats["speed"] = speed
        assert power(ELECTRO_BALL, user, foe) == expected, speed
    user.stats["speed"], foe.stats["speed"] = 50, 100
    assert power(GYRO_BALL, user, foe) == 51
    user.stats["speed"] = 10
    assert power(GYRO_BALL, user, foe) == 150


def test_trump_card_grows_as_its_pp_runs_out_and_the_ai_counts_the_pp_this_use_spends():
    user, foe, _ = duel()
    user.combatant = replace(user.combatant, moves=(TRUMP_CARD,))
    for left, expected in ((5, 40), (4, 40), (3, 50), (2, 60), (1, 80), (0, 200)):
        user.pp = [left]
        assert power(TRUMP_CARD, user, foe) == expected, left
    user.pp = [1]
    assert power(TRUMP_CARD, user, foe, hit=None) == 200


def test_punishment_grows_with_each_raised_stage_of_the_target():
    user, foe, _ = duel()
    assert power(PUNISHMENT, user, foe) == 60
    foe.stages.update(attack=2, speed=1, defense=-1)
    assert power(PUNISHMENT, user, foe) == 120
    foe.stages.update(attack=6, special_attack=6)
    assert power(PUNISHMENT, user, foe) == 200


def test_spit_up_fails_without_a_stockpile_and_spends_it_with_the_defenses_it_raised():
    user, foe, arena = duel()
    assert hit(user, foe, SPIT_UP, arena).failed and foe.hp == foe.max_hp
    for _ in range(2):
        resolve(user, foe, STOCKPILE, arena)
    assert (user.stages["defense"], user.stages["special_defense"]) == (2, 2)
    assert power(SPIT_UP, user, foe) == 200
    action = hit(user, foe, SPIT_UP, arena)
    assert foe.hp < foe.max_hp and "stockpile" not in user.memory
    assert (user.stages["defense"], user.stages["special_defense"]) == (0, 0)
    assert {change.kind for change in action.changes} == {"defense", "special_defense"}


def test_hidden_power_takes_its_type_from_the_users_ivs():
    arena = _Arena()
    odd = put(replace(mon("홀수", ("normal",)), ivs=replace(IVS, **dict.fromkeys(IVS.__dataclass_fields__, 31))), arena)
    even = put(replace(mon("짝수", ("normal",)), ivs=replace(IVS, **dict.fromkeys(IVS.__dataclass_fields__, 30))), arena)
    assert move_power.typed(HIDDEN_POWER, None, odd).type == "dark"
    assert move_power.typed(HIDDEN_POWER, None, even).type == "fighting"
    assert move_power.typed(HIDDEN_POWER, None).type == "normal"


def test_magnitude_and_fickle_beam_use_the_power_drawn_for_the_use_and_the_ai_their_mean():
    user, foe, _ = duel()
    seen = set()
    for seed in range(200):
        hooks.move(MAGNITUDE, "draws", user, random.Random(seed))
        seen.add(power(MAGNITUDE, user, foe))
    assert seen == {10, 30, 50, 70, 90, 110, 150}
    assert power(MAGNITUDE, user, foe, hit=None) == pytest.approx(71)
    user.memory["fickle-beam"] = True
    assert power(FICKLE_BEAM, user, foe) == 160
    user.memory["fickle-beam"] = False
    assert power(FICKLE_BEAM, user, foe) == 80
    assert power(FICKLE_BEAM, user, foe, hit=None) == pytest.approx(104)


def test_present_drawing_its_gift_heals_the_target_instead_of_hurting_it():
    user, foe, arena = duel()
    heals = next(seed for seed in range(200) if _present_gift(seed) == 0)
    hurts = next(seed for seed in range(200) if _present_gift(seed) == 40)
    foe.hp = foe.max_hp // 2
    action = _use(user, foe, PRESENT, arena, heals)
    assert foe.hp == foe.max_hp // 2 + foe.max_hp // 4
    assert Change(1, foe.combatant.name, "healed") in action.changes
    assert "💚HP 회복" in narration._change_tag(action.changes[-1], 0)
    foe.hp = foe.max_hp
    assert _use(user, foe, PRESENT, arena, heals).changes == () and foe.hp == foe.max_hp
    _use(user, foe, PRESENT, arena, hurts)
    assert foe.hp < foe.max_hp


def test_fury_cutter_doubles_each_turn_in_a_row_it_hits_and_resets_after_a_turn_off():
    user, foe, arena = duel()
    powers = []
    for turn in (1, 2, 3, 4, 6):
        arena.turn, foe.hp = turn, foe.max_hp
        powers.append(power(FURY_CUTTER, user, foe))
        _use(user, foe, FURY_CUTTER, arena, seed=_lands(FURY_CUTTER))
    assert powers == [40, 80, 160, 160, 40]
    user.leave()
    arena.turn = 7
    assert power(FURY_CUTTER, user, foe) == 40


def test_echoed_voice_adds_its_power_each_turn_in_a_row_up_to_200():
    user, foe, arena = duel()
    powers = []
    for turn in range(1, 7):
        arena.turn, foe.hp = turn, foe.max_hp
        powers.append(power(ECHOED_VOICE, user, foe))
        _use(user, foe, ECHOED_VOICE, arena)
    assert powers == [40, 80, 120, 160, 200, 200]


def test_assurance_doubles_on_a_target_a_move_already_hurt_this_turn():
    user, foe, _ = duel()
    assert power(ASSURANCE, user, foe) == 60
    foe.hurt = (True, 10)
    assert power(ASSURANCE, user, foe) == 120


def test_fusion_bolt_doubles_right_after_fusion_flare_in_the_same_turn_only():
    user, foe, arena = duel()
    foe.combatant, foe.pp = replace(foe.combatant, moves=(FUSION_FLARE,)), [FUSION_FLARE.pp]
    arena.turn = 3
    battle._act(3, 1, (user, foe), 0, arena.weather, random.Random(0), arena)
    assert (arena.last_move, arena.last_move_turn) == (FUSION_FLARE, 3)
    assert power(FUSION_BOLT, user, foe) == 200
    assert power(FUSION_FLARE, user, foe) == 100
    arena.turn = 4
    assert power(FUSION_BOLT, user, foe) == 100


def test_beat_up_hits_once_per_healthy_unstatused_member_with_its_own_power():
    arena = _Arena()
    roster = (mon("선봉", ("dark",), attack=120), mon("후보", ("normal",), attack=55),
              mon("잠꾸러기", ("normal",), attack=100), mon("기절", ("normal",)))
    team = _Team(roster, (None, None, Carry(50, "sleep"), Carry(50)), arena=arena)
    foe_team = _Team((mon("상대", ("normal",), hp=255),), arena=arena, side=1)
    arena.teams = (team, foe_team)
    team.place(3, battle._Fighter.enter(roster[3]))
    team.fighters[3].hp = 0
    user, foe = team.active, foe_team.active
    assert [power(BEAT_UP, user, foe, hit) for hit in (0, 1)] == [17, 10]
    assert power(BEAT_UP, user, foe, hit=None) == pytest.approx(13.5)
    assert battle._expected_hits(BEAT_UP, user, 100) == 2
    assert _use(user, foe, BEAT_UP, arena).hits == 2


def test_beat_up_fails_when_no_member_can_strike():
    user, foe, arena = duel()
    user.status = "burn"
    action = _use(user, foe, BEAT_UP, arena)
    assert action.failed and foe.hp == foe.max_hp


def test_attacks_whose_effect_sets_their_power_are_offered_and_count_as_damaging():
    for move_id in (67, 175, 216, 222, 251, 255, 360, 912):
        entry = battle_data.table("moves")[str(move_id)]
        assert move_effects.attacks(move_id, entry["power"], entry["class"]), move_id
    for move_id in (363, 374):
        assert not move_effects.attacks(move_id, None, "physical"), move_id
    assert LOW_KICK.damaging and attack(69).damaging and TACKLE.damaging
    assert not STOCKPILE.damaging and not data_move(240).damaging


def test_no_code_reads_a_moves_power_as_whether_it_is_an_attack():
    truthy = re.compile(r"(?:\b(?:not|and|or|if)\s+|any\()\w+\.power\b(?!\s*(?:[-+*/<>]|==|!=))"
                        r"|\b\w+\.power\s+(?:and|or)\b")
    found = [f"{path.name}: {match.group()}" for path in sorted(SOURCE.rglob("*.py"))
             for match in truthy.finditer(path.read_text()) if not match.group().startswith("self.power")]
    assert found == []


def _present_gift(seed):
    user, foe, arena = duel()
    _use(user, foe, PRESENT, arena, seed)
    return user.memory.get("present")


def _lands(move):
    return next(seed for seed in range(200) if random.Random(seed).random() * 100 < move.accuracy)


def _use(user, foe, move, arena, seed=0):
    user.combatant = replace(user.combatant, moves=(move,))
    user.pp = [move.pp]
    fighters = (user, foe) if user.side == 0 else (foe, user)
    return battle._resolve(arena.turn or 1, user.side, fighters, 0, arena.weather, random.Random(seed), arena)
