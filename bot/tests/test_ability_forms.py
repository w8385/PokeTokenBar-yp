import random
from dataclasses import replace

import pytest
from attacks import attack
from test_battle import mon
from test_held_items_more import FixedRng

from ypoke import abilities, battle, narration
from ypoke.battle import BaseStats, FormShift, MegaForm, _Arena, _Team
from ypoke.effects import hooks

TACKLE, SURF, EMBER, GROWL = attack(33), attack(57), attack(52), attack(45)
KINGS_SHIELD, AURA_WHEEL, CLOSE_COMBAT, LICK = attack(588), attack(783), attack(370), attack(122)
GIGA_DRAIN, DOUBLE_EDGE = attack(202), attack(38)
FORM_BASE = BaseStats(80, 150, 50, 150, 50, 100)
NO_CRIT = 0.5
WEATHER_FORMS = ("sunny", "rainy", "snowy")
BOTH_FACES = ("noice", "ice-face")
PREY = ("gulping", "gorging")


def holder(ability, *kinds, level=50, moves=(TACKLE,), item=None):
    """The holder (side 0) has a dragon-type form of each kind; the foe (side 1) hits hard."""
    arena = _Arena()
    forms = tuple(MegaForm(("dragon",), FORM_BASE, form_id=10000 + n, kind=kind) for n, kind in enumerate(kinds))
    user = replace(mon("보유자", ("normal",), level=level, moves=moves), ability=ability, forms=forms, item=item)
    foe = mon("상대", ("normal",), attack=200, special_attack=200)
    teams = (_Team((user,), arena=arena), _Team((foe,), arena=arena, side=1))
    arena.teams = teams
    return teams[0].active, teams[1].active, arena


def ended(fighter):
    return hooks.ability(fighter, "end_of_turn", fighter, fighter.side, 1, random.Random(0))


def updated(fighter):
    return hooks.ability(fighter, "on_update", fighter, fighter.side, 1)


def entered(fighter, foe, arena):
    return hooks.ability(fighter, "on_entry", fighter, foe, fighter.side, arena.weather)


def strike(user, target, arena, move=TACKLE):
    user.combatant = replace(user.combatant, moves=(move,))
    battle._resolve(1, user.side, (user, target) if user.side == 0 else (target, user), 0, arena.weather,
                    FixedRng(NO_CRIT), arena)


def kind_of(event):
    return event.kind if event is not None else None


@pytest.mark.parametrize(("kinds", "shown"), [(("zen",), "zen"), ((), None)])
def test_zen_mode_takes_its_form_at_half_hp_and_leaves_it_above(kinds, shown):
    fighter, _, _ = holder("zen-mode", *kinds)
    assert ended(fighter) is None
    fighter.hp = fighter.max_hp // 2
    assert kind_of(ended(fighter)) == shown
    if shown:
        assert fighter.combatant.types == ("dragon",)
        fighter.hp = fighter.max_hp
        assert kind_of(ended(fighter)) == "base"
        assert fighter.combatant.types == ("normal",)


@pytest.mark.parametrize(("level", "kinds", "shown"), [
    (50, ("school",), "school"), (10, ("school",), None), (50, (), None),
])
def test_schooling_schools_from_level_20_above_a_quarter_of_its_hp(level, kinds, shown):
    fighter, foe, arena = holder("schooling", *kinds, level=level)
    assert kind_of(entered(fighter, foe, arena)) == shown
    if shown:
        fighter.hp = fighter.max_hp // 4
        assert kind_of(ended(fighter)) == "base"


@pytest.mark.parametrize(("kinds", "shown"), [(("blade",), ["blade", None, "base"]), ((), [None, None, None])])
def test_stance_change_draws_the_blade_to_attack_and_sheathes_it_for_kings_shield(kinds, shown):
    fighter, _, _ = holder("stance-change", *kinds)
    shifts = [hooks.ability(fighter, "before_move", move, fighter, 0, 1) for move in (TACKLE, GROWL, KINGS_SHIELD)]
    assert [kind_of(shift) for shift in shifts] == shown


@pytest.mark.parametrize(("kinds", "share", "blocked"), [(("core",), 1, True), (("core",), 2, False), ((), 1, False)])
def test_shields_down_keeps_status_out_until_its_core_shows(kinds, share, blocked):
    fighter, foe, arena = holder("shields-down", *kinds)
    fighter.hp = fighter.max_hp // share
    entered(fighter, foe, arena)
    assert hooks.ability(fighter, "blocks_ailment", "paralysis", fighter, default=False) == blocked


@pytest.mark.parametrize(("kinds", "completed"), [(("complete",), True), ((), False)])
def test_power_construct_completes_once_at_half_hp_for_the_rest_of_the_battle(kinds, completed):
    fighter, _, _ = holder("power-construct", *kinds)
    assert ended(fighter) is None
    fighter.hp = fighter.max_hp // 2
    assert (ended(fighter) is not None) == completed
    assert ended(fighter) is None
    fighter.leave()
    assert (fighter.combatant.types == ("dragon",)) == completed


@pytest.mark.parametrize(("kinds", "disguised"), [(("busted",), True), ((), False)])
def test_disguise_takes_the_first_hit_for_an_eighth_of_its_hp(kinds, disguised):
    fighter, foe, arena = holder("disguise", *kinds)
    strike(foe, fighter, arena)
    assert (fighter.max_hp - fighter.hp == fighter.max_hp // abilities.DISGUISE_SHARE) == disguised
    assert [event.kind for event in arena.log if isinstance(event, FormShift)] == (["busted"] if disguised else [])
    before = fighter.hp
    strike(foe, fighter, arena)
    assert before - fighter.hp > fighter.max_hp // abilities.DISGUISE_SHARE
    assert sum(isinstance(event, FormShift) for event in arena.log) == disguised


@pytest.mark.parametrize(("ability", "kinds", "move"), [
    ("disguise", ("busted",), GIGA_DRAIN), ("disguise", ("busted",), DOUBLE_EDGE), ("ice-face", BOTH_FACES, DOUBLE_EDGE),
])
def test_a_hit_the_holders_form_takes_neither_drains_nor_recoils(ability, kinds, move):
    fighter, foe, arena = holder(ability, *kinds)
    foe.hp = foe.max_hp // 2
    strike(foe, fighter, arena, move)
    assert fighter.combatant.types == ("dragon",) and foe.hp == foe.max_hp // 2


@pytest.mark.parametrize("move", [GIGA_DRAIN, DOUBLE_EDGE])
def test_a_hit_endured_at_one_hp_neither_drains_nor_recoils(move):
    fighter, foe, arena = holder(None)
    fighter.hp, fighter.volatiles["endure"] = 1, True
    foe.hp = foe.max_hp // 2
    strike(foe, fighter, arena, move)
    assert fighter.hp == 1 and foe.hp == foe.max_hp // 2


@pytest.mark.parametrize(("move", "share"), [(GIGA_DRAIN, lambda doll: doll // 2),
                                             (DOUBLE_EDGE, lambda doll: -(doll * 33 // 100))])
def test_drain_and_recoil_count_what_a_substitute_took_up_to_its_hp(move, share):
    fighter, foe, arena = holder(None)
    foe.hp = before = foe.max_hp // 2
    doll = fighter.volatiles["substitute"] = fighter.max_hp // 4
    strike(foe, fighter, arena, move)
    assert "substitute" not in fighter.volatiles and fighter.hp == fighter.max_hp
    assert foe.hp - before == share(doll)


@pytest.mark.parametrize(("move", "kinds", "blocked"), [
    (TACKLE, BOTH_FACES, True), (SURF, BOTH_FACES, False), (TACKLE, (), False),
])
def test_ice_face_takes_the_first_physical_hit_and_snow_freezes_it_back(move, kinds, blocked):
    fighter, foe, arena = holder("ice-face", *kinds)
    strike(foe, fighter, arena, move)
    assert (fighter.hp == fighter.max_hp) == blocked
    arena.weather.kind = "snow"
    assert kind_of(updated(fighter)) == ("ice-face" if blocked else None)


@pytest.mark.parametrize(("kinds", "share", "caught"), [(PREY, 1, "gulping"), (PREY, 2, "gorging"), ((), 1, None)])
def test_gulp_missile_catches_prey_with_surf_and_spits_it_at_the_next_attacker(kinds, share, caught):
    fighter, foe, arena = holder("gulp-missile", *kinds)
    fighter.hp = fighter.max_hp // share
    assert kind_of(hooks.ability(fighter, "before_move", SURF, fighter, 0, 1)) == caught
    strike(foe, fighter, arena)
    assert (foe.max_hp - foe.hp == foe.max_hp // abilities.GULP_SHARE) == (caught is not None)
    assert (foe.stages["defense"], foe.status) == {
        "gulping": (-1, None), "gorging": (0, "paralysis"), None: (0, None)}[caught]


@pytest.mark.parametrize(("kinds", "wheel"), [(("hangry",), "dark"), ((), "electric")])
def test_hunger_switch_flips_each_turn_and_turns_aura_wheel_dark(kinds, wheel):
    fighter, _, _ = holder("hunger-switch", *kinds, moves=(AURA_WHEEL,))
    ended(fighter)
    assert fighter.combatant.moves[0].type == wheel
    ended(fighter)
    assert fighter.combatant.moves[0].type == "electric"


@pytest.mark.parametrize(("weather", "kinds", "shown"), [
    ("sun", WEATHER_FORMS, "sunny"), ("rain", WEATHER_FORMS, "rainy"), ("hail", WEATHER_FORMS, "snowy"),
    (None, WEATHER_FORMS, None), ("sun", (), None),
])
def test_forecast_takes_the_form_of_the_weather(weather, kinds, shown):
    fighter, _, arena = holder("forecast", *kinds)
    arena.weather.kind = weather
    assert kind_of(updated(fighter)) == shown


@pytest.mark.parametrize(("kinds", "boost"), [(("sunshine",), abilities.FLOWER_GIFT_BOOST), ((), 1.0)])
def test_flower_gift_blooms_in_the_sun(kinds, boost):
    fighter, _, arena = holder("flower-gift", *kinds)
    arena.weather.kind = "sun"
    updated(fighter)
    assert hooks.ability(fighter, "modify_stat", "attack", "sun", fighter, default=1.0) == boost
    assert hooks.ability(fighter, "modify_stat", "defense", "sun", fighter, default=1.0) == 1.0


@pytest.mark.parametrize(("switched", "kinds", "hero"), [(True, ("hero",), True), (False, ("hero",), False),
                                                         (True, (), False)])
def test_zero_to_hero_comes_back_a_hero_after_switching_out_by_its_own_move(switched, kinds, hero):
    fighter, foe, arena = holder("zero-to-hero", *kinds)
    if switched:
        hooks.ability(fighter, "on_switch_out", fighter, 0)
    fighter.leave()
    assert (entered(fighter, foe, arena) is not None) == hero
    fighter.leave()
    assert (fighter.combatant.types == ("dragon",)) == hero


def test_mimicry_takes_the_terrains_type_and_drops_it_with_the_terrain():
    fighter, _, arena = holder("mimicry")
    assert updated(fighter) is None
    arena.terrain = "electric-terrain"
    assert updated(fighter).effect == "retype"
    assert fighter.combatant.types == ("electric",)
    arena.terrain = None
    assert updated(fighter).effect == "retype-back"
    assert fighter.combatant.types == ("normal",)


@pytest.mark.parametrize(("substitute", "types"), [(False, ("fire",)), (True, ("normal",))])
def test_color_change_takes_the_type_of_the_move_that_hit_it(substitute, types):
    fighter, foe, arena = holder("color-change")
    if substitute:
        fighter.volatiles["substitute"] = fighter.max_hp
    strike(foe, fighter, arena, EMBER)
    assert fighter.combatant.types == types


@pytest.mark.parametrize(("item", "types"), [("fire-memory", ("fire",)), ("leftovers", ("normal",)), (None, ("normal",))])
def test_rks_system_takes_the_type_of_its_memory(item, types):
    fighter, foe, arena = holder("rks-system", item=item)
    entered(fighter, foe, arena)
    assert fighter.combatant.types == types


@pytest.mark.parametrize(("ability", "lost", "move", "multiplier"), [
    ("tera-shell", 0, CLOSE_COMBAT, 0.5), ("tera-shell", 0, EMBER, 0.5), ("tera-shell", 1, CLOSE_COMBAT, 2.0),
    ("tera-shell", 0, LICK, 0.0), (None, 0, CLOSE_COMBAT, 2.0),
])
def test_tera_shell_makes_every_hit_not_very_effective_at_full_hp(ability, lost, move, multiplier):
    fighter, _, _ = holder(ability)
    fighter.hp -= lost
    assert battle._multiplier(move, fighter) == multiplier


def test_teraform_zero_clears_the_weather_and_terrain_the_first_time_it_enters():
    fighter, foe, arena = holder("teraform-zero")
    arena.weather.kind, arena.terrain = "rain", "electric-terrain"
    assert entered(fighter, foe, arena).effect == "zero"
    assert (arena.weather.kind, arena.terrain) == (None, None)
    arena.weather.kind = "rain"
    assert entered(fighter, foe, arena) is None
    assert arena.weather.kind == "rain"


def test_battle_bond_raises_its_stats_after_its_first_knockout_only():
    fighter, foe, arena = holder("battle-bond")
    raised = ("attack", "special_attack", "speed")
    foe.hp = 1
    strike(fighter, foe, arena)
    assert [fighter.stages[stat] for stat in raised] == [1, 1, 1]
    foe.hp = 1
    strike(fighter, foe, arena)
    assert [fighter.stages[stat] for stat in raised] == [1, 1, 1]


FORM_KINDS = sorted({kind for species in abilities.FORMS.values() for kinds in species.values() for kind in kinds}
                    | {"base"})


@pytest.mark.parametrize("kind", FORM_KINDS)
def test_every_ability_form_reads_as_a_line(kind):
    line = narration._form_line(FormShift(1, 0, "보유자", kind, None))
    assert line.endswith(f"{narration.FORM_CAPTION[kind]}{narration._subject_particle(narration.FORM_CAPTION[kind])} 되었다!")


def test_a_form_caption_takes_the_subject_particle_of_its_last_syllable():
    assert narration._form_line(FormShift(1, 0, "보유자", "blade", None)).endswith("보유자는 블레이드폼이 되었다!")
    assert narration._form_line(FormShift(1, 0, "보유자", "hangry", None)).endswith("배고픈모양이 되었다!")
    assert narration._subject_particle("나이스페이스") == "가"
