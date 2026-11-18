import random
from dataclasses import replace

import pytest
from attacks import attack
from test_battle import mon

from ypoke import battle, move_power
from ypoke.battle import _Arena, _Team

THUNDER_PUNCH, TACKLE, BITE, WATER_PULSE, SWIFT = attack(9), attack(33), attack(44), attack(352), attack(129)
HYPER_VOICE, FLAMETHROWER, DOUBLE_EDGE, IRON_HEAD = attack(304), attack(53), attack(38), attack(442)
EARTHQUAKE, BULLET_SEED, HEAVY_SLAM, DARK_PULSE = attack(89), attack(331), attack(484), attack(399)
MOONBLAST, LEAF_BLADE, CLOSE_COMBAT, ICE_BEAM = attack(585), attack(348), attack(370), attack(58)
STRONG = {"attack": 200, "special_attack": 200}


def facing(user_ability=None, foe_ability=None, user_types=("normal",), foe_types=("normal",), **user_stats):
    arena = _Arena()
    user = replace(mon("사용자", user_types, **{**STRONG, **user_stats}), ability=user_ability)
    foe = replace(mon("상대", foe_types, defense=20, special_defense=20), ability=foe_ability)
    teams = (_Team((user,), arena=arena), _Team((foe,), arena=arena, side=1))
    arena.teams = teams
    return teams[0].active, teams[1].active, arena


def hit(move, user_ability=None, foe_ability=None, prep=None, weather=None, **kwargs):
    user, foe, arena = facing(user_ability, foe_ability, **kwargs)
    if prep:
        prep(user, foe, arena)
    typed = move_power.typed(move, weather, user)
    return battle._unrolled_damage(user, foe, typed, battle._multiplier(typed, foe, weather), weather)


def burned(user, foe, arena):
    user.status = "burn"


def poisoned(user, foe, arena):
    user.status = "poison"


def foe_acted(user, foe, arena):
    foe.acted = True


def foe_just_in(user, foe, arena):
    arena.turn = foe.entered_turn = 3


def half_hp(user, foe, arena):
    user.hp = user.max_hp // 2


def foe_half_hp(user, foe, arena):
    foe.hp = foe.max_hp // 2


def late(user, foe, arena):
    arena.turn = 5


@pytest.mark.parametrize(("ability", "move", "kwargs", "expected"), [
    ("iron-fist", THUNDER_PUNCH, {}, 1.2), ("iron-fist", TACKLE, {}, 1.0),
    ("strong-jaw", BITE, {}, 1.5), ("mega-launcher", WATER_PULSE, {}, 1.5), ("mega-launcher", SWIFT, {}, 1.0),
    ("sharpness", LEAF_BLADE, {}, 1.5), ("tough-claws", TACKLE, {}, 1.3), ("tough-claws", SWIFT, {}, 1.0),
    ("punk-rock", HYPER_VOICE, {}, 1.3),
    ("steelworker", IRON_HEAD, {}, 1.5), ("steelworker", TACKLE, {}, 1.0), ("water-bubble", WATER_PULSE, {}, 2.0),
    ("pixilate", TACKLE, {}, 1.2 / 1.5), ("pixilate", MOONBLAST, {}, 1.0),
    ("normalize", WATER_PULSE, {"user_types": ("water",)}, 1.2 / 1.5),
    ("liquid-voice", HYPER_VOICE, {"user_types": ("water",)}, 1.5), ("liquid-voice", SWIFT, {}, 1.0),
    ("reckless", DOUBLE_EDGE, {}, 1.2), ("reckless", TACKLE, {}, 1.0),
    ("sheer-force", IRON_HEAD, {}, 5325 / 4096), ("sheer-force", EARTHQUAKE, {}, 1.0),
    ("analytic", TACKLE, {"prep": foe_acted}, 5325 / 4096), ("analytic", TACKLE, {}, 1.0),
    ("stakeout", TACKLE, {"prep": foe_just_in}, 2.0), ("stakeout", TACKLE, {}, 1.0),
    ("flare-boost", SWIFT, {"prep": burned}, 1.5), ("flare-boost", SWIFT, {}, 1.0),
    ("toxic-boost", TACKLE, {"prep": poisoned}, 1.5), ("toxic-boost", SWIFT, {"prep": poisoned}, 1.0),
    ("hustle", TACKLE, {}, 1.5), ("hustle", SWIFT, {}, 1.0),
    ("marvel-scale", TACKLE, {}, 1.0),
    ("solar-power", SWIFT, {"weather": "sun"}, 1.5), ("solar-power", SWIFT, {}, 1.0),
    ("defeatist", TACKLE, {"prep": half_hp}, 0.5), ("defeatist", TACKLE, {}, 1.0),
    ("slow-start", TACKLE, {}, 0.5), ("slow-start", TACKLE, {"prep": late}, 1.0),
    ("tinted-lens", EARTHQUAKE, {"foe_types": ("grass",)}, 2.0), ("tinted-lens", TACKLE, {}, 1.0),
    ("neuroforce", CLOSE_COMBAT, {}, 1.25), ("neuroforce", SWIFT, {}, 1.0),
    ("dark-aura", DARK_PULSE, {}, 5448 / 4096), ("dark-aura", SWIFT, {}, 1.0),
    ("dark-aura", DARK_PULSE, {"foe_ability": "aura-break"}, 3072 / 4096),
    ("tablets-of-ruin", TACKLE, {}, 1.0), ("vessel-of-ruin", SWIFT, {}, 1.0),
    ("sword-of-ruin", TACKLE, {}, 1 / 0.75), ("beads-of-ruin", SWIFT, {}, 1 / 0.75), ("beads-of-ruin", TACKLE, {}, 1.0),
])
def test_the_users_ability_scales_the_damage_only_where_it_applies(ability, move, kwargs, expected):
    plain = {key: value for key, value in kwargs.items() if key != "foe_ability"}
    if move is CLOSE_COMBAT:
        plain["foe_types"] = ("normal",)
    assert hit(move, ability, **kwargs) / hit(move, **plain) == pytest.approx(expected, rel=0.02)


@pytest.mark.parametrize(("ability", "move", "kwargs", "expected"), [
    ("filter", CLOSE_COMBAT, {}, 0.75), ("filter", TACKLE, {}, 1.0),
    ("multiscale", TACKLE, {}, 0.5), ("multiscale", TACKLE, {"prep": foe_half_hp}, 1.0),
    ("fluffy", TACKLE, {}, 0.5), ("fluffy", FLAMETHROWER, {}, 2.0), ("fluffy", SWIFT, {}, 1.0),
    ("ice-scales", SWIFT, {}, 0.5), ("ice-scales", TACKLE, {}, 1.0),
    ("heatproof", FLAMETHROWER, {}, 0.5), ("purifying-salt", TACKLE, {}, 1.0),
    ("punk-rock", HYPER_VOICE, {}, 0.5), ("water-bubble", FLAMETHROWER, {}, 0.5),
    ("fur-coat", TACKLE, {}, 0.5), ("fur-coat", SWIFT, {}, 1.0),
    ("tablets-of-ruin", TACKLE, {}, 0.75), ("tablets-of-ruin", SWIFT, {}, 1.0),
])
def test_the_targets_ability_scales_the_damage_only_where_it_applies(ability, move, kwargs, expected):
    types = {"foe_types": ("normal",)} if move is not CLOSE_COMBAT else {}
    assert hit(move, foe_ability=ability, **kwargs, **types) / hit(move, **kwargs, **types) == pytest.approx(
        expected, rel=0.02)


def test_the_foes_ruin_lowers_the_holders_stat_and_a_ruin_holder_keeps_its_own():
    user, _, _ = facing("tablets-of-ruin", "tablets-of-ruin")
    plain_user, _, _ = facing()
    assert user.stat("attack") == plain_user.stat("attack")
    ruined, _, _ = facing(None, "tablets-of-ruin")
    assert ruined.stat("attack") == pytest.approx(plain_user.stat("attack") * 0.75, abs=1)


def test_the_status_stat_doubles_speed_back_from_paralysis_only_for_quick_feet():
    feet, _, _ = facing("quick-feet")
    calm = feet.stat("speed")
    feet.status = "paralysis"
    assert feet.stat("speed") == pytest.approx(calm * 1.5, abs=1)
    plain, _, _ = facing()
    plain.status = "paralysis"
    assert plain.stat("speed") < calm


def test_sheer_force_and_shield_dust_drop_added_effects_and_serene_grace_doubles_them():
    user, foe, _ = facing("sheer-force")
    assert battle._chance_scale(IRON_HEAD, user, foe) == 0.0
    assert battle._chance_scale(EARTHQUAKE, user, foe) == 1.0
    graced, foe, _ = facing("serene-grace")
    assert battle._chance_scale(IRON_HEAD, graced, foe) == 2.0
    plain, dusty, _ = facing(None, "shield-dust")
    assert battle._chance_scale(IRON_HEAD, plain, dusty) == 0.0
    plain, foe, _ = facing()
    assert battle._chance_scale(IRON_HEAD, plain, foe) == 1.0


def test_parental_bond_hits_a_single_hit_move_twice_and_skill_link_maxes_a_multi_hit_move():
    bond, _, _ = facing("parental-bond")
    assert battle._hit_count(TACKLE, bond, random.Random(0)) == 2
    assert battle._expected_hits(TACKLE, bond, 100) == 1.25
    linked, _, _ = facing("skill-link")
    plain, _, _ = facing()
    assert {battle._hit_count(BULLET_SEED, linked, random.Random(seed)) for seed in range(20)} == {5}
    assert battle._hit_count(TACKLE, linked, random.Random(0)) == 1
    assert len({battle._hit_count(BULLET_SEED, plain, random.Random(seed)) for seed in range(20)}) > 1


def test_the_second_parental_bond_hit_has_a_quarter_of_the_power():
    user, foe, _ = facing("parental-bond")
    first = battle._power(user, foe, TACKLE, None, 1.0, 0)
    assert battle._power(user, foe, TACKLE, None, 1.0, 1) == first * 0.25
    plain, foe, _ = facing()
    assert battle._power(plain, foe, TACKLE, None, 1.0, 1) == battle._power(plain, foe, TACKLE, None, 1.0, 0)


def test_heavy_and_light_metal_scale_the_weight_heavy_slam_reads():
    heavy, foe, _ = facing("heavy-metal")
    heavy.combatant = replace(heavy.combatant, weight=1000)
    foe.combatant = replace(foe.combatant, weight=1000)
    light, _, _ = facing("light-metal")
    light.combatant = replace(heavy.combatant, ability="light-metal")
    assert (battle._weight(heavy), battle._weight(light), battle._weight(foe)) == (2000, 500, 1000)
    assert battle._power(heavy, foe, HEAVY_SLAM, None, 1.0) > battle._power(foe, heavy, HEAVY_SLAM, None, 1.0)


def test_rock_head_takes_no_recoil_and_long_reach_makes_no_contact():
    rocky, _, _ = facing("rock-head")
    plain, _, _ = facing()
    assert battle._recoil_free(rocky) and not battle._recoil_free(plain)
    reach, _, _ = facing("long-reach")
    assert not battle.makes_contact(reach, TACKLE) and battle.makes_contact(plain, TACKLE)


def test_unseen_fist_strikes_through_protect_with_contact_moves_only():
    from ypoke.effects import protection

    _, foe, _ = facing("unseen-fist")
    assert protection.breaks_guard(TACKLE, foe)
    assert not protection.breaks_guard(SWIFT, foe)
    _, foe, _ = facing()
    assert not protection.breaks_guard(TACKLE, foe)


def test_gorilla_tactics_locks_its_holder_into_one_move():
    from ypoke.effects import hooks

    tactician, _, _ = facing("gorilla-tactics")
    plain, _, _ = facing()
    assert hooks.ability(tactician, "locks_move", default=False)
    assert not hooks.ability(plain, "locks_move", default=False)


def test_solar_power_chips_an_eighth_in_sun_only():
    from ypoke.effects import hooks

    user, _, arena = facing("solar-power")
    assert hooks.ability(user, "end_of_turn", user, 0, 1, random.Random(0)) is None
    arena.weather = battle._Weather("sun", 5)
    act = hooks.ability(user, "end_of_turn", user, 0, 1, random.Random(0))
    assert (act.ability, user.max_hp - user.hp) == ("solar-power", user.max_hp // 8)


def test_heatproof_halves_burn_chip_but_not_poison():
    from ypoke.effects import hooks

    user, _, _ = facing("heatproof")
    assert hooks.ability(user, "modify_status_damage", 16, "burn", default=16) == 8
    assert hooks.ability(user, "modify_status_damage", 16, "poison", default=16) == 16
