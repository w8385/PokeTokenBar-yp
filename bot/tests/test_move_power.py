import random
from dataclasses import replace

import pytest

from test_battle import TACKLE, actions, mon
from ypoke import abilities, move_power
from ypoke.battle import (
    STRONG_WINDS, Move, SendOut, _act, _best_move, _Fighter, _power, _stats_for, _Team, _unrolled_damage, _Weather,
    _weather_boost, simulate,
)


def attack(move_id, kind="normal", power=60, physical=True, **kwargs):
    return Move(f"move-{move_id}", kind, power, physical=physical, accuracy=100, id=move_id, **kwargs)


LAST_RESPECTS = attack(move_power.LAST_RESPECTS, "ghost", 50)
RAGE_FIST = attack(move_power.RAGE_FIST, "ghost", 50)
KNOCK_OFF = attack(move_power.KNOCK_OFF, "dark", 65)
ACROBATICS = attack(move_power.ACROBATICS, "flying", 55)
WEATHER_BALL = attack(move_power.WEATHER_BALL, "normal", 50, physical=False)
FACADE = attack(move_power.FACADE, "normal", 70)
TRIPLE_AXEL = attack(move_power.TRIPLE_AXEL, "ice", 20, min_hits=3, max_hits=3)
DOUBLE_HIT = Move("더블펀치", "normal", 35, physical=True, accuracy=100, min_hits=2, max_hits=2)
LOWERING_HIT = Move("깨트리기", "normal", 40, physical=True, accuracy=100, stat_changes=(("attack", -1),),
                    stat_chance=100)


def fighter(item=None, pokemon_id=None, ability=None, **kwargs):
    return _Fighter.enter(replace(mon("A", ("normal",), **kwargs), item=item, pokemon_id=pokemon_id, ability=ability))


def power_of(move, user, target, weather=None, multiplier=1.0, hit=None):
    return move_power.power(move, user, target, weather, multiplier, hit)


def _set(**fields):
    def apply(fighter_):
        for key, value in fields.items():
            setattr(fighter_, key, value)
    return apply


def _hp(share):
    def apply(fighter_):
        fighter_.hp = fighter_.max_hp * share // 100
    return apply


def _stages(**stages):
    def apply(fighter_):
        fighter_.stages.update(stages)
    return apply


def _nothing(_fighter):
    return None


# move id, base power, (user setup, target setup) for the boosted branch and the plain branch, boosted power
BRANCHES = [
    (move_power.LAST_RESPECTS, 50, (_set(fallen_allies=2), _nothing), (_nothing, _nothing), 150),
    (move_power.HEX, 65, (_nothing, _set(status="sleep")), (_nothing, _nothing), 130),
    (move_power.FACADE, 70, (_set(status="burn"), _nothing), (_set(status="sleep"), _nothing), 140),
    (move_power.BRINE, 65, (_nothing, _hp(50)), (_nothing, _hp(51)), 130),
    (move_power.VENOSHOCK, 65, (_nothing, _set(status="toxic")), (_nothing, _set(status="burn")), 130),
    (move_power.BARB_BARRAGE, 60, (_nothing, _set(status="poison")), (_nothing, _set(status="paralysis")), 120),
    (move_power.STORED_POWER, 20, (_stages(attack=2, speed=1, defense=-3), _nothing), (_stages(defense=-2), _nothing),
     80),
    (move_power.POWER_TRIP, 20, (_stages(special_attack=6), _nothing), (_nothing, _nothing), 140),
    (move_power.RAGE_FIST, 50, (_set(times_hit=2), _nothing), (_nothing, _nothing), 150),
    (move_power.AVALANCHE, 60, (_set(hit_by_foe=True), _nothing), (_nothing, _nothing), 120),
    (move_power.REVENGE, 60, (_set(hit_by_foe=True), _nothing), (_nothing, _nothing), 120),
    (move_power.PAYBACK, 50, (_nothing, _set(acted=True)), (_nothing, _nothing), 100),
    (move_power.BOLT_BEAK, 85, (_nothing, _nothing), (_nothing, _set(acted=True)), 170),
    (move_power.FISHIOUS_REND, 85, (_nothing, _nothing), (_nothing, _set(acted=True)), 170),
    (move_power.RETALIATE, 70, (_set(ally_fell_last_turn=True), _nothing), (_nothing, _nothing), 140),
    (move_power.STOMPING_TANTRUM, 75, (_set(flopped_last=True), _nothing), (_set(flopped=True), _nothing), 150),
    (move_power.TEMPER_FLARE, 75, (_set(flopped_last=True), _nothing), (_nothing, _nothing), 150),
    (move_power.LASH_OUT, 75, (_set(lowered=True), _nothing), (_nothing, _nothing), 150),
    (move_power.ERUPTION, 150, (_nothing, _nothing), (_hp(50), _nothing), 150),
    (move_power.WATER_SPOUT, 150, (_nothing, _nothing), (_hp(20), _nothing), 150),
    (move_power.DRAGON_ENERGY, 150, (_nothing, _nothing), (_hp(1), _nothing), 150),
]


@pytest.mark.parametrize("move_id, base, boosted_setup, plain_setup, boosted", BRANCHES,
                         ids=[str(row[0]) for row in BRANCHES])
def test_a_variable_power_move_scales_only_in_its_own_battle_state(move_id, base, boosted_setup, plain_setup, boosted):
    move = attack(move_id, power=base)
    results = []
    for setup in (boosted_setup, plain_setup):
        user, target = fighter(), fighter()
        setup[0](user)
        setup[1](target)
        results.append(power_of(move, user, target))
    plain = base if move_id not in (move_power.ERUPTION, move_power.WATER_SPOUT, move_power.DRAGON_ENERGY) else None
    assert results[0] == boosted
    if plain is not None:
        assert results[1] == plain


def test_hp_moves_scale_with_the_users_hp_share_and_never_drop_below_1():
    user, target = fighter(), fighter()
    for move_id in (move_power.ERUPTION, move_power.WATER_SPOUT, move_power.DRAGON_ENERGY):
        move = attack(move_id, power=150)
        user.hp = user.max_hp
        assert power_of(move, user, target) == 150
        user.hp = user.max_hp // 2
        assert power_of(move, user, target) == 150 * user.hp // user.max_hp < 150
        user.hp = 1
        assert power_of(move, user, target) == 1


def test_a_move_not_in_the_table_keeps_its_listed_power():
    user, target = fighter(), fighter()
    user.fallen_allies, user.status, target.status, user.hit_by_foe = 3, "burn", "poison", True
    assert power_of(TACKLE, user, target, "sun", 2.0, 0) == TACKLE.power
    assert power_of(replace(TACKLE, id=33), user, target, "rain", 2.0) == TACKLE.power


def test_rage_fist_stops_at_350():
    user = fighter()
    user.times_hit = 10
    assert power_of(RAGE_FIST, user, fighter()) == 350


def test_collision_course_and_electro_drift_get_a_third_more_only_on_a_super_effective_hit():
    user, target = fighter(), fighter()
    for move_id in (move_power.COLLISION_COURSE, move_power.ELECTRO_DRIFT):
        move = attack(move_id, power=100)
        assert power_of(move, user, target, multiplier=2.0) == pytest.approx(100 * 5461 / 4096)
        assert power_of(move, user, target, multiplier=1.0) == 100


@pytest.mark.parametrize("weather, kind", [("sun", "fire"), ("rain", "water"), ("sandstorm", "rock"),
                                           ("hail", "ice"), ("snow", "ice")])
def test_weather_ball_takes_the_weathers_type_and_doubles(weather, kind):
    user, target = fighter(), fighter()
    typed = move_power.typed(WEATHER_BALL, weather)
    assert typed.type == kind
    assert power_of(typed, user, target, weather) == 100


@pytest.mark.parametrize("weather", [None, STRONG_WINDS])
def test_weather_ball_stays_a_50_power_normal_move_without_a_weather_it_knows(weather):
    user, target = fighter(), fighter()
    assert move_power.typed(WEATHER_BALL, weather) is WEATHER_BALL
    assert power_of(WEATHER_BALL, user, target, weather) == 50


def test_weather_ball_in_rain_hits_a_fire_type_as_a_water_move():
    user = _Fighter.enter(mon("A", ("normal",), moves=(WEATHER_BALL,)))
    target = _Fighter.enter(mon("B", ("fire",), hp=255, defense=255, special_defense=255))
    rainy = _act(1, 0, (user, target), 0, _Weather("rain", 5), random.Random(0))
    clear = _act(1, 0, (user, target), 0, _Weather(), random.Random(0))
    assert (rainy.multiplier, clear.multiplier) == (2.0, 1.0)


def test_the_move_choice_scores_weather_ball_with_the_weathers_type():
    giga_impact = attack(416, "normal", 120)
    user = _Fighter.enter(mon("A", ("normal",), moves=(giga_impact, WEATHER_BALL)))
    target = _Fighter.enter(mon("B", ("fire",)))
    assert _best_move(user, target, "rain") == 1
    assert _best_move(user, target, None) == 0


@pytest.mark.parametrize("move_id, base", [(move_power.SOLAR_BEAM, 120), (move_power.SOLAR_BLADE, 125)])
def test_solar_beam_is_halved_in_rain_sand_hail_and_snow(move_id, base):
    move, user, target = attack(move_id, "grass", base), fighter(), fighter()
    assert [power_of(move, user, target, weather) for weather in ("rain", "sandstorm", "hail", "snow")] == [base / 2] * 4
    assert [power_of(move, user, target, weather) for weather in (None, "sun", STRONG_WINDS)] == [base] * 3


def test_hydro_steam_is_boosted_in_sun_while_other_water_moves_are_weakened():
    hydro_steam = attack(move_power.HYDRO_STEAM, "water", 80, physical=False)
    surf = attack(57, "water", 90, physical=False)
    assert _weather_boost(hydro_steam, "sun") == 1.5
    assert _weather_boost(surf, "sun") == 0.5
    assert _weather_boost(hydro_steam, "rain") == 1.5
    assert _weather_boost(hydro_steam, None) == 1.0


def test_facade_ignores_the_burn_attack_cut():
    burned, paralyzed, target = fighter(), fighter(), fighter()
    burned.status, paralyzed.status = "burn", "paralysis"
    assert _stats_for(burned, target, FACADE)[0] == burned.stat("attack")
    assert _unrolled_damage(burned, target, FACADE, 1.0, None) == _unrolled_damage(paralyzed, target, FACADE, 1.0, None)
    assert _unrolled_damage(burned, target, TACKLE, 1.0, None) < _unrolled_damage(paralyzed, target, TACKLE, 1.0, None)


def test_triple_axel_hits_harder_on_each_hit_and_scores_the_mean_hit():
    user, target = fighter(), fighter()
    assert [power_of(TRIPLE_AXEL, user, target, hit=hit) for hit in range(3)] == [20, 40, 60]
    assert power_of(TRIPLE_AXEL, user, target) == 40
    triple_kick = attack(move_power.TRIPLE_KICK, "fighting", 10, min_hits=3, max_hits=3)
    assert [power_of(triple_kick, user, target, hit=hit) for hit in range(3)] == [10, 20, 30]


def test_technician_applies_to_the_computed_power():
    user, target = fighter(ability="technician"), fighter()
    assert _power(user, target, LAST_RESPECTS, None, 1.0) == 50 * abilities.TECHNICIAN_BOOST
    user.fallen_allies = 1
    assert _power(user, target, LAST_RESPECTS, None, 1.0) == 100


@pytest.fixture
def used(monkeypatch):
    """The power each landed hit had in the battle, as (move id, user name, power)."""
    seen = []
    real = move_power.power

    def spy(move, user, target, weather, multiplier, hit=None):
        value = real(move, user, target, weather, multiplier, hit)
        if hit is not None:
            seen.append((move.id, user.combatant.name, value))
        return value

    monkeypatch.setattr(move_power, "power", spy)
    return seen


@pytest.mark.parametrize("fainted, expected", [(0, 50), (1, 100), (2, 150)])
def test_last_respects_adds_50_for_each_fainted_teammate(used, fainted, expected):
    fodder = [mon(f"F{index}", ("normal",), hp=1, speed=10) for index in range(fainted)]
    user = mon("A", ("normal",), moves=(LAST_RESPECTS,), speed=10)
    foe = mon("B", ("psychic",), moves=(TACKLE,), hp=255, defense=255, attack=200, speed=200)
    result = simulate(([*fodder, user], foe), seed=0)
    assert sum(isinstance(event, SendOut) and event.side == 0 for event in result.events) == fainted
    assert set(_powers(used, move_power.LAST_RESPECTS)) == {expected}


def test_last_respects_does_not_count_the_foes_fainted_members(used):
    user = mon("A", ("normal",), moves=(LAST_RESPECTS,), attack=200, speed=200)
    fragile = mon("X", ("psychic",), moves=(TACKLE,), hp=1, speed=10)
    wall = mon("Y", ("psychic",), moves=(TACKLE,), hp=255, defense=255, speed=10)
    result = simulate((user, [fragile, wall]), seed=0)
    assert any(isinstance(event, SendOut) and event.side == 1 for event in result.events)
    assert set(_powers(used, move_power.LAST_RESPECTS)) == {50}


def test_retaliate_doubles_only_on_the_turn_after_a_teammate_fainted():
    retaliate = attack(move_power.RETALIATE, power=70)
    team = _Team((mon("F", ("normal",)), mon("A", ("normal",), moves=(retaliate,))))
    target = fighter()
    team.start_turn()
    team.active.hp = 0
    team.send_next()
    team.start_turn()
    assert power_of(retaliate, team.active, target) == 140
    team.start_turn()
    assert power_of(retaliate, team.active, target) == 70


def test_supreme_overlord_adds_a_tenth_per_fainted_teammate_up_to_half():
    def multiplier(fallen):
        return abilities.power_multiplier("supreme-overlord", "dark", 80, False, None, fallen)

    assert [multiplier(fallen) for fallen in (0, 2, 5, 6)] == pytest.approx([1.0, 1.2, 1.5, 1.5])
    assert abilities.power_multiplier(None, "dark", 80, False, None, 5) == 1.0


def test_supreme_overlord_counts_its_own_sides_faints_only():
    holder = replace(mon("A", ("dark",), moves=(TACKLE,)), ability="supreme-overlord")
    team = _Team((mon("F1", ("normal",)), mon("F2", ("normal",)), holder))
    foes = _Team((mon("X", ("normal",)), mon("Y", ("normal",))))
    for _ in range(2):
        team.active.hp = 0
        team.send_next()
    foes.active.hp = 0
    foes.send_next()
    team.start_turn()
    foes.start_turn()
    assert _power(team.active, foes.active, TACKLE, None, 1.0) == pytest.approx(TACKLE.power * 1.2)


def test_rage_fist_counts_every_hit_taken_and_keeps_the_count_after_switching_out():
    user, foe = fighter(), _Fighter.enter(mon("B", ("normal",), moves=(DOUBLE_HIT,)))
    _act(1, 1, (user, foe), 0, _Weather(), random.Random(0))
    assert user.times_hit == 2
    user.leave()
    assert power_of(RAGE_FIST, user, foe) == 150


@pytest.mark.parametrize("move_id", [move_power.REVENGE, move_power.AVALANCHE])
@pytest.mark.parametrize("user_speed, expected", [(10, 120), (200, 60)])
def test_revenge_doubles_when_the_foe_hit_the_user_first_this_turn(used, move_id, user_speed, expected):
    user = mon("A", ("normal",), moves=(attack(move_id),), speed=user_speed)
    foe = mon("B", ("normal",), moves=(TACKLE,), hp=255, defense=255, speed=100)
    simulate((user, foe), seed=0)
    assert _powers(used, move_id)[0] == expected


@pytest.mark.parametrize("move_id, base, slower, faster", [
    (move_power.PAYBACK, 50, 100, 50), (move_power.BOLT_BEAK, 85, 85, 170), (move_power.FISHIOUS_REND, 85, 85, 170),
])
def test_move_order_moves_follow_who_moved_first(used, move_id, base, slower, faster):
    for user_speed, expected in ((10, slower), (200, faster)):
        used.clear()
        user = mon("A", ("normal",), moves=(attack(move_id, power=base),), speed=user_speed)
        foe = mon("B", ("normal",), moves=(TACKLE,), hp=255, defense=255, speed=100)
        simulate((user, foe), seed=0)
        assert _powers(used, move_id)[0] == expected


@pytest.mark.parametrize("user_speed, expected", [(10, 150), (200, 75)])
def test_lash_out_doubles_after_a_stat_drop_this_turn(used, user_speed, expected):
    user = mon("A", ("normal",), moves=(attack(move_power.LASH_OUT, "dark", 75),), speed=user_speed)
    foe = mon("B", ("normal",), moves=(LOWERING_HIT,), hp=255, defense=255, speed=100)
    simulate((user, foe), seed=0)
    assert _powers(used, move_power.LASH_OUT)[0] == expected


def test_lash_out_ignores_an_intimidate_from_before_the_turn(used):
    user = mon("A", ("normal",), moves=(attack(move_power.LASH_OUT, "dark", 75),), speed=200)
    foe = replace(mon("B", ("normal",), moves=(TACKLE,), hp=255, defense=255, speed=100), ability="intimidate")
    simulate((user, foe), seed=0)
    assert _powers(used, move_power.LASH_OUT)[0] == 75


@pytest.mark.parametrize("move_id", [move_power.STOMPING_TANTRUM, move_power.TEMPER_FLARE])
def test_stomping_tantrum_doubles_right_after_the_users_move_missed(used, move_id):
    move = replace(attack(move_id, power=75), accuracy=50)
    user = mon("A", ("normal",), moves=(move,), hp=255, defense=255, speed=200)
    foe = mon("B", ("normal",), moves=(TACKLE,), hp=255, defense=255, speed=10)
    result = simulate((user, foe), seed=0)
    mine = [action for action in actions(result) if action.side == 0]
    expected = [150 if index and mine[index - 1].missed else 75 for index, action in enumerate(mine)
                if action.move == move.name and not action.missed]
    assert _powers(used, move_id) == expected
    assert {75, 150} <= set(expected)


def test_knock_off_boosts_against_a_held_item_and_takes_it(used):
    user = _Fighter.enter(mon("A", ("normal",), moves=(KNOCK_OFF,)))
    target = fighter(item="leftovers", hp=255, defense=255)
    for turn in (1, 2):
        _act(turn, 0, (user, target), 0, _Weather(), random.Random(turn))
    assert _powers(used, move_power.KNOCK_OFF) == [65 * 1.5, 65]
    assert target.item is None and target.item_lost


def test_knock_off_ends_the_choice_lock_with_the_item():
    user = _Fighter.enter(mon("A", ("normal",), moves=(KNOCK_OFF,)))
    strong = attack(416, "normal", 120)
    holder = _Fighter.enter(replace(mon("B", ("normal",), moves=(TACKLE, strong), hp=255, defense=255),
                                    item="choice-band"))
    _act(1, 1, (user, holder), 0, _Weather(), random.Random(0))
    assert holder.locked == 0 and _best_move(holder, user, None) == 0
    _act(1, 0, (user, holder), 0, _Weather(), random.Random(0))
    assert holder.locked is None and _best_move(holder, user, None) == 1


def test_a_member_that_comes_back_in_has_not_moved_this_turn():
    payback = attack(move_power.PAYBACK, "dark", 50)
    bolt_beak = attack(move_power.BOLT_BEAK, "flying", 85)
    user, returning = fighter(), fighter()
    returning.acted = True
    returning.leave()
    assert (power_of(payback, user, returning), power_of(bolt_beak, user, returning)) == (50, 170)


def test_knock_off_takes_an_item_the_battle_does_not_know(used):
    user = _Fighter.enter(mon("A", ("normal",), moves=(KNOCK_OFF,)))
    target = fighter(item="booster-energy", hp=255, defense=255)
    assert power_of(ACROBATICS, target, user) == 55
    for turn in (1, 2):
        _act(turn, 0, (user, target), 0, _Weather(), random.Random(turn))
    assert _powers(used, move_power.KNOCK_OFF) == [65 * 1.5, 65]
    assert power_of(ACROBATICS, target, user) == 110


def test_knock_off_leaves_a_mega_stone_on_its_own_pokemon(used):
    user = _Fighter.enter(mon("A", ("normal",), moves=(KNOCK_OFF,)))
    target = fighter(item="charizardite-x", pokemon_id=6, hp=255, defense=255)
    _act(1, 0, (user, target), 0, _Weather(), random.Random(0))
    assert _powers(used, move_power.KNOCK_OFF) == [65]
    assert not target.item_lost
    assert move_power.holds_removable_item(fighter(item="charizardite-x", pokemon_id=3))


def test_acrobatics_doubles_once_the_users_item_is_used_up():
    holder, target = fighter(item="sitrus-berry"), fighter()
    assert power_of(ACROBATICS, holder, target) == 55
    holder.item = None
    assert power_of(ACROBATICS, holder, target) == 110
    assert power_of(ACROBATICS, fighter(), target) == 110


def test_kowtow_cleave_with_no_listed_accuracy_never_misses():
    kowtow_cleave = Move("도각참", "dark", 85, physical=True, accuracy=None, id=869)
    user = _Fighter.enter(mon("A", ("dark",), moves=(kowtow_cleave,)))
    for seed in range(200):
        target = _Fighter.enter(replace(mon("B", ("normal",), hp=255, defense=255), item="bright-powder"))
        assert not _act(1, 0, (user, target), 0, _Weather(), random.Random(seed)).missed


def _powers(used, move_id, name="A"):
    return [value for seen_id, seen_name, value in used if (seen_id, seen_name) == (move_id, name)]
