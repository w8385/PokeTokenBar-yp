import random
from dataclasses import replace

import pytest
from attacks import attack
from status_moves import data_move, resolve
from test_ability_damage import FLAMETHROWER, SWIFT, TACKLE, facing
from test_battle import mon

from ypoke import battle
from ypoke.battle import AbilityAct, Change, _enter_battle, _Team, _Weather
from ypoke.effects import hooks
from ypoke.narration import battle_turns

DARK_PULSE, BUG_BITE, WATER_GUN, FROST_BREATH = attack(399), attack(450), attack(55), attack(524)
DOUBLE_KICK, CLOSE_COMBAT, GUST = attack(24), attack(370), attack(16)
GROWL, SCREECH, SWORDS_DANCE, TAILWIND = data_move(45), data_move(103), data_move(14), data_move(366)
WILL_O_WISP, TAUNT = data_move(261), data_move(269)
WEAK = {"attack": 10, "special_attack": 10}


def knock_out(user_ability, move=TACKLE, foe_hp=1, **stats):
    user, foe, arena = facing(user_ability, None, **stats)
    foe.hp = foe_hp
    resolve(user, foe, move, arena)
    return user, foe


@pytest.mark.parametrize(("ability", "stats", "stat"), [
    ("moxie", {}, "attack"), ("chilling-neigh", {}, "attack"), ("grim-neigh", {}, "special_attack"),
    ("as-one-glastrier", {}, "attack"), ("as-one-spectrier", {}, "special_attack"),
    ("beast-boost", {"speed": 300}, "speed"), ("beast-boost", {"defense": 300}, "defense"),
    ("eelevate", {"speed": 300}, "speed"),
])
def test_knocking_a_foe_out_raises_a_stat(ability, stats, stat):
    user, foe = knock_out(ability, **stats)
    assert foe.hp == 0 and user.stages[stat] == 1
    assert sum(user.stages.values()) == 1
    user, foe = knock_out(ability, foe_hp=10_000, **{**stats, **WEAK})
    assert foe.hp > 0 and sum(user.stages.values()) == 0


def test_as_one_keeps_the_foe_off_its_berry():
    user, foe, _ = facing("as-one-glastrier", None)
    assert battle._unnerved(foe, "sitrus-berry") and not battle._unnerved(user, "sitrus-berry")


def test_soul_heart_raises_special_attack_as_the_foe_faints():
    teams, arena = two_on_one("soul-heart")
    events = []
    battle._replace_fainted(teams, 1, arena, _Weather(), random.Random(0), events)
    holder = teams[0].active
    assert holder.stages["special_attack"] == 1
    assert [event.ability for event in events if isinstance(event, AbilityAct)] == ["soul-heart"]
    teams, arena = two_on_one("soul-heart")
    teams[0].active.hp = 0
    battle._replace_fainted(teams, 1, arena, _Weather(), random.Random(0), events := [])
    assert not any(isinstance(event, AbilityAct) for event in events)


def two_on_one(holder_ability):
    """The holder against a team of two whose first member has fainted."""
    arena = battle._Arena()
    teams = (_Team((replace(mon("사용자", ("normal",)), ability=holder_ability),), arena=arena),
             _Team((mon("상대", ("normal",)), mon("다음", ("normal",))), arena=arena, side=1))
    arena.teams = teams
    teams[1].active.hp = 0
    return teams, arena


@pytest.mark.parametrize(("ability", "attack_stage", "special_stage"), [
    ("defiant", 1, 0), ("competitive", -1, 2), (None, -1, 0),
])
def test_a_foes_drop_draws_a_two_stage_answer(ability, attack_stage, special_stage):
    user, foe, arena = facing(None, ability)
    resolve(user, foe, GROWL, arena)
    assert (foe.stages["attack"], foe.stages["special_attack"]) == (attack_stage, special_stage)


def test_defiant_ignores_the_holders_own_drops():
    user, foe, arena = facing("defiant", None, **WEAK)
    resolve(user, foe, CLOSE_COMBAT, arena)
    assert user.stages["defense"] == -1 and user.stages["attack"] == 0


def entry(holder_ability, foe_ability=None, **foe_stats):
    user, foe, _ = facing(holder_ability, foe_ability)
    for stat, value in foe_stats.items():
        foe.stats[stat] = value
    return user, foe, _enter_battle((user, foe), _Weather(), random.Random(0))


@pytest.mark.parametrize(("ability", "stat"), [("intrepid-sword", "attack"), ("dauntless-shield", "defense")])
def test_an_entry_boost_comes_once_a_battle(ability, stat):
    user, foe, triggers = entry(ability)
    assert user.stages[stat] == 1 and [trigger.ability for trigger in triggers] == [ability]
    user.leave()
    assert _enter_battle((user, foe), _Weather(), random.Random(0)) == [] and user.stages[stat] == 0


def test_supersweet_syrup_lowers_the_foes_evasion_once_a_battle():
    user, foe, _ = entry("supersweet-syrup")
    assert foe.stages["evasion"] == -1
    foe.stages["evasion"] = 0
    assert _enter_battle((user, foe), _Weather(), random.Random(0)) == [] and foe.stages["evasion"] == 0


@pytest.mark.parametrize(("foe_stats", "stat"), [
    ({"defense": 50, "special_defense": 100}, "attack"), ({"defense": 100, "special_defense": 50}, "special_attack"),
    ({"defense": 80, "special_defense": 80}, "special_attack"),
])
def test_download_raises_the_attack_the_foes_weaker_defense_meets(foe_stats, stat):
    user, _, _ = entry("download", **foe_stats)
    assert user.stages[stat] == 1 and sum(user.stages.values()) == 1


def struck(move, foe_ability, user_ability=None, foe_hp=None, **stats):
    """The user's move on a sturdy foe; the user and the foe."""
    user, foe, arena = facing(user_ability, foe_ability, **{**WEAK, **stats})
    foe.hp = foe.max_hp if foe_hp is None else foe_hp
    resolve(user, foe, move, arena)
    return user, foe


@pytest.mark.parametrize(("ability", "move", "expected"), [
    ("stamina", TACKLE, {"defense": 1}), ("stamina", DOUBLE_KICK, {"defense": 2}), ("stamina", GROWL, {"attack": -1}),
    ("weak-armor", TACKLE, {"defense": -1, "speed": 2}), ("weak-armor", SWIFT, {}),
    ("justified", DARK_PULSE, {"attack": 1}), ("justified", TACKLE, {}),
    ("rattled", BUG_BITE, {"speed": 1}), ("rattled", TACKLE, {}),
    ("steam-engine", WATER_GUN, {"speed": 6}), ("steam-engine", FLAMETHROWER, {"speed": 6}), ("steam-engine", TACKLE, {}),
    ("water-compaction", WATER_GUN, {"defense": 2}), ("water-compaction", TACKLE, {}),
    ("thermal-exchange", FLAMETHROWER, {"attack": 1}), ("thermal-exchange", WATER_GUN, {}),
])
def test_a_hit_moves_the_holders_stages(ability, move, expected):
    _, foe = struck(move, ability)
    assert {stat: stage for stat, stage in foe.stages.items() if stage} == expected


def test_a_knocked_out_holder_answers_no_hit():
    _, foe = struck(TACKLE, "stamina", foe_hp=1, attack=200)
    assert foe.hp == 0 and foe.stages["defense"] == 0


def test_thermal_exchange_cannot_be_burned():
    _, foe = struck(WILL_O_WISP, "thermal-exchange")
    assert foe.status is None


@pytest.mark.parametrize(("ability", "expected"), [
    ("berserk", {"special_attack": 1}),
    ("anger-shell", {"attack": 1, "special_attack": 1, "speed": 1, "defense": -1, "special_defense": -1}),
])
def test_dropping_to_half_hp_moves_the_stages_once(ability, expected):
    user, foe, arena = facing(None, ability, **WEAK)
    foe.hp = foe.max_hp // 2 + 1
    resolve(user, foe, TACKLE, arena)
    assert {stat: stage for stat, stage in foe.stages.items() if stage} == expected
    resolve(user, foe, TACKLE, arena)
    assert {stat: stage for stat, stage in foe.stages.items() if stage} == expected


def test_anger_point_maxes_attack_on_a_critical_hit_only():
    _, foe = struck(FROST_BREATH, "anger-point")
    assert foe.stages["attack"] == battle.MAX_STAGE
    _, foe = struck(SWIFT, "anger-point")
    assert foe.stages["attack"] == 0


@pytest.mark.parametrize(("ability", "move", "charged"), [
    ("electromorphosis", TACKLE, True), ("electromorphosis", GROWL, False),
    ("wind-power", GUST, True), ("wind-power", TACKLE, False),
])
def test_a_hit_charges_the_holder(ability, move, charged):
    _, foe = struck(move, ability)
    assert ("charge" in foe.volatiles) == charged


@pytest.mark.parametrize(("ability", "charged", "attack_stage"), [
    ("wind-power", True, 0), ("wind-rider", False, 1), (None, False, 0),
])
def test_tailwind_charges_wind_power_and_raises_wind_riders_attack(ability, charged, attack_stage):
    user, foe, arena = facing(ability, None)
    resolve(user, foe, TAILWIND, arena)
    assert ("charge" in user.volatiles) == charged and user.stages["attack"] == attack_stage


@pytest.mark.parametrize(("move", "user_ability", "speed"), [
    (TACKLE, None, -1), (DOUBLE_KICK, None, -2), (TACKLE, "clear-body", 0), (GROWL, None, 0),
])
def test_cotton_down_slows_whoever_hits_it(move, user_ability, speed):
    user, _ = struck(move, "cotton-down", user_ability)
    assert user.stages["speed"] == speed


@pytest.mark.parametrize(("ability", "move", "landed"), [
    ("seed-sower", TACKLE, lambda arena: arena.terrain == "grassy-terrain"),
    ("sand-spit", SWIFT, lambda arena: arena.weather.kind == "sandstorm"),
    ("toxic-debris", TACKLE, lambda arena: arena.hazards[0] == {"toxic-spikes": 1}),
])
def test_a_hit_changes_the_field(ability, move, landed):
    _, foe = struck(move, ability)
    assert landed(foe.arena)
    _, foe = struck(GROWL, ability)
    assert not landed(foe.arena)


def test_toxic_debris_only_answers_physical_moves():
    _, foe = struck(SWIFT, "toxic-debris")
    assert foe.arena.hazards[0] == {}


def test_speed_boost_skips_the_turn_its_holder_entered():
    user, _, _ = facing("speed-boost", None)
    user.entered_turn = 3
    assert hooks.ability(user, "end_of_turn", user, 0, 3, random.Random(0)) is None
    event = hooks.ability(user, "end_of_turn", user, 0, 4, random.Random(0))
    assert event.changes == (Change(0, "사용자", "speed", 1),)


@pytest.mark.parametrize("seed", range(5))
def test_moody_raises_one_stat_two_and_drops_another(seed):
    user, _, _ = facing("moody", None)
    hooks.ability(user, "end_of_turn", user, 0, 1, random.Random(seed))
    assert sorted(stage for stage in user.stages.values() if stage) == [-1, 2]
    assert user.stages["accuracy"] == user.stages["evasion"] == 0


@pytest.mark.parametrize(("ability", "move", "expected"), [
    ("contrary", SWORDS_DANCE, {"attack": -2}), ("simple", SWORDS_DANCE, {"attack": 4}),
    ("contrary", CLOSE_COMBAT, {"defense": 1, "special_defense": 1}),
    ("simple", CLOSE_COMBAT, {"defense": -2, "special_defense": -2}),
])
def test_contrary_and_simple_reshape_the_users_own_changes(ability, move, expected):
    user, foe, arena = facing(ability, None, **WEAK)
    resolve(user, foe, move, arena)
    assert {stat: stage for stat, stage in user.stages.items() if stage} == expected


@pytest.mark.parametrize(("ability", "move", "expected"), [
    ("contrary", GROWL, {"attack": 1}), ("simple", GROWL, {"attack": -2}),
    ("clear-body", GROWL, {}), ("white-smoke", SCREECH, {}), ("full-metal-body", SCREECH, {}),
    ("hyper-cutter", GROWL, {}), ("hyper-cutter", SCREECH, {"defense": -2}),
    ("big-pecks", SCREECH, {}), ("big-pecks", GROWL, {"attack": -1}),
    ("mirror-armor", GROWL, {}),
])
def test_the_holders_ability_meets_a_foes_drop(ability, move, expected):
    user, foe, arena = facing(None, ability)
    resolve(user, foe, move, arena)
    assert {stat: stage for stat, stage in foe.stages.items() if stage} == expected


def test_clear_body_keeps_only_a_foes_drops():
    user, foe, arena = facing("clear-body", None, **WEAK)
    resolve(user, foe, CLOSE_COMBAT, arena)
    assert user.stages["defense"] == -1


def test_mirror_armor_sends_the_drop_back():
    user, foe, arena = facing(None, "mirror-armor")
    resolve(user, foe, GROWL, arena)
    assert user.stages["attack"] == -1 and foe.stages["attack"] == 0


@pytest.mark.parametrize(("ability", "attack_stage", "speed"), [
    ("guard-dog", 1, 0), ("rattled", -1, 1), (None, -1, 0),
])
def test_intimidate_meets_the_holders_ability(ability, attack_stage, speed):
    _, foe, _ = entry("intimidate", ability)
    assert (foe.stages["attack"], foe.stages["speed"]) == (attack_stage, speed)


@pytest.mark.parametrize(("foe_ability", "foe_attack"), [("opportunist", 2), (None, 0)])
def test_opportunist_copies_the_foes_raise(foe_ability, foe_attack):
    user, foe, arena = facing(None, foe_ability)
    resolve(user, foe, SWORDS_DANCE, arena)
    assert user.stages["attack"] == 2 and foe.stages["attack"] == foe_attack


def test_two_opportunists_copy_once():
    user, foe, arena = facing("opportunist", "opportunist")
    resolve(user, foe, SWORDS_DANCE, arena)
    assert user.stages["attack"] == foe.stages["attack"] == 2


@pytest.mark.parametrize(("state", "speed"), [("flinch", 1), ("taunt", 0)])
def test_steadfast_speeds_up_when_it_flinches(state, speed):
    user, foe, arena = facing("steadfast", None)
    user.volatiles[state] = 1
    action = resolve(user, foe, TAUNT if state == "taunt" else TACKLE, arena)
    assert action.blocked == state and user.stages["speed"] == speed


@pytest.mark.parametrize(("make", "line"), [
    (lambda: knock_out("moxie"), "🔵 사용자 [자기과신] 공격↑"),
    (lambda: struck(GROWL, "mirror-armor"), "🔴 상대 [미러아머] → 사용자 공격↓"),
    (lambda: struck(TACKLE, "toxic-debris"), "🔴 상대 [독치장] 상대 쪽에 ☠️독압정 깔림"),
    (lambda: struck(TACKLE, "electromorphosis"), "🔴 상대 [전기로바꾸기] ⚡충전"),
    (lambda: struck(TACKLE, "weak-armor"), "🔴 상대 [깨어진갑옷] 방어↓ 스피드↑↑"),
])
def test_an_ability_acting_mid_turn_reads_in_the_log(make, line):
    user, _ = make()
    [act] = acts(user)
    move = battle.Action(1, 0, "사용자", "상대", "몸통박치기")
    [(_, lines)] = battle_turns(battle.BattleResult(winner=0, turns=1, events=[move, replace(act, turn=1)]))
    assert lines[1:] == [line]


def acts(fighter):
    return [event for event in fighter.arena.log if isinstance(event, AbilityAct)]


def test_an_entry_boost_reads_without_a_self_marker():
    _, _, triggers = entry("intrepid-sword")
    turns = battle_turns(battle.BattleResult(winner=0, turns=1, events=[*triggers, battle.Action(
        1, 0, "사용자", "상대", "몸통박치기")]))
    assert "🔵 사용자 [불요의검] 공격↑" in turns[0][1][0]
