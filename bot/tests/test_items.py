import random
from dataclasses import replace

import pytest
from attacks import attack
from status_moves import put, resolve

from ypoke import battle, items
from ypoke.battle import (STRUGGLE, Action, BaseStats, Combatant, ItemHeal, MegaForm, Move, _Arena, _Fighter,
                          _unrolled_damage, simulate)
from ypoke.narration import battle_card, battle_log
from ypoke.upload_server import PartyError, validate_party

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)
SURF = Move("파도타기", "water", 90, physical=False, accuracy=100)
ONE_SHOT = Move("한방", "normal", 120, physical=True, accuracy=100, pp=1)


def mon(name, item=None, types=("normal",), level=50, moves=(TACKLE,), hp=80, attack=80, defense=80, speed=80):
    return Combatant(
        name=name, level=level, types=tuple(types), base=BaseStats(hp, attack, defense, 80, 80, speed),
        ivs=IVS, moves=tuple(moves), item=item,
    )


def actions(result):
    return [event for event in result.events if isinstance(event, Action)]


def damage(attacker, defender, move, multiplier=1.0):
    return _unrolled_damage(_Fighter.enter(attacker), _Fighter.enter(defender), move, multiplier, None)


def _party(*members):
    return validate_party({"party": list(members)})


def test_leftovers_heals_a_sixteenth_each_turn_it_is_hurt():
    result = simulate((mon("먹보", items.LEFTOVERS, hp=255, defense=255), mon("약골", level=40)), seed=3)
    heals = [event for event in result.events if isinstance(event, ItemHeal)]
    assert heals and all(heal.side == 0 and heal.item == items.LEFTOVERS for heal in heals)
    assert _Fighter.enter(mon("먹보", hp=255)).max_hp // 16 > 0


def test_leftovers_stays_quiet_at_full_hp():
    result = simulate((mon("먹보", items.LEFTOVERS, level=100, hp=255, defense=255, speed=255), mon("약골", level=1)), seed=1)
    assert not [event for event in result.events if isinstance(event, ItemHeal)]


def test_choice_scarf_outspeeds_a_faster_pokemon():
    slow_with_scarf = mon("스카프", items.CHOICE_SCARF, speed=80)
    fast = mon("빠름", speed=100)
    assert actions(simulate((slow_with_scarf, fast), seed=0))[0].attacker == "스카프"
    assert actions(simulate((replace(slow_with_scarf, item=None), fast), seed=0))[0].attacker == "빠름"


def test_choice_band_raises_physical_damage_only():
    banded, plain, foe = mon("머리띠", items.CHOICE_BAND), mon("맨몸"), mon("상대")
    assert damage(banded, foe, TACKLE) > damage(plain, foe, TACKLE) * 1.4
    assert damage(banded, foe, EMBER) == damage(plain, foe, EMBER)


def test_choice_item_repeats_its_first_move_and_struggles_when_it_runs_out():
    wall = mon("벽", hp=255, defense=255, speed=1)
    locked = actions(simulate((mon("고집", items.CHOICE_BAND, moves=(ONE_SHOT, TACKLE), speed=100), wall), seed=2))
    free = actions(simulate((mon("자유", moves=(ONE_SHOT, TACKLE), speed=100), wall), seed=2))
    mine = [action.move for action in locked if action.attacker == "고집"]
    assert mine[0] == "한방" and set(mine[1:5]) == {STRUGGLE.name}
    assert {action.move_id for action in locked if action.move == STRUGGLE.name} == {165}
    assert {action.move for action in free if action.attacker == "자유"} == {"한방", "몸통박치기"}


def test_focus_sash_survives_one_lethal_hit_from_full_hp():
    strong = mon("강함", level=100, attack=255, speed=255)
    weak = mon("띠", items.FOCUS_SASH, level=5, speed=1)
    hits = [action for action in actions(simulate((strong, weak), seed=5)) if action.attacker == "강함"]
    assert (hits[0].defender_item, hits[0].knockout) == (items.FOCUS_SASH, False)
    assert 0 < hits[0].defender_hp <= 10
    assert hits[1].knockout and hits[1].defender_item == ""


def test_a_member_sent_out_later_still_has_its_own_focus_sash():
    strong = mon("강함", level=100, attack=255, speed=255)
    team = (mon("첫째", level=5, speed=1), mon("둘째", items.FOCUS_SASH, level=5, speed=1))
    result = simulate((team, (strong,)), seed=5)
    second = [action for action in actions(result) if action.defender == "둘째"]
    assert second[0].defender_item == items.FOCUS_SASH and not second[0].knockout


def test_leftovers_never_heals_a_fainted_member_waiting_to_be_replaced():
    strong = mon("강함", level=100, attack=255, speed=255)
    team = (mon("첫째", items.LEFTOVERS, level=5, speed=1), mon("둘째", level=5, speed=1))
    result = simulate((team, (strong,)), seed=5)
    assert not [event for event in result.events if isinstance(event, ItemHeal) and event.pokemon == "첫째"]
    assert result.winner == 1


def test_focus_sash_does_nothing_when_not_at_full_hp():
    strong = mon("강함", level=100, attack=255, speed=255)
    weak = mon("띠", items.FOCUS_SASH, level=5, speed=1)
    fighter = _Fighter.enter(weak)
    fighter.hp -= 1
    assert fighter.item == items.FOCUS_SASH
    from ypoke.battle import _Weather, _act
    import random
    action = _act(1, 0, (_Fighter.enter(strong), fighter), 0, _Weather(), random.Random(0))
    assert action.knockout and action.defender_item == ""


def test_life_orb_boosts_damage_and_costs_a_tenth_of_max_hp():
    orb, plain, foe = mon("구슬", items.LIFE_ORB, hp=255), mon("맨몸", hp=255), mon("상대", hp=255, defense=255)
    assert damage(orb, foe, TACKLE) == pytest.approx(damage(plain, foe, TACKLE) * 1.3)
    first = actions(simulate((replace(orb, level=100), foe), seed=4))[0]
    assert first.attacker_item == items.LIFE_ORB and first.attacker_hp < 100


IRON_HEAD, GROWL, GIGA_DRAIN = attack(442), attack(45), attack(202)
NEVER_HITS = Move("빗나감", "normal", 40, physical=True, accuracy=1)
DOLL = 10_000
SUBSTITUTE, PROTECT = {"substitute": DOLL}, {"protect": True}
BUSTED = (MegaForm(("ghost", "fairy"), BaseStats(55, 90, 80, 50, 105, 96), form_id=10143, kind="busted"),)
NOICE = (MegaForm(("ice",), BaseStats(75, 80, 70, 65, 50, 130), form_id=10185, kind="noice"),)


@pytest.mark.parametrize(("move", "ability", "foe_types", "foe_ability", "foe_forms", "foe_volatiles", "recoil"), [
    (TACKLE, None, ("normal",), None, (), {}, True),
    (TACKLE, None, ("normal",), None, (), SUBSTITUTE, True),
    (TACKLE, None, ("normal",), "disguise", BUSTED, {}, True),
    (TACKLE, None, ("normal",), "ice-face", NOICE, {}, True),
    (TACKLE, "magic-guard", ("normal",), None, (), SUBSTITUTE, False),
    (IRON_HEAD, "sheer-force", ("normal",), None, (), SUBSTITUTE, False),
    (IRON_HEAD, "sheer-force", ("normal",), None, (), {}, False),
    (NEVER_HITS, None, ("normal",), None, (), {}, False),
    (GROWL, None, ("normal",), None, (), {}, False),
    (TACKLE, None, ("ghost",), None, (), {}, False),
    (TACKLE, None, ("normal",), None, (), PROTECT, False),
])
def test_life_orb_costs_a_tenth_whenever_the_move_lands_even_on_a_substitute_or_disguise(
        move, ability, foe_types, foe_ability, foe_forms, foe_volatiles, recoil):
    user, foe, arena = facing(items.LIFE_ORB, ability, foe_types, foe_ability, foe_forms, foe_volatiles)
    action = resolve(user, foe, move, arena, seed=1)
    assert action.missed == (move is NEVER_HITS)
    assert user.max_hp - user.hp == (user.max_hp // items.LIFE_ORB_RECOIL_FRACTION if recoil else 0)
    assert action.attacker_item == (items.LIFE_ORB if recoil else "")


@pytest.mark.parametrize(("foe_ability", "foe_forms", "foe_volatiles"), [
    (None, (), SUBSTITUTE), ("disguise", BUSTED, {}),
])
def test_shell_bell_heals_nothing_from_a_hit_a_substitute_or_disguise_took(foe_ability, foe_forms, foe_volatiles):
    user, foe, arena = facing(items.SHELL_BELL, foe_ability=foe_ability, foe_forms=foe_forms,
                              foe_volatiles=foe_volatiles)
    user.hp = user.max_hp // 2
    action = resolve(user, foe, TACKLE, arena, seed=1)
    assert action.hits == 1
    assert (user.hp, action.attacker_item) == (user.max_hp // 2, "")


@pytest.mark.parametrize(("move", "ability", "heals"), [
    (IRON_HEAD, "sheer-force", False),
    (IRON_HEAD, None, True),
    (TACKLE, "sheer-force", True),
])
def test_shell_bell_heals_nothing_when_sheer_force_drops_the_moves_added_effect(move, ability, heals):
    user, foe, arena = facing(items.SHELL_BELL, ability)
    user.hp = user.max_hp // 2
    action = resolve(user, foe, move, arena, seed=1)
    dealt = foe.max_hp - foe.hp
    assert dealt > 0
    assert user.hp == user.max_hp // 2 + (max(1, dealt // items.SHELL_BELL_FRACTION) if heals else 0)
    assert action.attacker_item == (items.SHELL_BELL if heals else "")


SNARL, HYPER_VOICE = attack(555), attack(304)


@pytest.mark.parametrize(("move", "ability", "sprays"), [
    (SNARL, "sheer-force", False),
    (SNARL, None, True),
    (HYPER_VOICE, "sheer-force", True),
])
def test_throat_spray_stays_unused_when_sheer_force_drops_the_sound_moves_added_effect(move, ability, sprays):
    user, foe, arena = facing("throat-spray", ability)
    user.combatant = replace(user.combatant, moves=(move,))
    user.pp = [move.pp]
    battle._act(1, 0, (user, foe), 0, arena.weather, random.Random(1), arena)
    assert foe.hp < foe.max_hp
    assert (user.item, user.stages["special_attack"]) == ((None, 1) if sprays else ("throat-spray", 0))


def test_big_root_shows_its_boost_on_a_drain_that_hit_a_substitute():
    user, foe, arena = facing(items.BIG_ROOT, foe_volatiles=SUBSTITUTE)
    user.hp = 1
    action = resolve(user, foe, GIGA_DRAIN, arena, seed=1)
    taken = DOLL - foe.volatiles["substitute"]
    assert user.hp == 1 + int(max(1, taken // 2) * items.BIG_ROOT_MULTIPLIER)
    assert action.drained and action.attacker_item == items.BIG_ROOT


def facing(item, ability=None, foe_types=("normal",), foe_ability=None, foe_forms=(), foe_volatiles=None):
    """A level 100 holder of `item` (side 0) against a bulky foe (side 1)."""
    arena = _Arena()
    user = put(mon("보유자", level=100, hp=255), arena, item=item, ability=ability)
    foe = put(replace(mon("상대", types=foe_types, hp=255, defense=255), forms=foe_forms), arena, 1,
              ability=foe_ability)
    foe.volatiles.update(foe_volatiles or {})
    return user, foe, arena


def test_expert_belt_boosts_only_super_effective_hits():
    belt, plain = mon("띠", items.EXPERT_BELT), mon("맨몸")
    grass, water = mon("풀", types=("grass",)), mon("물", types=("water",))
    assert damage(belt, grass, EMBER, 2.0) == pytest.approx(damage(plain, grass, EMBER, 2.0) * 1.2)
    assert damage(belt, water, EMBER, 0.5) == damage(plain, water, EMBER, 0.5)


def test_charcoal_boosts_only_fire_moves():
    coal, plain, foe = mon("목탄", items.CHARCOAL), mon("맨몸"), mon("상대")
    assert damage(coal, foe, EMBER) == pytest.approx(damage(plain, foe, EMBER) * 1.2)
    assert damage(coal, foe, SURF) == damage(plain, foe, SURF)


def test_unknown_item_changes_nothing():
    sides = (mon("A", moves=(TACKLE, EMBER)), mon("B", moves=(TACKLE,)))
    assert simulate((replace(sides[0], item="venusaurite"), sides[1]), seed=7) == simulate(sides, seed=7)


def test_narration_names_the_item_and_its_triggers():
    strong = mon("강함", level=100, attack=255, speed=255)
    weak = mon("띠", items.FOCUS_SASH, level=5, speed=1)
    sides = ((strong,), (weak,))
    result = simulate((strong, weak), seed=5)
    assert battle_card(("<@UA>", "<@UB>"), sides, result).columns[1].splitlines()[1].startswith("띠 Lv5 @기합의띠")
    assert battle_log(result)[0].splitlines()[1:] == ["🔵 강함 › 몸통박치기 → 띠 4% @기합의띠", "🔴 띠 › 몸통박치기 → 강함 99%"]
    heal = ItemHeal(2, 1, "먹보", items.LEFTOVERS, 80)
    life_orb = Action(1, 0, "구슬", "상대", "몸통박치기", attacker_item=items.LIFE_ORB, attacker_hp=90, defender_hp=50)
    lines = battle_log(replace(result, events=[life_orb, heal], winner=0))
    assert lines == ("*1턴*\n🔵 구슬 › 몸통박치기 → 상대 50% @생명의구슬", "*2턴*\n🔴 먹보 @먹다남은음식 80%")


def test_upload_keeps_a_normalized_held_item_and_ignores_junk():
    kept = _party({"pokemon_id": 25, "level": 30, "held_item": " Leftovers "})
    assert kept[0]["held_item"] == "leftovers"
    for junk in (None, "", "  ", 5, ["x"], "x" * 41):
        assert "held_item" not in _party({"pokemon_id": 25, "level": 30, "held_item": junk})[0]
    with pytest.raises(PartyError):
        _party({"pokemon_id": 25, "level": 30, "held_item": "leftovers"}, {"level": 3})
