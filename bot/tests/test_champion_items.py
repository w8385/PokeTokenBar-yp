import random
from dataclasses import replace

import pytest

from ypoke import foe_items, foe_moves, items, tera_forms
from ypoke.battle import (
    AbilityTrigger, BaseStats, BattleResult, Carry, Combatant, FormShift, MegaEvolution, Move, StatusDamage,
    WeatherEnd, _act, _Fighter, _unrolled_damage, _Weather, simulate,
)
from ypoke.combatants import combatant
from ypoke.foe_moves import FoeMove
from ypoke.move_effects import DRAGON_ASCENT, JUDGMENT, PUNCH_MOVES
from ypoke.narration import battle_turns

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
ICE_BEAM = Move("냉동빔", "ice", 90, physical=False, accuracy=100)
FIRE_PUNCH = Move("불꽃펀치", "fire", 75, physical=True, accuracy=100, id=7)
FLAMETHROWER = Move("화염방사", "fire", 90, physical=False, accuracy=100, id=53)
SHADOW_BALL = Move("섀도볼", "ghost", 80, physical=False, accuracy=100)
DRAGON_PULSE = Move("용의파동", "dragon", 85, physical=False, accuracy=100)
THUNDERBOLT = Move("10만볼트", "electric", 90, physical=False, accuracy=100)
ROCK_SLIDE = Move("스톤샤워", "rock", 75, physical=True, accuracy=100)
RAIN_DANCE = Move("비바라기", "water", 0, physical=False, weather="rain")
PLAIN = {"hp": 80, "attack": 80, "defense": 80, "special_attack": 80, "special_defense": 80, "speed": 80}
ORIGIN = {"hp": 150, "attack": 120, "defense": 100, "special_attack": 120, "special_defense": 100, "speed": 90}
MEGA_RAYQUAZA = {"hp": 105, "attack": 180, "defense": 100, "special_attack": 180, "special_defense": 100, "speed": 115}
FORMS = {
    487: ("기라티나", ["ghost", "dragon"], PLAIN, None),
    10007: ("기라티나", ["ghost", "dragon"], ORIGIN, "levitate"),
    483: ("디아루가", ["steel", "dragon"], PLAIN, None),
    10245: ("디아루가", ["steel", "dragon"], ORIGIN, "pressure"),
    493: ("아르세우스", ["normal"], PLAIN, None),
    384: ("레쿠쟈", ["dragon", "flying"], PLAIN, None),
    10079: ("레쿠쟈", ["dragon", "flying"], MEGA_RAYQUAZA, "delta-stream"),
}


def test_a_resist_berry_halves_the_first_super_effective_hit_of_its_type_then_is_gone():
    plain, held = hit(ICE_BEAM, None), hit(ICE_BEAM, "yache-berry")
    assert held.defender_item == "yache-berry" and held.item is None
    assert held.dealt == pytest.approx(plain.dealt / 2, abs=1)
    again = hit(ICE_BEAM, None, defender=held.fighter)
    assert again.dealt == plain.dealt


def test_a_resist_berry_stays_on_a_hit_that_is_not_super_effective():
    plain, held = hit(TACKLE, None, ("dragon",)), hit(TACKLE, "yache-berry", ("dragon",))
    resisted = hit(ICE_BEAM, "yache-berry", ("water",))
    assert held.dealt == plain.dealt and held.item == "yache-berry" and not held.defender_item
    assert resisted.item == "yache-berry"


def test_a_resist_berry_halves_only_the_first_hit_of_a_multi_hit_move():
    double = Move("더블윙", "ice", 40, physical=True, accuracy=100, min_hits=2, max_hits=2)
    plain, held = hit(double, None), hit(double, "yache-berry")
    assert held.item is None
    assert held.dealt == pytest.approx(plain.dealt * 3 / 4, abs=2)


def test_the_chilan_berry_halves_a_neutral_normal_hit():
    plain, held = hit(TACKLE, None, ("water",)), hit(TACKLE, "chilan-berry", ("water",))
    assert held.item is None and held.dealt == pytest.approx(plain.dealt / 2, abs=1)


def test_every_resist_berry_and_plate_has_a_name_and_a_type():
    for table in (items.RESIST_BERRIES, items.PLATES):
        assert all(slug in items.ITEM_NAMES for slug in table)
    assert len(items.RESIST_BERRIES) == 18 and len(set(items.RESIST_BERRIES.values())) == 18
    assert len(items.PLATES) == 17 and "normal" not in items.PLATES.values()


def test_the_punching_glove_list_holds_known_moves_and_boosts_only_them():
    assert all(foe_moves.move(move_id) is not None for move_id in PUNCH_MOVES)
    gloved = fighter(mon("격투가", item=items.PUNCHING_GLOVE))
    bare = fighter(mon("격투가"))
    target = fighter(mon("과녁"))
    assert damage(gloved, target, FIRE_PUNCH) / damage(bare, target, FIRE_PUNCH) == pytest.approx(1.1, rel=0.01)
    assert damage(gloved, target, FLAMETHROWER) == damage(bare, target, FLAMETHROWER)


def test_a_plate_boosts_its_type_on_any_holder():
    plated = fighter(mon("아무나", item="flame-plate"))
    bare = fighter(mon("아무나"))
    target = fighter(mon("과녁"))
    assert damage(plated, target, FLAMETHROWER) / damage(bare, target, FLAMETHROWER) == pytest.approx(1.2, rel=0.01)
    assert damage(plated, target, TACKLE) == damage(bare, target, TACKLE)


def test_a_plate_gives_arceus_and_judgment_its_type_but_no_one_else():
    arceus = build(493, "flame-plate", moves=[JUDGMENT, 33])
    assert arceus.types == ("fire",)
    assert [move.type for move in arceus.moves] == ["fire", "normal"]
    other = build(487, "flame-plate", moves=[JUDGMENT])
    assert other.types == ("ghost", "dragon") and other.moves[0].type == "normal"


def test_an_origin_item_gives_its_own_species_the_origin_forme_with_an_implemented_ability():
    giratina = build(487, "griseous-core")
    assert giratina.base.hp == ORIGIN["hp"] and giratina.ability == "levitate" and giratina.item == "griseous-core"
    dialga = build(483, "adamant-crystal", ability="sturdy")
    assert dialga.base.hp == ORIGIN["hp"] and dialga.ability == "sturdy"
    wrong = build(487, "adamant-crystal")
    assert wrong.item is None and wrong.base.hp == PLAIN["hp"]
    assert tera_forms.usable_item("lustrous-globe", 487) is None


def test_an_origin_item_boosts_dragon_and_its_second_type_and_shows_the_forme_on_entry():
    core = fighter(mon("기라티나", ("ghost", "dragon"), item="griseous-core"))
    bare = fighter(mon("기라티나", ("ghost", "dragon")))
    target = fighter(mon("과녁"))
    for move in (DRAGON_PULSE, SHADOW_BALL):
        assert damage(core, target, move) / damage(bare, target, move) == pytest.approx(1.2, rel=0.01)
    assert damage(core, target, THUNDERBOLT) == damage(bare, target, THUNDERBOLT)
    result = simulate((core.combatant, mon("상대")), seed=1)
    assert [(event.kind, event.form_id) for event in result.events if isinstance(event, FormShift)] == [
        ("origin", 10007)]
    assert "오리진폼" in "\n".join(line for _, lines in battle_turns(result) for line in lines)


def test_the_item_picker_fires_the_new_items_only_where_they_act():
    fist = FoeMove(7, "fire", True, 75, 100, 1.0)
    beam = FoeMove(58, "ice", False, 90, 100, 1.0)

    def holder(species_id=1, types=("grass",), moves=(fist,), weathers=()):
        return foe_items.Holder(species_id, types, PLAIN, moves, False, weathers)

    assert foe_items.fires("yache-berry", holder()) and not foe_items.fires("yache-berry", holder(types=("fire",)))
    assert foe_items.fires(items.PUNCHING_GLOVE, holder()) and not foe_items.fires(items.PUNCHING_GLOVE, holder(moves=(beam,)))
    assert foe_items.fires("flame-plate", holder()) and not foe_items.fires("flame-plate", holder(moves=(beam,)))
    assert foe_items.fires("flame-plate", holder(493, ("normal",), (beam,)))
    assert foe_items.fires("griseous-core", holder(487)) and not foe_items.fires("griseous-core", holder(483))
    assert foe_items.fires("smooth-rock", holder(weathers=("sandstorm",))) and not foe_items.fires("smooth-rock", holder())


def test_rayquaza_mega_evolves_through_dragon_ascent_without_a_stone():
    assert build(384, "life-orb", moves=[DRAGON_ASCENT]).mega.form_id == 10079
    assert build(384, "life-orb", moves=[DRAGON_ASCENT]).mega.ability_id == "delta-stream"
    assert build(384, "life-orb", moves=[33]).mega is None
    assert build(384, "gengarite", moves=[DRAGON_ASCENT]).mega is None


@pytest.mark.parametrize("side", [0, 1])
def test_mega_rayquaza_takes_its_sides_one_mega_slot(side):
    rayquaza = build(384, "life-orb", moves=[DRAGON_ASCENT])
    second = build(384, "leftovers", moves=[DRAGON_ASCENT])
    mine = (replace(rayquaza, name="첫째"), replace(second, name="둘째"))
    result = simulate(sides(mine, (mon("상대", hp=250),), side), seed=3)
    assert [event.pokemon for event in result.events if isinstance(event, MegaEvolution)] == ["첫째"]


@pytest.mark.parametrize("side", [0, 1])
def test_delta_stream_replaces_the_weather_that_is_up_with_strong_winds(side):
    kyogre = replace(mon("가이오가", ("water",)), ability="drizzle")
    rayquaza = replace(mon("레쿠쟈", ("dragon", "flying")), ability="delta-stream")
    result = simulate(sides((kyogre, rayquaza), (wall("상대"),), side), seed=4)
    weathers = [event.weather for event in result.events if isinstance(event, AbilityTrigger) and event.weather]
    assert weathers[:2] == ["rain", "strong-winds"]


def test_strong_winds_make_weather_moves_and_abilities_fail():
    weather = _Weather("strong-winds", 0)
    user, target = fighter(mon("기우", moves=(RAIN_DANCE,))), fighter(mon("과녁"))
    action = _act(1, 0, (user, target), 0, weather, random.Random(1))
    assert action.failed and weather.kind == "strong-winds"
    assert "실패 (🌀난기류)" in "\n".join(line for _, lines in battle_turns(result_of(action)) for line in lines)
    drought = replace(mon("그란돈", ("ground",)), ability="drought")
    rayquaza = replace(mon("레쿠쟈", ("dragon", "flying"), speed=150), ability="delta-stream")
    result = simulate((rayquaza, drought), seed=5)
    assert not any(event.weather == "sun" for event in result.events if isinstance(event, AbilityTrigger))


def test_strong_winds_make_ice_electric_and_rock_neutral_on_a_flying_type():
    rayquaza = fighter(mon("레쿠쟈", ("dragon", "flying")))
    winds, calm = _Weather("strong-winds", 0), _Weather()
    for move, calm_multiplier in ((ICE_BEAM, 4.0), (THUNDERBOLT, 1.0), (ROCK_SLIDE, 2.0)):
        user = fighter(mon("공격", moves=(move,)))
        assert _act(1, 0, (user, rayquaza), 0, calm, random.Random(1)).multiplier == calm_multiplier
        assert _act(1, 0, (user, rayquaza), 0, winds, random.Random(1)).multiplier == calm_multiplier / 2


def test_strong_winds_end_when_the_delta_stream_user_faints_and_the_log_says_so():
    rayquaza = replace(mon("레쿠쟈", ("dragon", "flying"), hp=20, defense=20), ability="delta-stream")
    result = simulate(((rayquaza, wall("후발")), (mon("상대", moves=(ICE_BEAM,), speed=200, attack=200),)), seed=6)
    ends = [event for event in result.events if isinstance(event, WeatherEnd)]
    assert [event.weather for event in ends] == ["strong-winds"]
    lines = "\n".join(line for _, lines in battle_turns(result) for line in lines)
    assert "난기류" in lines and "🌀난기류끝" in lines


def test_strong_winds_end_on_the_turn_the_delta_stream_user_faints_to_poison():
    rayquaza = replace(mon("레쿠쟈", ("dragon", "flying"), speed=150), ability="delta-stream")
    ground = Move("땅고르기", "ground", 60, physical=True, accuracy=100)
    foe = mon("상대", moves=(ground,), hp=250, defense=250)
    result = simulate(((rayquaza, wall("후발")), (foe,)), seed=8, carried=[Carry(5, "poison")])
    fainted = [event.turn for event in result.events if isinstance(event, StatusDamage) and event.fainted]
    assert fainted == [1]
    assert [event.turn for event in result.events if isinstance(event, WeatherEnd)] == fainted


def result_of(*events):
    return BattleResult(winner=0, turns=1, events=list(events), remaining=((), ()), statuses=((), ()))


def hit(move, item, types=("dragon", "flying"), defender=None):
    attacker = fighter(mon("공격", moves=(move,), attack=120))
    target = defender or fighter(mon("과녁", types, hp=250, defense=150, item=item))
    before = target.hp
    action = _act(1, 0, (attacker, target), 0, _Weather(), random.Random(7))
    return Hit(before - target.hp, target.item, action.defender_item, target)


class Hit:
    def __init__(self, dealt, item, defender_item, fighter):
        self.dealt, self.item, self.defender_item, self.fighter = dealt, item, defender_item, fighter


def damage(attacker, defender, move):
    return _unrolled_damage(attacker, defender, move, 1.0, None)


def fighter(combatant):
    return _Fighter.enter(combatant)


def mon(name, types=("normal",), moves=(TACKLE,), hp=80, attack=80, defense=80, speed=80, item=None):
    return Combatant(name=name, level=50, types=tuple(types), base=BaseStats(hp, attack, defense, attack, defense, speed),
                     ivs=IVS, moves=tuple(moves), item=item)


def wall(name):
    return mon(name, hp=250, attack=20, defense=250)


def sides(mine, theirs, side):
    return (mine, theirs) if side == 0 else (theirs, mine)


def build(pokemon_id, item=None, moves=(), **extra):
    member = {"pokemon_id": pokemon_id, "level": 50, "ivs": {}, "shiny": False, "moves": list(moves), **extra}
    if item is not None:
        member["held_item"] = item
    return combatant(FakePokeAPI(), member)


class FakePokeAPI:
    def mega_form(self, pokemon_id):
        ability = FORMS[pokemon_id][3]
        return {**self.pokemon(pokemon_id), "ability": ability, "ability_id": ability}

    def pokemon(self, pokemon_id):
        name, types, base, _ = FORMS.get(pokemon_id, (f"#{pokemon_id}", ["normal"], PLAIN, None))
        return {"name_ko": name, "types": types, "base": base}

    def attacking_moves(self, pokemon_id, level, machine_ids=()):
        return [move_dict(move_id) for move_id in (JUDGMENT, 33, DRAGON_ASCENT)]

    def can_evolve(self, pokemon_id):
        return False


def move_dict(move_id):
    return {
        "id": move_id, "name": f"m{move_id}", "type": "normal" if move_id != DRAGON_ASCENT else "flying",
        "power": 100, "damage_class": "special", "accuracy": 100, "pp": 10, "crit_rate": 0, "ailment": None,
        "ailment_chance": 0, "stat_changes": [], "stat_target": None, "stat_chance": 0, "priority": 0,
        "weather": None, "always_hits_in": [], "drain": 0, "min_hits": 1, "max_hits": 1,
    }
