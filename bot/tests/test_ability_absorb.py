import random
from dataclasses import replace

import pytest
from attacks import attack
from status_moves import data_move, resolve
from test_ability_damage import FLAMETHROWER, SWIFT, TACKLE, facing, hit

from ypoke import battle
from ypoke.battle import _Weather
from ypoke.effects import hooks
from ypoke.narration import battle_turns

THUNDERBOLT, SURF, EARTHQUAKE, LEAF_BLADE = attack(85), attack(57), attack(89), attack(348)
HURRICANE, SHADOW_BALL, HYPER_VOICE, QUICK_ATTACK = attack(542), attack(247), attack(304), attack(98)
CLOSE_COMBAT, GIGA_DRAIN = attack(370), attack(202)
THUNDER_WAVE, WILL_O_WISP, SPORE, GROWL = data_move(86), data_move(261), data_move(147), data_move(45)
TAUNT, CONFUSE_RAY, SWORDS_DANCE, TAILWIND = data_move(269), data_move(109), data_move(14), data_move(366)
LEECH_SEED, STRENGTH_SAP, HOWL = data_move(73), data_move(668), data_move(336)


def strike(move, foe_ability, user_ability=None, foe_hp_share=2, **kwargs):
    """The user's move on a foe at 1/`foe_hp_share` HP; the action and the foe."""
    user, foe, arena = facing(user_ability, foe_ability, **kwargs)
    foe.hp = foe.max_hp // foe_hp_share
    return resolve(user, foe, move, arena), user, foe


@pytest.mark.parametrize(("ability", "move", "stat", "stages"), [
    ("lightning-rod", THUNDERBOLT, "special_attack", 1), ("storm-drain", SURF, "special_attack", 1),
    ("motor-drive", THUNDER_WAVE, "speed", 1), ("sap-sipper", SPORE, "attack", 1),
    ("sap-sipper", LEAF_BLADE, "attack", 1), ("well-baked-body", WILL_O_WISP, "defense", 2),
    ("wind-rider", HURRICANE, "attack", 1),
])
def test_an_absorbed_move_fails_and_raises_the_holders_stat(ability, move, stat, stages):
    action, _, foe = strike(move, ability)
    assert action.failed and action.blocked == ability
    assert foe.stages[stat] == stages and foe.status is None and foe.hp == foe.max_hp // 2
    assert [change.kind for change in action.changes] == [stat]


@pytest.mark.parametrize(("ability", "move"), [
    ("volt-absorb", THUNDERBOLT), ("volt-absorb", THUNDER_WAVE), ("water-absorb", SURF),
    ("earth-eater", EARTHQUAKE), ("dry-skin", SURF),
])
def test_an_absorbed_move_heals_the_holder_a_quarter(ability, move):
    action, _, foe = strike(move, ability)
    assert action.blocked == ability and foe.status is None
    assert foe.hp == foe.max_hp // 2 + foe.max_hp // 4
    action, _, foe = strike(move, ability, foe_hp_share=1)
    assert action.blocked == ability and action.changes == ()


@pytest.mark.parametrize(("ability", "move"), [
    ("volt-absorb", SURF), ("lightning-rod", EARTHQUAKE), ("sap-sipper", TACKLE), ("wind-rider", TACKLE),
    ("wind-rider", TAILWIND), ("well-baked-body", SWORDS_DANCE),
])
def test_a_move_the_ability_does_not_absorb_goes_through(ability, move):
    action, _, foe = strike(move, ability)
    assert not action.blocked and all(stage == 0 for stage in foe.stages.values())


def test_flash_fire_absorbs_fire_once_and_powers_up_its_own_fire_moves_until_it_leaves():
    action, user, foe = strike(FLAMETHROWER, "flash-fire")
    assert action.blocked == "flash-fire" and [change.kind for change in action.changes] == ["flash-fire"]
    assert resolve(user, foe, FLAMETHROWER, foe.arena).changes == ()
    assert power(foe, user, FLAMETHROWER) == 1.5 and power(foe, user, SWIFT) == 1.0
    foe.leave()
    assert power(foe, user, FLAMETHROWER) == 1.0
    _, user, foe = strike(SWIFT, "flash-fire")
    assert power(foe, user, FLAMETHROWER) == 1.0


def power(user, foe, move):
    return hooks.ability(user, "modify_power", move, move.power, user, foe, None, default=1.0)


@pytest.mark.parametrize(("weather", "hp_after"), [("rain", 50 + 12), ("sun", 50 - 12), (None, 50)])
def test_dry_skin_heals_in_rain_and_burns_in_sun_at_the_end_of_a_turn(weather, hp_after):
    _, foe, arena = facing(foe_ability="dry-skin")
    foe.max_hp, foe.hp = 100, 50
    arena.weather = _Weather(weather, 5)
    act = hooks.ability(foe, "end_of_turn", foe, 1, 1, random.Random(0))
    assert foe.hp == hp_after and (act is None) == (weather is None)


def test_dry_skin_takes_more_from_fire_moves_only():
    assert hit(FLAMETHROWER, foe_ability="dry-skin") / hit(FLAMETHROWER) == pytest.approx(1.25, rel=0.02)
    assert hit(TACKLE, foe_ability="dry-skin") == hit(TACKLE)


@pytest.mark.parametrize(("ability", "move", "blocked"), [
    ("bulletproof", SHADOW_BALL, True), ("bulletproof", TACKLE, False),
    ("soundproof", HYPER_VOICE, True), ("soundproof", GROWL, True), ("soundproof", HOWL, False),
    ("overcoat", SPORE, True), ("overcoat", THUNDER_WAVE, False),
    ("oblivious", TAUNT, True), ("oblivious", THUNDER_WAVE, False),
    ("good-as-gold", THUNDER_WAVE, True), ("good-as-gold", TAUNT, True), ("good-as-gold", TACKLE, False),
    ("good-as-gold", SWORDS_DANCE, False),
    ("dazzling", QUICK_ATTACK, True), ("queenly-majesty", QUICK_ATTACK, True), ("armor-tail", TACKLE, False),
])
def test_the_ability_blocks_only_its_moves_aimed_at_the_holder(ability, move, blocked):
    action, user, foe = strike(move, ability)
    assert (action.blocked == ability) == blocked
    assert battle._stopped(user, foe, move) == (ability if blocked else "")


def test_own_tempo_inner_focus_and_oblivious_keep_off_their_condition_and_intimidate():
    _, _, foe = strike(CONFUSE_RAY, "own-tempo")
    assert foe.confusion_left == 0
    _, foe, _ = facing(foe_ability="inner-focus")
    assert battle._blocks_ailment(foe, "flinch") and not battle._blocks_ailment(foe, "confusion")
    for ability in ("own-tempo", "inner-focus", "oblivious"):
        scared, foe, arena = facing("intimidate", ability)
        battle._enter_battle((scared, foe), arena.weather, random.Random(0))
        assert foe.stages["attack"] == 0
    _, _, foe = strike(CONFUSE_RAY, None)
    assert foe.confusion_left > 0


def test_overcoat_takes_no_weather_chip():
    _, coated, _ = facing(foe_ability="overcoat")
    _, plain, _ = facing()
    assert not battle._chipped_by(coated, "sandstorm") and battle._chipped_by(plain, "sandstorm")


def test_wonder_guard_lets_only_super_effective_attacks_through():
    _, guarded, _ = facing(foe_ability="wonder-guard")
    assert battle._multiplier(TACKLE, guarded) == 0.0
    assert battle._multiplier(CLOSE_COMBAT, guarded) == 2.0
    action, _, _ = strike(TACKLE, "wonder-guard")
    assert action.multiplier == 0 and action.ability == "wonder-guard"


def test_magic_bounce_sends_a_status_move_back_and_says_so():
    action, user, foe = strike(THUNDER_WAVE, "magic-bounce")
    assert user.status == "paralysis" and foe.status is None and action.blocked == "magic-bounce"
    action, user, foe = strike(THUNDER_WAVE, None)
    assert foe.status == "paralysis" and user.status is None and not action.blocked


def test_liquid_ooze_hurts_whoever_drains_it():
    action, user, _ = strike(GIGA_DRAIN, "liquid-ooze", user_types=("grass",))
    hurt = user.max_hp - user.hp
    assert hurt > 0 and not action.drained
    action, user, _ = strike(GIGA_DRAIN, None, user_types=("grass",))
    assert action.drained
    user, foe, arena = facing(None, "liquid-ooze")
    resolve(user, foe, STRENGTH_SAP, arena)
    assert user.hp < user.max_hp and foe.stages["attack"] == -1


def test_liquid_ooze_turns_leech_seed_against_the_seeder():
    seeder, oozing, _ = facing(None, "liquid-ooze")
    oozing.volatiles["leech-seed"] = True
    seeder.hp = seeder.max_hp // 2
    battle._field(oozing, "volatile_end", oozing, 1, 1, random.Random(0))
    assert seeder.hp < seeder.max_hp // 2


@pytest.mark.parametrize(("foe_ability", "user_types", "moves", "picked"), [
    (None, ("water",), (SURF, TACKLE), 0), ("water-absorb", ("water",), (SURF, TACKLE), 1),
    (None, ("ground",), (EARTHQUAKE, TACKLE), 0), ("levitate", ("ground",), (EARTHQUAKE, TACKLE), 1),
    (None, ("normal",), (THUNDER_WAVE, TACKLE), 0), ("good-as-gold", ("normal",), (THUNDER_WAVE, TACKLE), 1),
    ("magic-bounce", ("normal",), (THUNDER_WAVE, TACKLE), 1),
])
def test_the_move_chooser_steers_around_the_foes_ability(foe_ability, user_types, moves, picked):
    user, _, arena = facing(None, foe_ability, user_types=user_types, speed=1, attack=10, special_attack=10)
    user.combatant = replace(user.combatant, moves=moves)
    user.pp = [move.pp for move in moves]
    assert battle._choose(arena.teams, 0, arena, None) == picked


@pytest.mark.parametrize(("move", "ability", "line"), [
    (THUNDERBOLT, "volt-absorb", "🔵 사용자 › 10만볼트 → [축전]에 막힘 💚HP 회복"),
    (THUNDER_WAVE, "magic-bounce", "🔵 사용자 › 전기자석파 → [매직미러]로 되받아쳤다 ⚡마비"),
    (TAUNT, "magic-bounce", "🔵 사용자 › 도발 → [매직미러]로 되받아쳤다 😤도발"),
])
def test_an_absorbed_move_and_a_bounced_move_read_in_the_log(move, ability, line):
    action, _, _ = strike(move, ability)
    assert battle_turns(battle.BattleResult(winner=0, turns=1, events=[action]))[0][1] == [line]


def test_a_move_bounced_by_magic_coat_reads_in_the_log():
    user, foe, arena = facing(None, None)
    resolve(foe, user, data_move(277), arena)
    action = resolve(user, foe, THUNDER_WAVE, arena)
    [(_, lines)] = battle_turns(battle.BattleResult(winner=0, turns=1, events=[action]))
    assert lines == ["🔵 사용자 › 전기자석파 → 🪞매직코트로 되받아쳤다 ⚡마비"]
