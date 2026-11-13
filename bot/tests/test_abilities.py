import random
from dataclasses import replace

import pytest

from ypoke.battle import (
    CONFUSION_HIT, WEATHER_TURNS, AbilityTrigger, BaseStats, Change, Combatant, Move, WeatherEnd, _act, _best_move,
    _enter_battle, _Fighter, _power, _stats_for, _turn_order, _unrolled_damage, _Weather, simulate,
)

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
SLAM = Move("메가톤펀치", "normal", 80, physical=True, accuracy=100)
EARTHQUAKE = Move("지진", "ground", 100, physical=True, accuracy=100)
FLAMETHROWER = Move("화염방사", "fire", 90, physical=False, accuracy=100)
ICE_BEAM = Move("냉동빔", "ice", 90, physical=False, accuracy=100)
SURF = Move("파도타기", "water", 90, physical=False, accuracy=100)


def mon(ability=None, name="A", types=("normal",), moves=(), hp=80, attack=80, defense=80, speed=80):
    return Combatant(
        name=name, level=50, types=tuple(types), base=BaseStats(hp, attack, defense, 80, 80, speed), ivs=IVS,
        moves=tuple(moves), ability=ability,
    )


def fighter(ability=None, **kwargs):
    return _Fighter.enter(mon(ability, **kwargs))


def damage(attacker, defender, move, weather=None):
    return _unrolled_damage(attacker, defender, move, 1.0, weather)


def test_intimidate_lowers_the_foes_attack_one_stage_on_entry():
    fighters = (fighter("intimidate"), fighter(name="B"))
    triggers = _enter_battle(fighters, _Weather(), random.Random(0))
    assert triggers == [AbilityTrigger(0, "A", "intimidate", change=Change(1, "B", "attack", -1))]
    assert (fighters[1].stages["attack"], fighters[0].stages["attack"]) == (-1, 0)


def test_intimidate_does_nothing_against_an_attack_already_at_minus_six():
    fighters = (fighter("intimidate"), fighter())
    fighters[1].stages["attack"] = -6
    assert _enter_battle(fighters, _Weather(), random.Random(0)) == []


def test_an_intimidated_foe_hits_softer():
    plain, scared = fighter(moves=[SLAM]), fighter(moves=[SLAM])
    scared.stages["attack"] = -1
    victim = fighter(name="B")
    assert damage(scared, victim, SLAM) < damage(plain, victim, SLAM)


def test_the_battle_opens_with_the_entry_ability_event():
    result = simulate((mon("intimidate", moves=[TACKLE]), mon(name="B", moves=[TACKLE])), seed=3)
    assert isinstance(result.events[0], AbilityTrigger) and result.events[0].ability == "intimidate"


def test_levitate_dodges_ground_moves_and_says_so():
    levitating = fighter("levitate", name="B", types=["psychic"])
    digger = fighter(moves=[EARTHQUAKE])
    action = _act(1, 0, (digger, levitating), 0, _Weather(), random.Random(0))
    assert (action.multiplier, action.ability, levitating.hp == levitating.max_hp) == (0, "levitate", True)
    assert not action.knockout


def test_levitate_does_not_stop_other_types_and_a_flyer_is_not_credited_with_it():
    levitating = fighter("levitate", name="B", types=["psychic"])
    assert _act(1, 0, (fighter(moves=[TACKLE]), levitating), 0, _Weather(), random.Random(0)).ability is None
    flyer = fighter("levitate", name="B", types=["flying"])
    assert _act(1, 0, (fighter(moves=[EARTHQUAKE]), flyer), 0, _Weather(), random.Random(0)).ability is None


def test_a_ground_move_is_not_chosen_against_levitate_when_another_move_works():
    levitating = fighter("levitate", name="B", types=["psychic"])
    assert _best_move(fighter(moves=[EARTHQUAKE, TACKLE]), levitating, None) == 1


@pytest.mark.parametrize("ability,move_type", [
    ("blaze", "fire"), ("torrent", "water"), ("overgrow", "grass"), ("swarm", "bug"),
])
def test_a_starter_ability_boosts_its_type_at_a_third_hp_or_less(ability, move_type):
    move = Move("기술", move_type, 80, physical=False, accuracy=100)
    boosted, plain, target = fighter(ability, moves=[move]), fighter(moves=[move]), fighter(name="B")
    base = damage(plain, target, move)
    assert damage(boosted, target, move) == base
    boosted.hp = boosted.max_hp // 3
    assert damage(boosted, target, move) == pytest.approx(base * 1.5, rel=0.03)
    boosted.hp = boosted.max_hp // 3 + 3
    assert damage(boosted, target, move) == base
    boosted.hp = 1
    other = Move("기술", "ground", 80, physical=False, accuracy=100)
    assert damage(boosted, target, other) == damage(plain, target, other)


@pytest.mark.parametrize("ability,weather", [
    ("drizzle", "rain"), ("drought", "sun"), ("sand-stream", "sandstorm"), ("snow-warning", "snow"),
])
def test_each_weather_ability_sets_its_weather_for_five_turns(ability, weather):
    state = _Weather()
    triggers = _enter_battle((fighter(ability), fighter(name="B")), state, random.Random(0))
    assert triggers == [AbilityTrigger(0, "A", ability, weather=weather)]
    assert (state.kind, state.turns_left) == (weather, WEATHER_TURNS)


def test_drizzle_starts_rain_that_ends_after_five_turns_in_a_real_battle():
    tank = {"hp": 255, "defense": 255}
    result = simulate((mon("drizzle", moves=[TACKLE], **tank), mon(name="B", moves=[TACKLE], **tank)), seed=0)
    assert result.events[0].weather == "rain"
    assert [event for event in result.events if isinstance(event, WeatherEnd)][0] == WeatherEnd(WEATHER_TURNS, "rain")


def test_the_slower_weather_setter_keeps_its_weather():
    slow, fast = fighter("drought", speed=10), fighter("drizzle", speed=200)
    for sides in ((slow, fast), (fast, slow)):
        state = _Weather()
        _enter_battle(sides, state, random.Random(0))
        assert state.kind == "sun"


def test_the_same_weather_is_not_set_twice():
    triggers = _enter_battle((fighter("drizzle"), fighter("drizzle")), _Weather(), random.Random(0))
    assert len(triggers) == 1


def test_an_unknown_ability_changes_nothing():
    plain = (mon(types=["fire"], moves=[FLAMETHROWER]), mon(name="B", types=["water"], moves=[SURF]))
    odd = (replace(plain[0], ability="made-up"), replace(plain[1], ability="wonder-guard"))
    for seed in range(10):
        assert simulate(odd, seed) == simulate(plain, seed)


def test_no_ability_means_no_ability_events():
    assert mon().ability is None
    result = simulate((mon(moves=[TACKLE]), mon(name="B", moves=[TACKLE])), seed=1)
    assert not [event for event in result.events if isinstance(event, AbilityTrigger)]


@pytest.mark.parametrize("ability", ["huge-power", "pure-power"])
def test_huge_and_pure_power_double_attack_only(ability):
    plain, strong = fighter(), fighter(ability)
    assert strong.stat("attack") == plain.stat("attack") * 2
    assert strong.stat("special_attack") == plain.stat("special_attack")


def test_thick_fat_halves_fire_and_ice_damage_but_not_water():
    thick, plain, attacker = fighter("thick-fat"), fighter(), fighter(name="B")
    for move in (FLAMETHROWER, ICE_BEAM):
        assert damage(attacker, thick, move) == pytest.approx(damage(attacker, plain, move) / 2, rel=0.02)
    assert damage(attacker, thick, SURF) == damage(attacker, plain, SURF)


def test_technician_boosts_weak_moves_only():
    technician, plain, target = fighter("technician"), fighter(), fighter(name="B")
    assert damage(technician, target, TACKLE) > damage(plain, target, TACKLE)
    assert damage(technician, target, SLAM) == damage(plain, target, SLAM)


def test_adaptability_raises_stab_to_double():
    adaptable, plain, target = fighter("adaptability"), fighter(), fighter(name="B")
    assert damage(adaptable, target, SLAM) == pytest.approx(damage(plain, target, SLAM) * 2 / 1.5, rel=0.02)
    assert damage(adaptable, target, EARTHQUAKE) == damage(plain, target, EARTHQUAKE)


def test_guts_raises_attack_when_statused_and_ignores_the_burn_penalty():
    plain, guts = fighter(), fighter("guts")
    assert guts.stat("attack") == plain.stat("attack")
    guts.status = plain.status = "burn"
    assert guts.stat("attack") == plain.stat("attack") * 1.5
    assert _stats_for(guts, guts, physical=True)[0] == guts.stat("attack")
    assert _stats_for(plain, plain, physical=True)[0] == plain.stat("attack") / 2


def test_sturdy_survives_one_would_be_knockout_at_full_hp_only():
    sturdy = fighter("sturdy", name="B", hp=20, defense=10)
    brute = fighter(moves=[SLAM], attack=250)
    action = _act(1, 0, (brute, sturdy), 0, _Weather(), random.Random(0))
    assert (sturdy.hp, action.ability, action.knockout) == (1, "sturdy", False)
    action = _act(2, 0, (brute, sturdy), 0, _Weather(), random.Random(0))
    assert (sturdy.hp, action.ability, action.knockout) == (0, None, True)


def test_sturdy_does_nothing_against_a_hit_that_does_not_kill():
    sturdy = fighter("sturdy", name="B", hp=255, defense=200)
    weak = fighter(moves=[TACKLE], attack=20)
    assert _act(1, 0, (weak, sturdy), 0, _Weather(), random.Random(0)).ability is None


@pytest.mark.parametrize("ability,weather", [("swift-swim", "rain"), ("chlorophyll", "sun"), ("sand-rush", "sandstorm")])
def test_a_weather_runner_doubles_speed_in_its_weather_only(ability, weather):
    runner, plain = fighter(ability), fighter()
    assert runner.stat("speed", weather) == plain.stat("speed") * 2
    assert runner.stat("speed") == plain.stat("speed")
    assert runner.stat("speed", "hail") == plain.stat("speed")


def ailing(name, ailment, **kwargs):
    return Move(name, "normal", 40, physical=False, accuracy=100, ailment=ailment, ailment_chance=100, **kwargs)


@pytest.mark.parametrize("ability,ailment", [
    ("water-veil", "burn"), ("limber", "paralysis"), ("immunity", "poison"), ("immunity", "toxic"),
    ("insomnia", "sleep"),
])
def test_a_status_ability_blocks_its_ailment_and_says_so(ability, ailment):
    shield, plain = fighter(ability, name="B"), fighter(name="B")
    move = ailing("기술", ailment)
    attacker = fighter(moves=[move])
    blocked = _act(1, 0, (attacker, shield), 0, _Weather(), random.Random(0))
    assert (shield.status, blocked.ability, blocked.changes) == (None, ability, ())
    landed = _act(1, 0, (attacker, plain), 0, _Weather(), random.Random(0))
    assert (plain.status, landed.ability) == (ailment, None)


def test_a_status_ability_lets_other_ailments_through():
    shield = fighter("limber", name="B")
    _act(1, 0, (fighter(moves=[ailing("기술", "burn")]), shield), 0, _Weather(), random.Random(0))
    assert shield.status == "burn"


def hit_back(defender_ability, move=SLAM, attacker_ability=None, attacker_types=("normal",), seeds=300):
    landed = 0
    for seed in range(seeds):
        attacker = fighter(attacker_ability, types=attacker_types, moves=[move])
        defender = fighter(defender_ability, name="B", hp=255, defense=255)
        action = _act(1, 0, (attacker, defender), 0, _Weather(), random.Random(seed))
        landed += attacker.status is not None
        assert (action.ability == defender_ability) == (attacker.status is not None)
    return landed


@pytest.mark.parametrize("ability,ailment", [("static", "paralysis"), ("flame-body", "burn"), ("poison-point", "poison")])
def test_a_contact_ability_sometimes_afflicts_a_physical_attacker(ability, ailment):
    landed = hit_back(ability)
    assert 50 < landed < 130
    attacker = fighter(moves=[SLAM])
    for seed in range(300):
        attacker.status = None
        _act(1, 0, (attacker, fighter(ability, name="B", hp=255, defense=255)), 0, _Weather(), random.Random(seed))
        if attacker.status:
            assert attacker.status == ailment
            break


def test_a_contact_ability_ignores_special_moves_immune_types_and_blocking_abilities():
    special = Move("기술", "normal", 80, physical=False, accuracy=100)
    assert hit_back("static", special) == 0
    assert hit_back("static", attacker_types=("electric",)) == 0
    assert hit_back("static", attacker_ability="limber") == 0
    assert hit_back("poison-point", attacker_types=("steel",)) == 0
    assert hit_back("flame-body", attacker_types=("fire",)) == 0


def test_a_contact_ability_does_not_trigger_when_the_hit_knocks_out():
    attacker = fighter(moves=[SLAM], attack=250)
    defender = fighter("static", name="B", hp=5, defense=5)
    action = _act(1, 0, (attacker, defender), 0, _Weather(), random.Random(0))
    assert action.knockout and attacker.status is None and action.ability is None


def test_the_confusion_self_hit_is_not_boosted_by_technician_or_low_hp_abilities():
    technician = fighter("technician")
    plain = fighter()
    assert _power(technician, CONFUSION_HIT) == _power(plain, CONFUSION_HIT) == CONFUSION_HIT.power


def test_sturdy_only_saves_the_first_hit_of_a_multi_hit_move():
    flurry = Move("연속펀치", "normal", 100, physical=True, accuracy=100, min_hits=2, max_hits=2)
    sturdy = fighter("sturdy", name="B", hp=20, defense=10)
    action = _act(1, 0, (fighter(moves=[flurry], attack=250), sturdy), 0, _Weather(), random.Random(0))
    assert (action.hits, action.knockout, action.ability) == (2, True, "sturdy")


def test_a_slower_swift_swimmer_outspeeds_in_the_rain():
    swimmer, quick = fighter("swift-swim", speed=60), fighter(speed=100)
    assert _turn_order((swimmer, quick), (None, None), random.Random(0), None) == (1, 0)
    assert _turn_order((swimmer, quick), (None, None), random.Random(0), "rain") == (0, 1)
