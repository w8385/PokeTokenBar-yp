from dataclasses import replace

import pytest

from ypoke import gym_battle, gym_data, items, tera_forms
from ypoke.battle import (
    Action, BaseStats, Change, Combatant, FormShift, MegaEvolution, MegaForm, Move, SendOut, simulate,
)
from ypoke.combatants import combatant
from ypoke.gym_battle import GymBattles
from ypoke.narration import battle_turns

IVS = BaseStats(15, 15, 15, 15, 15, 15)
TACKLE = Move("몸통박치기", "normal", 40, physical=True, accuracy=100)
GRASS_HIT = Move("잎날가르기", "grass", 60, physical=True, accuracy=100)
OGERPON_BASE = {"hp": 80, "attack": 120, "defense": 84, "special_attack": 60, "special_defense": 96, "speed": 110}
TERASTAL_BASE = {"hp": 95, "attack": 95, "defense": 110, "special_attack": 105, "special_defense": 110, "speed": 85}
STELLAR_BASE = {"hp": 160, "attack": 105, "defense": 110, "special_attack": 130, "special_defense": 110, "speed": 85}
PLAIN = {"hp": 60, "attack": 60, "defense": 60, "special_attack": 60, "special_defense": 60, "speed": 60}
FORMS = {
    1017: ("오거폰", ["grass"], OGERPON_BASE),
    10273: ("오거폰", ["grass", "water"], OGERPON_BASE),
    10274: ("오거폰", ["grass", "fire"], OGERPON_BASE),
    10275: ("오거폰", ["grass", "rock"], OGERPON_BASE),
    1024: ("테라파고스", ["normal"], {**TERASTAL_BASE, "hp": 90, "attack": 65, "defense": 85, "special_attack": 65,
                                      "special_defense": 85, "speed": 60}),
    10276: ("테라파고스-테라스탈", ["normal"], TERASTAL_BASE),
    10277: ("테라파고스-스텔라", ["normal"], STELLAR_BASE),
    1: ("이상해씨", ["grass", "poison"], PLAIN),
}


class FakePokeAPI:
    def pokemon(self, pokemon_id):
        name, types, base = FORMS.get(pokemon_id, (f"#{pokemon_id}", ["normal"], PLAIN))
        return {"name_ko": name, "types": types, "base": base}

    def attacking_moves(self, pokemon_id, level, machine_ids=()):
        return []

    def can_evolve(self, pokemon_id):
        return False


def member(pokemon_id, item=None, **extra):
    data = {"pokemon_id": pokemon_id, "level": 50, "ivs": {}, "shiny": False, **extra}
    if item is not None:
        data["held_item"] = item
    return data


def build(pokemon_id, item=None, **extra):
    return combatant(FakePokeAPI(), member(pokemon_id, item, **extra))


def mon(name, item=None, speed=80, moves=(TACKLE,), **fields):
    return Combatant(name=name, level=50, types=("normal",), base=BaseStats(60, 60, 60, 60, 60, speed), ivs=IVS,
                     moves=moves, item=item, **fields)


STELLAR = MegaForm(types=("normal",), base=BaseStats(160, 105, 110, 130, 110, 85), form_id=10277, kind="stellar")
MEGA = MegaForm(types=("fire", "dragon"), base=BaseStats(78, 130, 111, 130, 85, 100), ability="단단한발톱")
STRONG = replace(mon("강함", speed=200), base=BaseStats(100, 255, 100, 255, 100, 200))


def shifts(events, kind=None):
    return [event for event in events if isinstance(event, FormShift) and kind in (None, event.kind)]


def test_the_mask_slugs_match_the_mask_table():
    assert set(tera_forms.MASKS) == set(items.OGERPON_MASKS)
    assert all(slug in items.ITEM_NAMES for slug in items.OGERPON_MASKS)
    assert items.STELLAR_CRYSTAL in items.ITEM_NAMES


@pytest.mark.parametrize("slug,types", [
    ("teal-mask", ("grass",)), ("wellspring-mask", ("grass", "water")),
    ("hearthflame-mask", ("grass", "fire")), ("cornerstone-mask", ("grass", "rock")),
])
def test_an_ogerpon_mask_sets_the_form_type_and_keeps_the_species_name_and_stats(slug, types):
    fighter = build(1017, slug)
    assert (fighter.types, fighter.name, fighter.item) == (types, "오거폰", slug)
    assert fighter.base.attack == 120 and fighter.mega is None and fighter.tera is False


def test_a_mask_keeps_the_members_own_ability_and_nickname():
    fighter = build(1017, "cornerstone-mask", ability="defiant", name="초록이")
    assert (fighter.ability, fighter.name) == ("defiant", "초록이")


@pytest.mark.parametrize("slug", ["teal-mask", "wellspring-mask", "hearthflame-mask", "cornerstone-mask",
                                  "stellar-crystal"])
def test_masks_and_the_crystal_on_the_wrong_species_do_nothing(slug):
    fighter = build(1, slug)
    assert (fighter.item, fighter.mega, fighter.types, fighter.tera) == (None, None, ("grass", "poison"), False)
    assert build(1017, "stellar-crystal").item is None
    assert build(1024, "teal-mask").item is None


def test_terapagos_enters_every_battle_in_terastal_form_without_an_item():
    fighter = build(1024)
    assert (fighter.name, fighter.tera, fighter.mega) == ("테라파고스", True, None)
    assert (fighter.base.hp, fighter.base.defense) == (95, 110)
    assert shifts(simulate(((fighter,), (mon("상대"),)), seed=3).events) == [
        FormShift(1, 0, "테라파고스", "terastal", 10276)]


def test_the_crystal_gives_terapagos_the_stellar_form_to_enter_with():
    fighter = build(1024, "stellar-crystal")
    assert fighter.mega == STELLAR
    events = simulate(((fighter,), (mon("상대"),)), seed=3).events
    assert shifts(events) == [FormShift(1, 0, "테라파고스", "stellar", 10277)]
    assert not any(isinstance(event, MegaEvolution) for event in events)


def test_the_gym_path_builds_masks_and_the_crystal_the_same_way(monkeypatch):
    seen = []

    class Reached(Exception):
        pass

    def capture(sides, seed, starts, finale, unlimited_megas):
        seen.extend(sides[0])
        raise Reached

    monkeypatch.setattr(gym_battle, "simulate", capture)
    members = [member(1017, "hearthflame-mask"), member(1024, "stellar-crystal"), member(1, "teal-mask")]
    with pytest.raises(Reached):
        GymBattles(FakePokeAPI()).battle("kanto-1", members)
    assert [(fighter.types, fighter.item) for fighter in seen] == [
        (("grass", "fire"), "hearthflame-mask"), (("normal",), "stellar-crystal"), (("grass", "poison"), None)]
    assert seen[1].mega == STELLAR


def test_a_champion_gives_its_finale_a_second_mega_slot_and_only_a_hidden_boss_has_no_limit(monkeypatch):
    seen = {}

    class Reached(Exception):
        pass

    def capture(sides, seed, starts, finale, unlimited_megas):
        seen[len(seen)] = (len(sides[1]), finale, unlimited_megas)
        raise Reached

    monkeypatch.setattr(gym_battle, "simulate", capture)
    monkeypatch.setattr(gym_battle, "combatant", lambda pokeapi, member: member["pokemon_id"])
    for battle_id in ("kanto-1", "kanto-champion", "kanto-hidden"):
        with pytest.raises(Reached):
            GymBattles(FakePokeAPI()).battle(battle_id, [member(1)])
    assert seen == {0: (3, None, False), 1: (7, 6, False), 2: (len(gym_data.HIDDEN_TEAMS["kanto"]), 6, True)}


def test_a_mask_raises_every_move_by_a_fifth_but_not_a_confusion_hit():
    assert items.damage_multiplier("teal-mask", "grass", 1.0) == items.BOOST_MULTIPLIER
    assert items.damage_multiplier("cornerstone-mask", "normal", 1.0) == items.BOOST_MULTIPLIER
    assert items.damage_multiplier("wellspring-mask", None, 1.0) == 1.0
    assert items.damage_multiplier("stellar-crystal", "grass", 1.0) == 1.0


def test_a_masked_ogerpon_hits_harder_than_the_same_ogerpon_without_it():
    def first_hit(item):
        fighter = mon("오거폰", item, moves=(TACKLE,))
        events = simulate(((fighter,), (mon("상대"),)), seed=5).events
        return next(event for event in events if isinstance(event, Action) and event.side == 0)

    assert first_hit("hearthflame-mask").defender_hp < first_hit(None).defender_hp


@pytest.mark.parametrize("slug,stat", [
    ("teal-mask", "speed"), ("wellspring-mask", "special_defense"),
    ("hearthflame-mask", "attack"), ("cornerstone-mask", "defense"),
])
def test_each_mask_raises_its_stat_one_stage_on_entry(slug, stat):
    events = simulate(((mon("오거폰", slug),), (mon("상대"),)), seed=3).events
    assert shifts(events, "mask") == [
        FormShift(1, 0, "오거폰", "mask", tera_forms.MASKS[slug][0], Change(0, "오거폰", stat, 1))]


def test_the_teal_masks_speed_stage_decides_who_moves_first():
    def mover(item):
        events = simulate(((mon("오거폰", item, speed=80),), (mon("상대", speed=100),)), seed=3).events
        return next(event.side for event in events if isinstance(event, Action))

    assert mover(None) == 1
    assert mover("teal-mask") == 0


def test_the_mask_boost_fires_again_when_the_holder_is_sent_out_mid_battle():
    team = (replace(mon("첫째"), level=5), mon("오거폰", "hearthflame-mask"))
    events = simulate((team, (STRONG,)), seed=3).events
    index = next(i for i, event in enumerate(events) if isinstance(event, FormShift))
    assert isinstance(events[index - 1], SendOut)
    assert events[index].change == Change(0, "오거폰", "attack", 1)
    assert len(shifts(events)) == 1


def test_a_mask_does_not_use_up_the_mega_slot():
    team = (mon("오거폰", "teal-mask"), mon("메가", mega=MEGA))
    events = simulate((team, (STRONG,)), seed=3).events
    assert [event.pokemon for event in events if isinstance(event, MegaEvolution)] == ["메가"]
    assert len(shifts(events, "mask")) == 1


def test_only_the_first_of_a_mega_holder_and_a_stellar_holder_transforms():
    mega_first = (mon("메가", mega=MEGA), mon("테라파고스", "stellar-crystal", mega=STELLAR, tera=True))
    events = simulate((mega_first, (STRONG,)), seed=3).events
    assert [event.pokemon for event in events if isinstance(event, MegaEvolution)] == ["메가"]
    assert [event.kind for event in shifts(events)] == ["terastal"]

    stellar_first = (mon("테라파고스", "stellar-crystal", mega=STELLAR, tera=True), mon("메가", mega=MEGA))
    events = simulate((stellar_first, (STRONG,)), seed=3).events
    assert not any(isinstance(event, MegaEvolution) for event in events)
    assert [event.kind for event in shifts(events)] == ["stellar"]


def test_a_foe_finale_gets_its_own_mega_after_one_of_the_first_members_used_the_teams():
    foes = (mon("메가1", mega=MEGA), mon("메가2", mega=MEGA), mon("스텔라", "stellar-crystal", mega=STELLAR, tera=True))

    def foe_forms(finale):
        events = simulate(((STRONG,), foes), seed=3, finale=finale).events
        return [event.pokemon for event in events if event.side == 1 and isinstance(event, MegaEvolution)] + \
            [event.pokemon for event in shifts(events, "stellar") if event.side == 1]

    assert foe_forms(None) == ["메가1"]
    assert foe_forms(1) == ["메가1", "메가2"]
    assert foe_forms(2) == ["메가1", "스텔라"]


def test_the_player_keeps_one_mega_per_battle_when_the_foe_has_a_finale():
    team = (mon("메가1", mega=MEGA), mon("메가2", mega=MEGA))
    events = simulate((team, (STRONG,)), seed=3, finale=1).events
    assert [event.pokemon for event in events if isinstance(event, MegaEvolution)] == ["메가1"]


def test_each_side_gets_its_own_stellar_form():
    holder = mon("테라파고스", "stellar-crystal", mega=STELLAR, tera=True)
    events = simulate(((holder,), (replace(holder, name="상대테라"),)), seed=3).events
    assert sorted((event.side, event.kind) for event in shifts(events)) == [(0, "stellar"), (1, "stellar")]


def test_without_these_items_the_battle_has_no_form_shifts():
    assert shifts(simulate(((mon("가"),), (mon("나"),)), seed=9).events) == []


def test_the_log_announces_the_mask_and_the_forms_in_one_line_each():
    mask = simulate(((mon("오거폰", "hearthflame-mask"),), (mon("상대"),)), seed=3)
    lines = battle_turns(mask)[0][1]
    assert lines[0] == "🔵 오거폰의 가면이 빛났다! 자신 공격↑"
    stellar = simulate(((mon("테라파고스", "stellar-crystal", mega=STELLAR, tera=True),), (mon("상대"),)), seed=3)
    assert battle_turns(stellar)[0][1][0] == "🔵 테라파고스는 스텔라폼이 되었다!"
    terastal = simulate(((mon("테라파고스", tera=True),), (mon("상대"),)), seed=3)
    assert battle_turns(terastal)[0][1][0] == "🔵 테라파고스는 테라스탈폼이 되었다!"


@pytest.mark.parametrize("name, line", [
    ("별이", "🔵 별이는 스텔라폼이 되었다!"),
    ("별빛", "🔵 별빛은 스텔라폼이 되었다!"),
    ("Star", "🔵 Star은(는) 스텔라폼이 되었다!"),
])
def test_the_form_line_uses_the_members_name_with_the_matching_particle(name, line):
    stellar = simulate(((mon(name, "stellar-crystal", mega=STELLAR, tera=True),), (mon("상대"),)), seed=3)
    assert battle_turns(stellar)[0][1][0] == line
