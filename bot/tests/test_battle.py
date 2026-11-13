import random
from dataclasses import replace

import pytest

from ypoke.battle import (
    NATURE_MODIFIERS, STRUGGLE, TURN_LIMIT, WEATHER_TURNS, Action, BaseStats, Change, Combatant, Move,
    StatusDamage, WeatherDamage, WeatherEnd, _act, _best_move, _damage, _Fighter, _stats_for, _Weather, _weather_upkeep, simulate,
)
from ypoke.type_chart import effectiveness

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)
FLAMETHROWER = Move("화염방사", "fire", 90, physical=False, accuracy=100)
SURF = Move("파도타기", "water", 90, physical=False, accuracy=100)
FIRE_BLAST = Move("불대문자", "fire", 120, physical=False, accuracy=50)
HAMMER_ARM = Move("암해머", "fighting", 100, physical=True, accuracy=90)


def mon(name, types, level=50, moves=(TACKLE,), hp=80, attack=80, defense=80, special_attack=80,
        special_defense=80, speed=80):
    return Combatant(
        name=name,
        level=level,
        types=tuple(types),
        base=BaseStats(hp, attack, defense, special_attack, special_defense, speed),
        ivs=IVS,
        moves=tuple(moves),
    )


def actions(result):
    return [event for event in result.events if isinstance(event, Action)]


def first_action(attacker, defender, seed=0):
    return actions(simulate((attacker, defender), seed))[0]


def test_effectiveness_multiplies_dual_types():
    assert effectiveness("electric", ("water", "flying")) == 4
    assert effectiveness("ground", ("electric", "flying")) == 0
    assert effectiveness("fire", ("grass",)) == 2
    assert effectiveness("normal", ("psychic",)) == 1


def test_same_seed_replays_the_same_battle():
    sides = (mon("A", ["fire"], moves=[FLAMETHROWER]), mon("B", ["water"], moves=[SURF]))
    assert simulate(sides, seed=42) == simulate(sides, seed=42)


def test_type_advantage_and_level_decide_the_winner():
    for seed in range(20):
        result = simulate((mon("물", ["water"], level=60, moves=[SURF]), mon("불", ["fire"], level=40, moves=[EMBER])), seed)
        assert result.winner == 0
        assert actions(result)[-1].knockout


def test_opponent_side_can_win():
    result = simulate((mon("약", ["bug"], level=5), mon("강", ["fire"], level=90, moves=[FLAMETHROWER])), seed=1)
    assert result.winner == 1
    last = actions(result)[-1]
    assert (last.attacker, last.move, last.multiplier, last.knockout) == ("강", "화염방사", 2.0, True)


def test_shedinja_style_base_hp_one_has_one_hp():
    assert _Fighter.enter(mon("껍질몬", ["bug", "ghost"], hp=1)).max_hp == 1


def test_stats_follow_the_mainline_formula():
    fighter = _Fighter.enter(mon("피카츄", ["electric"], level=50, hp=35, speed=90))
    assert fighter.max_hp == (2 * 35 + 15) * 50 // 100 + 50 + 10
    assert fighter.stat("speed") == (2 * 90 + 15) * 50 // 100 + 5


def test_picks_the_move_with_the_highest_expected_damage():
    attacker = mon("리자몽", ["fire"], moves=[TACKLE, EMBER, FLAMETHROWER, SURF], speed=200)
    assert first_action(attacker, mon("이상해씨", ["grass"])).move == "화염방사"
    assert first_action(attacker, mon("바위", ["rock"])).move == "파도타기"


def test_expected_damage_weighs_accuracy_and_the_matching_stat():
    wild_shot = mon("A", ["fire"], moves=[FIRE_BLAST, FLAMETHROWER], speed=200)
    assert first_action(wild_shot, mon("B", ["grass"])).move == "화염방사"
    strong_body = mon("C", ["normal"], moves=[FLAMETHROWER, HAMMER_ARM], speed=200, attack=150, special_attack=40)
    assert first_action(strong_body, mon("D", ["normal"])).move == "암해머"


def test_a_move_can_miss_and_does_no_damage():
    attacker = mon("A", ["fire"], moves=[Move("헛방", "fire", 200, physical=False, accuracy=1)], speed=200)
    action = first_action(attacker, mon("B", ["normal"], level=5))
    assert (action.move, action.missed, action.knockout, action.defender_hp) == ("헛방", True, False, 100)


def test_an_immune_target_takes_nothing():
    action = first_action(mon("노말", ["normal"], level=80, speed=200), mon("유령", ["ghost"], level=5))
    assert (action.move, action.multiplier, action.defender_hp) == ("몸통박치기", 0, 100)


def test_running_out_of_pp_falls_back_to_struggle_with_recoil():
    attacker = mon("A", ["normal"], moves=[replace(TACKLE, pp=1)], speed=200, hp=200, defense=200, special_defense=200)
    result = simulate((attacker, mon("B", ["normal"], moves=[], hp=200, defense=200)), seed=0)
    used = [action.move for action in actions(result) if action.side == 0]
    assert used[:2] == ["몸통박치기", STRUGGLE.name]
    assert all(action.recoil for action in actions(result)[1:] if action.side == 0)


def test_no_moves_means_struggle_and_struggle_hits_ghosts():
    action = first_action(mon("A", ["normal"], moves=[], speed=200), mon("유령", ["ghost"]))
    assert (action.move, action.multiplier, action.recoil) == ("발버둥", 1.0, True)
    assert action.defender_hp < 100


def test_a_critical_stage_of_three_always_crits():
    sure_crit = mon("A", ["normal"], moves=[replace(TACKLE, crit_stage=3)], speed=200)
    assert all(first_action(sure_crit, mon("B", ["normal"], hp=255), seed).critical for seed in range(10))


def test_burn_halves_physical_damage_and_hurts_each_turn():
    flame = replace(TACKLE, name="불꽃엄니", type="fire", ailment="burn", ailment_chance=100)
    result = simulate((mon("A", ["fire"], moves=[flame], speed=200, attack=10),
                       mon("B", ["normal"], hp=200, defense=200)), seed=0)
    assert actions(result)[0].changes == (Change(1, "B", "burn"),)
    burns = [event for event in result.events if isinstance(event, StatusDamage)]
    assert burns and burns[0] == StatusDamage(1, 1, "B", burns[0].hp, False)
    fighter = _Fighter.enter(mon("B", ["normal"]))
    plain = _stats_for(fighter, fighter, physical=True)[0]
    fighter.status = "burn"
    assert _stats_for(fighter, fighter, physical=True)[0] == plain / 2
    assert _stats_for(fighter, fighter, physical=False)[0] == fighter.stat("special_attack")


def test_type_immunity_blocks_the_ailment():
    flame = replace(TACKLE, type="fire", ailment="burn", ailment_chance=100)
    assert first_action(mon("A", ["fire"], moves=[flame], speed=200), mon("불", ["fire"], hp=200)).changes == ()


def test_paralysis_can_skip_a_turn_and_slows_the_target():
    nuzzle = Move("볼부비부비", "electric", 20, physical=True, accuracy=100, ailment="paralysis", ailment_chance=100)
    result = simulate((mon("A", ["electric"], moves=[nuzzle], speed=200, hp=255, defense=255),
                       mon("B", ["normal"], hp=255, defense=255, speed=150)), seed=3)
    assert actions(result)[0].changes == (Change(1, "B", "paralysis"),)
    assert any(action.side == 1 and action.move == "" for action in actions(result))


def test_stat_changes_hit_the_target_or_the_user_and_stop_at_six():
    crunch = replace(TACKLE, stat_changes=(("defense", -1),), stat_chance=100)
    overheat = replace(FLAMETHROWER, stat_changes=(("special_attack", -2),), stat_on_user=True, stat_chance=100)
    assert first_action(mon("A", ["normal"], moves=[crunch], speed=200), mon("B", ["normal"], hp=255)).changes == (
        Change(1, "B", "defense", -1),)
    assert first_action(mon("A", ["fire"], moves=[overheat], speed=200), mon("B", ["water"], hp=255)).changes == (
        Change(0, "A", "special_attack", -2),)
    fighter = _Fighter.enter(mon("B", ["normal"]))
    fighter.stages["defense"] = -6
    assert fighter.stat("defense") == fighter.stats["defense"] * 2 / 8


def test_a_stalemate_ends_at_the_turn_limit():
    lick = Move("핥기", "ghost", 30, physical=True, accuracy=100, pp=999)
    result = simulate((mon("노말", ["normal"], moves=[replace(TACKLE, pp=999)]), mon("유령", ["ghost"], moves=[lick])), 0)
    assert (result.turns, result.winner) == (TURN_LIMIT, 0)


QUICK_ATTACK = Move("전광석화", "normal", 40, physical=True, accuracy=100, priority=1)


def test_a_priority_move_goes_before_a_faster_foe():
    slow = mon("느림", ["normal"], moves=[QUICK_ATTACK], speed=20)
    fast = mon("빠름", ["normal"], moves=[TACKLE], speed=130)
    for seed in range(20):
        assert actions(simulate((slow, fast), seed))[0].attacker == "느림"
        assert actions(simulate((fast, slow), seed))[0].attacker == "느림"


def test_equal_priority_falls_back_to_speed():
    slow = mon("A", ["normal"], moves=[QUICK_ATTACK], speed=20)
    fast = mon("B", ["normal"], moves=[QUICK_ATTACK], speed=130)
    assert first_action(slow, fast).attacker == "B"


def test_the_higher_priority_goes_first_even_when_both_use_priority_moves():
    high = replace(QUICK_ATTACK, priority=2)
    assert first_action(mon("A", ["normal"], moves=[high], speed=10), mon("B", ["normal"], moves=[QUICK_ATTACK], speed=150)).attacker == "A"


def test_a_speed_tie_goes_both_ways_across_seeds():
    firsts = {first_action(mon("A", ["normal"]), mon("B", ["normal"]), seed=seed).attacker for seed in range(40)}
    assert firsts == {"A", "B"}


def stats_of(**changes):
    return _Fighter.enter(replace(mon("X", ["normal"]), **changes)).stats


def test_adamant_raises_attack_and_lowers_special_attack_by_ten_percent():
    neutral, adamant = stats_of(), stats_of(nature="adamant")
    assert adamant["attack"] == neutral["attack"] * 110 // 100 > neutral["attack"]
    assert adamant["special_attack"] == neutral["special_attack"] * 90 // 100 < neutral["special_attack"]
    for key in ("defense", "special_defense", "speed"):
        assert adamant[key] == neutral[key]


def test_a_nature_never_changes_hp():
    assert _Fighter.enter(replace(mon("X", ["normal"]), nature="adamant")).max_hp == _Fighter.enter(mon("X", ["normal"])).max_hp


def test_missing_unknown_and_neutral_natures_change_nothing():
    neutral = stats_of()
    for nature in (None, "nonsense", "", "hardy", "docile", "serious", "bashful", "quirky"):
        assert stats_of(nature=nature) == neutral


def test_natures_match_the_main_series_table():
    assert NATURE_MODIFIERS["adamant"] == ("attack", "special_attack")
    assert NATURE_MODIFIERS["timid"] == ("speed", "attack")
    assert NATURE_MODIFIERS["bold"] == ("defense", "attack")
    assert NATURE_MODIFIERS["modest"] == ("special_attack", "attack")
    assert NATURE_MODIFIERS["careful"] == ("special_defense", "special_attack")
    assert len(NATURE_MODIFIERS) == 20


RAIN_DANCE = Move("비바라기", "water", 0, physical=False, pp=5, weather="rain")
SUNNY_DAY = Move("쾌청", "fire", 0, physical=False, pp=5, weather="sun")
SANDSTORM = Move("모래바람", "rock", 0, physical=False, pp=5, weather="sandstorm")
THUNDER = Move("번개", "electric", 110, physical=False, accuracy=70, always_hits_in=("rain",))
SWIFT = Move("스피드스타", "normal", 60, physical=False)
WEATHER_ARGS = (1, False)


def weather_damage(move, weather, attacker_types=("water",), defender_types=("normal",)):
    attacker = _Fighter.enter(mon("A", attacker_types, moves=[move], special_attack=150))
    defender = _Fighter.enter(mon("B", defender_types, special_defense=100, defense=100))
    return _damage(attacker, defender, move, 1.0, False, weather, random.Random(0))


@pytest.mark.parametrize("move, weather, factor", [
    (SURF, "rain", 1.5), (SURF, "sun", 0.5), (FLAMETHROWER, "sun", 1.5), (FLAMETHROWER, "rain", 0.5),
    (TACKLE, "rain", 1.0), (SURF, "sandstorm", 1.0),
])
def test_sun_and_rain_scale_fire_and_water_moves(move, weather, factor):
    clear = weather_damage(move, None, attacker_types=("normal",))
    assert weather_damage(move, weather, attacker_types=("normal",)) / clear == pytest.approx(factor, abs=0.05)


def test_sandstorm_raises_rock_special_defense_and_snow_raises_ice_defense():
    rock, ice, plain = (_Fighter.enter(mon("X", [types])) for types in ("rock", "ice", "normal"))
    assert _stats_for(plain, rock, False, "sandstorm")[1] == rock.stat("special_defense") * 1.5
    assert _stats_for(plain, rock, True, "sandstorm")[1] == rock.stat("defense")
    assert _stats_for(plain, plain, False, "sandstorm")[1] == plain.stat("special_defense")
    assert _stats_for(plain, ice, True, "snow")[1] == ice.stat("defense") * 1.5
    assert _stats_for(plain, ice, False, "snow")[1] == ice.stat("special_defense")


def test_a_water_user_opens_with_rain_dance_and_weather_lasts_five_turns():
    tank = dict(hp=255, defense=250, special_defense=250, attack=5, special_attack=5)
    rainy = mon("물", ["water"], moves=[RAIN_DANCE, SURF], speed=200, **tank)
    result = simulate((rainy, mon("불", ["fire"], moves=[EMBER], speed=10, **tank)), seed=1)
    first = actions(result)[0]
    assert (first.move, first.weather, first.turn) == ("비바라기", "rain", 1)
    assert [event for event in result.events if isinstance(event, WeatherEnd)][0] == WeatherEnd(WEATHER_TURNS, "rain")
    rain_turns = [action.turn for action in actions(result) if action.move == "비바라기"]
    assert rain_turns[:2] == [1, WEATHER_TURNS + 1]


def test_a_weather_move_that_changes_nothing_is_never_picked():
    result = simulate((mon("A", ["normal"], moves=[RAIN_DANCE, TACKLE]), mon("B", ["normal"])), seed=0)
    assert all(action.move != "비바라기" for action in actions(result))


def test_a_move_for_the_weather_already_up_fails_and_does_not_restart_it():
    fighters = (_Fighter.enter(mon("A", ["water"], moves=[RAIN_DANCE])), _Fighter.enter(mon("B", ["fire"], hp=255, special_defense=150)))
    weather = _Weather("rain", 2)
    action = _act(3, 0, fighters, 0, weather, random.Random(0))
    assert (action.failed, action.weather, weather.turns_left) == (True, None, 2)


def test_sandstorm_chips_a_non_immune_pokemon_and_spares_rock_ground_and_steel():
    for spared in ("ground", "steel"):
        result = simulate((mon("돌", ["rock"], moves=[SANDSTORM, SWIFT], hp=255, defense=250, special_defense=250),
                           mon("상대", [spared], moves=[SWIFT], hp=255, special_defense=250)), seed=0)
        assert "sandstorm" in [action.weather for action in actions(result)]
        assert not [event for event in result.events if isinstance(event, WeatherDamage)]
    result = simulate((mon("돌", ["rock"], moves=[SANDSTORM, SWIFT], hp=255, defense=250, special_defense=250),
                       mon("상대", ["normal"], moves=[SWIFT], hp=255, special_defense=250)), seed=0)
    chips = [event for event in result.events if isinstance(event, WeatherDamage)]
    assert chips and {chip.side for chip in chips} == {1}
    assert chips[0].turn == 1 and chips[0].weather == "sandstorm" and chips[0].hp < 100


def test_sandstorm_chip_is_a_sixteenth_of_max_hp_and_can_knock_out():
    fighters = (_Fighter.enter(mon("A", ["normal"])), _Fighter.enter(mon("B", ["rock"])))
    events = []
    assert _weather_upkeep(1, fighters, _Weather("sandstorm", 3), events) is None
    assert fighters[0].hp == fighters[0].max_hp - fighters[0].max_hp // 16 and fighters[1].hp == fighters[1].max_hp
    fighters[0].hp = 1
    assert _weather_upkeep(2, fighters, _Weather("sandstorm", 3), events) == 0
    assert events[-1] == WeatherDamage(2, 0, "A", 0, True, "sandstorm")


def test_thunder_never_misses_in_the_rain_but_can_miss_otherwise():
    fighters = (_Fighter.enter(mon("A", ["electric"], moves=[THUNDER])), _Fighter.enter(mon("B", ["normal"], hp=255)))
    rain = [_act(1, 0, fighters, 0, _Weather("rain", 3), random.Random(seed)).missed for seed in range(60)]
    clear = [_act(1, 0, fighters, 0, _Weather(), random.Random(seed)).missed for seed in range(60)]
    assert not any(rain) and any(clear)


def test_weather_never_blocks_a_battle_from_ending():
    for seed in range(20):
        result = simulate((mon("A", ["water"], moves=[RAIN_DANCE, SURF, SUNNY_DAY]),
                           mon("B", ["fire"], moves=[SUNNY_DAY, EMBER, RAIN_DANCE])), seed)
        assert result.winner in (0, 1) and result.turns <= TURN_LIMIT


def test_a_weather_move_is_not_picked_when_an_attack_surely_finishes_the_foe():
    fighters = (_Fighter.enter(mon("A", ["water"], moves=[RAIN_DANCE, SURF], special_attack=30)),
                _Fighter.enter(mon("B", ["fire"], hp=255, special_defense=150)))
    assert _best_move(*fighters, None) == 0
    fighters[1].hp = 1
    assert _best_move(*fighters, None) == 1
