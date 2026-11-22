from dataclasses import replace

import pytest
from attacks import attack
from test_battle import mon
from test_held_items_more import FixedRng
from test_tera_items import build

from ypoke import battle, narration
from ypoke.battle import Action, FormShift, _Arena, _Team, simulate
from ypoke.narration import battle_turns

TACKLE, FLAMETHROWER, SEISMIC_TOSS, DOUBLE_HIT = attack(33), attack(53), attack(69), attack(458)
NO_CRIT = 0.5


def struck(foe_ability, user_ability=None, move=TACKLE, lost=0):
    arena = _Arena()
    user = replace(mon("공격", ("normal",), moves=(move,)), ability=user_ability)
    foe = replace(mon("보유자", ("normal",), hp=200), ability=foe_ability)
    teams = (_Team((user,), arena=arena), _Team((foe,), arena=arena, side=1))
    arena.teams = teams
    target = teams[1].active
    target.hp -= lost
    before = target.hp
    action = battle._resolve(1, 0, (teams[0].active, target), 0, arena.weather, FixedRng(NO_CRIT), arena)
    return action, before - target.hp


def line(action):
    return narration._action_line(action, "▶")


@pytest.mark.parametrize(("ability", "tag"), [("multiscale", "[멀티스케일]"), ("shadow-shield", "[스펙터가드]")])
def test_a_hit_halved_at_full_hp_names_the_ability(ability, tag):
    action, taken = struck(ability)
    _, plain = struck(None)
    assert (action.ability, action.critical, taken) == (ability, False, pytest.approx(plain / 2, abs=1))
    assert line(action).endswith(tag)


@pytest.mark.parametrize("ability", ["multiscale", "shadow-shield"])
def test_a_hit_below_full_hp_is_not_halved_or_tagged(ability):
    action, taken = struck(ability, lost=1)
    _, plain = struck(None, lost=1)
    assert (action.ability, taken) == (None, plain)
    assert "[" not in line(action)


def test_mold_breaker_ignores_multiscale_so_the_hit_is_neither_halved_nor_tagged():
    action, taken = struck("multiscale", "mold-breaker")
    _, plain = struck(None, "mold-breaker")
    assert (action.ability, taken) == (None, plain)
    assert "[" not in line(action)


def test_shadow_shield_is_not_breakable_so_mold_breaker_still_gets_halved_and_tagged():
    action, taken = struck("shadow-shield", "mold-breaker")
    _, plain = struck(None, "mold-breaker")
    assert (action.ability, taken) == ("shadow-shield", pytest.approx(plain / 2, abs=1))


def test_set_damage_at_full_hp_is_not_tagged():
    action, taken = struck("multiscale", move=SEISMIC_TOSS)
    assert (action.ability, taken) == (None, 50)


@pytest.mark.parametrize(("user_ability", "multiplier", "ability"), [
    (None, 0.5, "tera-shell"), ("mold-breaker", 1.0, None), ("turboblaze", 1.0, None), ("teravolt", 1.0, None),
])
def test_tera_shell_is_tagged_only_when_it_caps_the_hit(user_ability, multiplier, ability):
    action, _ = struck("tera-shell", user_ability)
    assert (action.multiplier, action.ability) == (multiplier, ability)
    assert line(action).endswith("효과 별로 [테라셸]") == (ability is not None)


def foe_hits(fighter, seed=0, ability="intimidate"):
    foe = replace(mon("윈디", ("fire",), speed=200, moves=(FLAMETHROWER,)), ability=ability)
    result = simulate(((fighter,), (foe,)), seed=seed)
    return result, [event for event in result.events if isinstance(event, Action) and event.side == 1]


def test_an_uploaded_terapagos_fights_its_terastal_form_with_tera_shell():
    terapagos = build(1024, ability="tera-shift")
    assert (terapagos.ability, terapagos.tera) == ("tera-shell", True)
    result, (first, second, *_) = foe_hits(terapagos)
    assert (first.multiplier, first.ability, first.critical) == (0.5, "tera-shell", False)
    assert (second.multiplier, second.ability) == (1.0, None)
    lines = battle_turns(result)[0][1]
    assert lines[0] == "🔵 테라파고스는 테라스탈폼이 되었다!"
    assert any(text.startswith("🔴 윈디 › 화염방사 → 테라파고스") and text.endswith("효과 별로 [테라셸]") for text in lines)


def test_a_stellar_crystal_terapagos_loses_tera_shell_when_it_turns_stellar():
    terapagos = build(1024, "stellar-crystal", ability="tera-shift")
    assert (terapagos.ability, terapagos.mega.ability_id) == ("tera-shell", "teraform-zero")
    result, (first, *_) = foe_hits(terapagos)
    kinds = [event.kind for event in result.events if isinstance(event, FormShift)]
    assert kinds == ["terastal", "stellar"]
    assert result.events.index(first) > max(index for index, event in enumerate(result.events)
                                            if isinstance(event, FormShift))
    assert (first.multiplier, first.ability) == (1.0, None)


def test_an_uploaded_dragonite_names_multiscale_on_the_first_hit_only():
    dragonite = build(149, ability="multiscale")
    assert dragonite.ability == "multiscale"
    result, (first, second, *_) = foe_hits(dragonite)
    assert (first.ability, first.critical, second.ability) == ("multiscale", False, None)
    texts = [text for _, lines in battle_turns(result) for text in lines if "윈디 › 화염방사" in text]
    assert ["[멀티스케일]" in text for text in texts[:2]] == [True, False]


def test_mold_breaker_ignores_the_foes_ability_on_every_hit():
    _, broken = struck("fur-coat", "mold-breaker", DOUBLE_HIT)
    _, plain = struck(None, "mold-breaker", DOUBLE_HIT)
    _, coated = struck("fur-coat", None, DOUBLE_HIT)
    assert broken == plain > coated


def test_a_mold_breaker_foe_gets_no_multiscale_tag():
    _, hits = foe_hits(build(149, ability="multiscale"), ability="mold-breaker")
    assert all(hit.ability is None for hit in hits)
