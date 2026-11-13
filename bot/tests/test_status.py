import random
from collections import Counter
from dataclasses import replace

import pytest

from ypoke.battle import Action, Change, Move, StatusDamage, _act, _best_move, _Fighter, _hit_count, _Weather, simulate
from ypoke.moves import battle_moves
from test_battle import FLAMETHROWER, TACKLE, actions, mon

SLEEPER = replace(TACKLE, name="잠재우기", ailment="sleep", ailment_chance=100)
WEAK_ATTACKER = dict(attack=10, speed=200)
TANK = dict(hp=255, defense=255, speed=10)


def duel(first, second):
    return _Fighter.enter(first), _Fighter.enter(second)


def act_once(fighters, move_index=0, side=0, seed=0):
    return _act(1, side, fighters, move_index, _Weather(), random.Random(seed))


def test_toxic_damage_grows_every_turn():
    toxin = replace(TACKLE, name="독엄니", ailment="toxic", ailment_chance=100)
    result = simulate((mon("A", ["normal"], moves=[toxin], **WEAK_ATTACKER), mon("B", ["normal"], **TANK)), seed=0)
    ticks = [event for event in result.events if isinstance(event, StatusDamage)]
    assert ticks and {tick.kind for tick in ticks} == {"toxic"}
    fighter = _Fighter.enter(mon("B", ["normal"], **TANK))
    fighter.status = "toxic"
    damages = [fighter.residual_damage() for _ in range(4)]
    assert damages == [fighter.max_hp * turn // 16 for turn in (1, 2, 3, 4)]
    assert damages == sorted(set(damages))


def test_regular_poison_takes_an_eighth_every_turn():
    fighter = _Fighter.enter(mon("B", ["normal"], **TANK))
    fighter.status = "poison"
    assert [fighter.residual_damage() for _ in range(3)] == [fighter.max_hp // 8] * 3


@pytest.mark.parametrize("ailment,immune_type", [
    ("poison", "poison"), ("poison", "steel"), ("toxic", "poison"), ("toxic", "steel"),
    ("freeze", "ice"), ("paralysis", "electric"), ("burn", "fire"),
])
def test_an_immune_type_cannot_be_given_the_status(ailment, immune_type):
    move = replace(TACKLE, ailment=ailment, ailment_chance=100)
    action = act_once(duel(mon("A", ["normal"], moves=[move], speed=200), mon("B", [immune_type], **TANK)))
    assert action.changes == ()


@pytest.mark.parametrize("ailment", ["poison", "toxic", "sleep", "freeze", "burn", "paralysis"])
def test_a_second_major_status_does_not_stack(ailment):
    first, second = duel(mon("A", ["normal"], moves=[replace(TACKLE, ailment=ailment, ailment_chance=100)]),
                         mon("B", ["normal"], **TANK))
    second.status = "burn"
    assert act_once((first, second)).changes == ()
    assert second.status == "burn"


def test_poison_type_attacker_is_not_stopped_by_its_own_poison_move():
    move = replace(TACKLE, type="poison", ailment="poison", ailment_chance=100)
    assert act_once(duel(mon("A", ["poison"], moves=[move]), mon("B", ["normal"], **TANK))).changes == (
        Change(1, "B", "poison"),)


@pytest.mark.parametrize("seed", range(40))
def test_sleep_ends_within_three_turns(seed):
    result = simulate((mon("A", ["normal"], moves=[SLEEPER], **WEAK_ATTACKER), mon("B", ["normal"], **TANK)), seed)
    sleeper = [action for action in actions(result) if action.side == 1]
    asleep = 0
    while sleeper[asleep].blocked == "sleep":
        asleep += 1
    assert 1 <= asleep <= 3
    assert sleeper[asleep].recovered == ("sleep",) and sleeper[asleep].move == TACKLE.name


def test_sleep_lengths_cover_one_to_three_turns():
    lengths = set()
    for seed in range(60):
        sleeper = [a for a in actions(simulate((mon("A", ["normal"], moves=[SLEEPER], **WEAK_ATTACKER),
                                                 mon("B", ["normal"], **TANK)), seed)) if a.side == 1]
        lengths.add(next(index for index, action in enumerate(sleeper) if action.blocked != "sleep"))
    assert lengths == {1, 2, 3}


def test_a_sleeping_pokemon_does_not_spend_pp():
    _, sleeper = duel(mon("A", ["normal"]), mon("B", ["normal"]))
    sleeper.status, sleeper.sleep_left = "sleep", 2
    pp = list(sleeper.pp)
    assert act_once((_Fighter.enter(mon("A", ["normal"])), sleeper), side=1).blocked == "sleep"
    assert sleeper.pp == pp


def test_a_frozen_pokemon_is_hit_by_a_fire_move_and_thaws():
    fighters = duel(mon("A", ["fire"], moves=[FLAMETHROWER]), mon("B", ["normal"], **TANK))
    fighters[1].status = "freeze"
    action = act_once(fighters)
    assert Change(1, "B", "thaw") in action.changes
    assert fighters[1].status is None


def test_a_non_fire_hit_leaves_the_target_frozen():
    fighters = duel(mon("A", ["normal"], moves=[TACKLE]), mon("B", ["normal"], **TANK))
    fighters[1].status = "freeze"
    assert act_once(fighters).changes == () and fighters[1].status == "freeze"


def test_a_frozen_pokemon_thaws_about_one_turn_in_five():
    thawed = 0
    for seed in range(400):
        fighters = duel(mon("A", ["normal"]), mon("B", ["normal"]))
        fighters[0].status = "freeze"
        action = act_once(fighters, seed=seed)
        if action.recovered == ("freeze",):
            thawed += 1
        else:
            assert (action.blocked, action.move) == ("freeze", "")
    assert 50 <= thawed <= 110


def test_a_frozen_pokemon_using_a_fire_move_thaws_and_acts():
    fighters = duel(mon("A", ["fire"], moves=[FLAMETHROWER]), mon("B", ["normal"], **TANK))
    fighters[0].status = "freeze"
    action = act_once(fighters)
    assert (action.recovered, action.move, action.blocked) == (("freeze",), "화염방사", "")


def test_a_freezing_move_freezes_and_the_target_cannot_move():
    ice = Move("얼음빔", "ice", 90, physical=False, accuracy=100, ailment="freeze", ailment_chance=100)
    result = simulate((mon("A", ["ice"], moves=[ice], **WEAK_ATTACKER), mon("B", ["normal"], **TANK)), seed=1)
    assert actions(result)[0].changes == (Change(1, "B", "freeze"),)
    assert any(action.blocked == "freeze" for action in actions(result))


def test_confusion_makes_a_pokemon_hit_itself_about_a_third_of_the_time():
    hits = 0
    for seed in range(300):
        fighters = duel(mon("A", ["normal"]), mon("B", ["normal"], **TANK))
        fighters[0].confusion_left = 5
        action = act_once(fighters, seed=seed)
        if action.blocked == "confusion":
            hits += 1
            assert fighters[0].hp < fighters[0].max_hp and action.attacker_hp < 100
            assert action.move == "" and action.defender_hp == 100 and fighters[1].hp == fighters[1].max_hp
        else:
            assert action.move == TACKLE.name
    assert 70 <= hits <= 130


def test_confusion_self_damage_is_typeless_power_forty_and_can_faint():
    fighters = duel(mon("A", ["normal"], level=5), mon("B", ["normal"]))
    fighters[0].confusion_left, fighters[0].hp = 3, 1
    for seed in range(100):
        fighters[0].hp, fighters[0].confusion_left = 1, 3
        action = act_once(fighters, seed=seed)
        if action.blocked == "confusion":
            assert action.attacker_fainted and fighters[0].hp == 0
            return
    pytest.fail("no self-hit in 100 seeds")


def test_confusion_wears_off_after_a_few_turns():
    confuse = Move("초음파", "normal", 20, physical=False, accuracy=100, ailment="confusion", ailment_chance=100)
    snapped = set()
    for seed in range(40):
        result = simulate((mon("A", ["normal"], moves=[confuse], **WEAK_ATTACKER), mon("B", ["normal"], **TANK)), seed)
        first = next(index for index, action in enumerate(
            action for action in actions(result) if action.side == 1) if "confusion" in action.recovered)
        snapped.add(first + 1)
    assert snapped <= {2, 3, 4, 5} and len(snapped) > 1


def test_confusion_hits_every_type_but_never_stacks():
    confuse = replace(TACKLE, ailment="confusion", ailment_chance=100)
    for kind in ("normal", "poison", "steel", "ice", "electric", "fire"):
        fighters = duel(mon("A", ["normal"], moves=[confuse]), mon("B", [kind], **TANK))
        assert act_once(fighters).changes == (Change(1, "B", "confusion"),)
    again = duel(mon("A", ["normal"], moves=[confuse]), mon("B", ["normal"], **TANK))
    again[1].confusion_left = 4
    assert act_once(again).changes == ()
    assert again[1].confusion_left == 4


def test_confusion_can_sit_on_top_of_a_major_status():
    both = duel(mon("A", ["normal"], moves=[replace(TACKLE, ailment="confusion", ailment_chance=100)]),
                mon("B", ["normal"], **TANK))
    both[1].status = "burn"
    assert act_once(both).changes == (Change(1, "B", "confusion"),)


def test_giga_drain_heals_half_the_damage_dealt():
    drain = Move("기가드레인", "grass", 75, physical=False, accuracy=100, drain=50)
    fighters = duel(mon("A", ["grass"], moves=[drain]), mon("B", ["normal"], **TANK))
    fighters[0].hp = 10
    before = fighters[1].hp
    action = act_once(fighters)
    dealt = before - fighters[1].hp
    assert dealt > 20 and action.drained
    assert fighters[0].hp == 10 + dealt // 2


def test_drain_never_heals_past_full_hp():
    drain = Move("기가드레인", "grass", 75, physical=False, accuracy=100, drain=50)
    fighters = duel(mon("A", ["grass"], moves=[drain]), mon("B", ["normal"], **TANK))
    act_once(fighters)
    assert fighters[0].hp == fighters[0].max_hp


def test_a_drain_from_a_knockout_blow_only_counts_the_hp_the_target_had():
    drain = Move("기가드레인", "grass", 200, physical=False, accuracy=100, drain=50)
    fighters = duel(mon("A", ["grass"], moves=[drain]), mon("B", ["normal"], hp=10))
    fighters[1].hp, fighters[0].hp = 6, 1
    action = act_once(fighters)
    assert action.knockout and fighters[0].hp == 1 + 3


def test_take_down_recoil_is_a_quarter_of_the_damage_dealt():
    take_down = Move("누르기", "normal", 90, physical=True, accuracy=100, drain=-25)
    fighters = duel(mon("A", ["normal"], moves=[take_down]), mon("B", ["normal"], **TANK))
    before = fighters[1].hp
    action = act_once(fighters)
    dealt = before - fighters[1].hp
    assert action.recoil and fighters[0].max_hp - fighters[0].hp == dealt * 25 // 100


def test_recoil_can_knock_out_the_user():
    head_smash = Move("로크블라스트", "rock", 150, physical=True, accuracy=100, drain=-50)
    fighters = duel(mon("A", ["rock"], moves=[head_smash]), mon("B", ["normal"], **TANK))
    fighters[0].hp = 1
    action = act_once(fighters)
    assert action.attacker_fainted and not action.knockout


def test_double_slap_hits_two_to_five_times_with_main_series_odds():
    slap = Move("연속뺨치기", "normal", 15, physical=True, accuracy=100, min_hits=2, max_hits=5)
    counts = Counter()
    for seed in range(2000):
        fighters = duel(mon("A", ["normal"], moves=[slap]), mon("B", ["normal"], **TANK))
        counts[act_once(fighters, seed=seed).hits] += 1
    assert set(counts) == {2, 3, 4, 5}
    assert 0.30 < counts[2] / 2000 < 0.40 and 0.30 < counts[3] / 2000 < 0.40
    assert 0.11 < counts[4] / 2000 < 0.19 and 0.11 < counts[5] / 2000 < 0.19


def test_a_multi_hit_move_deals_damage_for_every_hit_and_stops_on_a_knockout():
    slap = Move("연속뺨치기", "normal", 15, physical=True, accuracy=100, min_hits=2, max_hits=5)
    fighters = duel(mon("A", ["normal"], moves=[slap]), mon("B", ["normal"], **TANK))
    one_hit = _Fighter.enter(mon("B", ["normal"], **TANK))
    action = act_once(fighters, seed=3)
    assert action.hits >= 2 and one_hit.hp - fighters[1].hp > action.hits
    weak = duel(mon("A", ["normal"], moves=[slap]), mon("B", ["normal"]))
    weak[1].hp = 1
    last = act_once(weak)
    assert (last.hits, last.knockout) == (1, True)


@pytest.mark.parametrize("low,high", [(2, 2), (3, 3), (2, 3)])
def test_other_hit_ranges_are_uniform(low, high):
    move = replace(TACKLE, min_hits=low, max_hits=high)
    assert {_hit_count(move, random.Random(seed)) for seed in range(100)} == set(range(low, high + 1))


def test_the_ai_values_a_multi_hit_move_by_its_expected_hits():
    slap = Move("연속뺨치기", "normal", 25, physical=True, accuracy=100, min_hits=2, max_hits=5)
    plain = Move("힘껏치기", "normal", 60, physical=True, accuracy=100)
    attacker = mon("A", ["normal"], moves=[plain, slap], speed=200)
    fighters = duel(attacker, mon("B", ["normal"], **TANK))
    assert attacker.moves[_best_move(*fighters, None)].name == "연속뺨치기"


def test_battle_moves_carry_drain_and_hits_from_the_cached_move():
    data = {"id": 1, "name": "기술", "type": "grass", "power": 75, "damage_class": "special", "accuracy": 100,
            "pp": 10, "crit_rate": 0, "ailment": "toxic", "ailment_chance": 50, "stat_changes": [],
            "stat_target": "target", "stat_chance": 0, "priority": 0, "drain": 50, "min_hits": 2, "max_hits": 5,
            "weather": None, "always_hits_in": []}
    (move,) = battle_moves([data], None)
    assert (move.ailment, move.drain, move.min_hits, move.max_hits) == ("toxic", 50, 2, 5)


def test_same_seed_replays_a_status_heavy_battle():
    sides = (mon("A", ["normal"], moves=[SLEEPER], **WEAK_ATTACKER), mon("B", ["normal"], **TANK))
    first = simulate(sides, seed=7)
    assert first == simulate(sides, seed=7)
    assert any(isinstance(event, Action) and event.blocked for event in first.events)
