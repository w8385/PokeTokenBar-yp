from dataclasses import replace

import pytest
from attacks import attack
from test_ability_damage import facing
from test_held_items_more import FixedRng

from ypoke import battle, items
from ypoke.battle import AbilityAct, Action, BattleResult, Change
from ypoke.narration import battle_turns

TACKLE, EARTHQUAKE, SURF, POWER_UP_PUNCH = attack(33), attack(89), attack(57), attack(612)
POISON_JAB, DOUBLE_HIT, ROCK_THROW, GRASS_KNOT = attack(398), attack(458), attack(88), attack(447)
WEAK = {"attack": 10, "special_attack": 10}
TRIGGERS, MISSES = 0.25, 0.5
SURE = 0.05


def struck(move, foe_ability=None, user_ability=None, draw=TRIGGERS, foe_item=None, substitute=False, foe_hp=None,
           user_item=None, **kwargs):
    """The user's `move` on the foe with every chance draw at `draw`; the action, the user and the foe."""
    user, foe, arena = facing(user_ability, foe_ability, **{**WEAK, **kwargs})
    foe.item, user.item = foe_item, user_item
    if foe_hp is not None:
        foe.hp = foe_hp
    if substitute:
        foe.volatiles["substitute"] = foe.max_hp
    user.combatant = replace(user.combatant, moves=(move,))
    user.pp = [move.pp]
    action = battle._resolve(1, 0, (user, foe), 0, arena.weather, FixedRng(draw), arena)
    return action, user, foe


@pytest.mark.parametrize(("move", "afflicted"), [(TACKLE, True), (EARTHQUAKE, False), (SURF, False)])
def test_static_answers_only_a_contact_move(move, afflicted):
    _, user, _ = struck(move, "static")
    assert (user.status == "paralysis") == afflicted


@pytest.mark.parametrize(("move", "hurt"), [(TACKLE, True), (EARTHQUAKE, False)])
def test_rocky_helmet_answers_only_a_contact_move(move, hurt):
    _, user, _ = struck(move, foe_item=items.ROCKY_HELMET)
    assert (user.hp < user.max_hp) == hurt


@pytest.mark.parametrize(("substitute", "afflicted"), [(True, False), (False, True)])
def test_static_does_not_answer_a_hit_its_substitute_took(substitute, afflicted):
    _, user, _ = struck(POWER_UP_PUNCH, "static", substitute=substitute)
    assert (user.status == "paralysis") == afflicted


@pytest.mark.parametrize(("move", "user_ability", "user_types", "draw", "status"), [
    (TACKLE, None, ("normal",), SURE, "sleep"), (TACKLE, None, ("normal",), 0.15, "paralysis"),
    (TACKLE, None, ("normal",), TRIGGERS, "poison"), (TACKLE, None, ("normal",), MISSES, None),
    (EARTHQUAKE, None, ("normal",), SURE, None), (TACKLE, "overcoat", ("normal",), SURE, None),
    (TACKLE, None, ("grass",), SURE, None),
])
def test_effect_spore_draws_one_ailment_for_a_contact_move(move, user_ability, user_types, draw, status):
    _, user, _ = struck(move, "effect-spore", user_ability, draw, user_types=user_types)
    assert user.status == status


@pytest.mark.parametrize(("foe_ability", "move", "user_ability", "hurt"), [
    ("rough-skin", TACKLE, None, True), ("iron-barbs", TACKLE, None, True), ("rough-skin", EARTHQUAKE, None, False),
    ("rough-skin", TACKLE, "magic-guard", False), (None, TACKLE, None, False),
    ("rough-skin", GRASS_KNOT, None, True), ("rough-skin", SURF, None, False),
])
def test_rough_skin_takes_an_eighth_per_contact_hit(foe_ability, move, user_ability, hurt):
    action, user, _ = struck(move, foe_ability, user_ability, MISSES)
    assert user.max_hp - user.hp == (user.max_hp // 8 if hurt else 0)
    assert action.ability == (foe_ability if hurt else None)


def test_rough_skin_takes_its_share_once_per_hit():
    _, user, _ = struck(DOUBLE_HIT, "rough-skin", draw=MISSES)
    assert user.max_hp - user.hp == 2 * (user.max_hp // 8)


@pytest.mark.parametrize(("move", "user_ability", "foe_hp", "hurt"), [
    (TACKLE, None, 1, True), (EARTHQUAKE, None, 1, False), (TACKLE, "damp", 1, False),
    (TACKLE, "magic-guard", 1, False), (TACKLE, None, None, False),
])
def test_aftermath_hurts_the_contact_move_that_knocks_its_holder_out(move, user_ability, foe_hp, hurt):
    user, foe, arena = facing(user_ability, "aftermath", **WEAK)
    if foe_hp is not None:
        foe.hp = foe_hp
    user.combatant = replace(user.combatant, moves=(move,))
    battle._resolve(1, 0, (user, foe), 0, arena.weather, FixedRng(MISSES), arena)
    assert user.max_hp - user.hp == (user.max_hp // 4 if hurt else 0)
    assert any(isinstance(event, AbilityAct) for event in arena.log) == hurt


def test_aftermath_does_nothing_while_a_damp_foe_holds_it():
    _, user, _ = struck(TACKLE, "aftermath", "damp", MISSES, foe_hp=1)
    assert user.hp == user.max_hp


@pytest.mark.parametrize(("move", "foe_hp", "lost"), [(EARTHQUAKE, 7, 7), (SURF, 7, 7), (DOUBLE_HIT, 3, 3)])
def test_innards_out_deals_the_hp_the_last_hit_took(move, foe_hp, lost):
    _, user, foe = struck(move, "innards-out", draw=MISSES, foe_hp=foe_hp)
    assert foe.hp == 0
    assert user.max_hp - user.hp == lost


def test_innards_out_does_nothing_when_its_holder_survives():
    _, user, foe = struck(TACKLE, "innards-out", draw=MISSES)
    assert foe.hp > 0 and user.hp == user.max_hp


@pytest.mark.parametrize(("draw", "user_ability", "substitute", "disabled"), [
    (TRIGGERS, None, False, True), (MISSES, None, False, False), (TRIGGERS, "aroma-veil", False, False),
    (TRIGGERS, None, True, False),
])
def test_cursed_body_may_disable_the_move_that_hit_it(draw, user_ability, substitute, disabled):
    _, user, _ = struck(EARTHQUAKE, "cursed-body", user_ability, draw, substitute=substitute)
    assert ("disable" in user.volatiles) == disabled
    assert battle._banned(user, EARTHQUAKE) == ("disable" if disabled else "")


@pytest.mark.parametrize(("move", "counting"), [(TACKLE, True), (EARTHQUAKE, False)])
def test_perish_body_starts_the_count_on_both_after_contact(move, counting):
    _, user, foe = struck(move, "perish-body", draw=MISSES)
    assert ("perish-song" in user.volatiles, "perish-song" in foe.volatiles) == (counting, counting)


@pytest.mark.parametrize(("foe_ability", "move", "user_ability", "user_after", "foe_after"), [
    ("mummy", TACKLE, "huge-power", "mummy", "mummy"), ("mummy", EARTHQUAKE, "huge-power", "huge-power", "mummy"),
    ("lingering-aroma", TACKLE, "huge-power", "lingering-aroma", "lingering-aroma"),
    ("mummy", TACKLE, "zen-mode", "zen-mode", "mummy"),
    ("wandering-spirit", TACKLE, "huge-power", "wandering-spirit", "huge-power"),
    ("wandering-spirit", EARTHQUAKE, "huge-power", "huge-power", "wandering-spirit"),
])
def test_a_contact_move_catches_or_swaps_the_holders_ability(foe_ability, move, user_ability, user_after, foe_after):
    _, user, foe = struck(move, foe_ability, user_ability, MISSES)
    assert (user.combatant.ability, foe.combatant.ability) == (user_after, foe_after)


@pytest.mark.parametrize(("move", "foe_item", "user_item", "foe_after", "user_after"), [
    (TACKLE, None, "leftovers", "leftovers", None), (EARTHQUAKE, None, "leftovers", None, "leftovers"),
    (TACKLE, "sitrus-berry", "leftovers", "sitrus-berry", "leftovers"),
])
def test_pickpocket_takes_the_item_of_a_contact_move_user(move, foe_item, user_item, foe_after, user_after):
    _, user, foe = struck(move, "pickpocket", draw=MISSES, foe_item=foe_item, user_item=user_item)
    assert (foe.item, user.item) == (foe_after, user_after)


@pytest.mark.parametrize(("foe_item", "user_item", "user_after", "foe_after"), [
    ("leftovers", None, "leftovers", None), ("leftovers", "sitrus-berry", "sitrus-berry", "leftovers"),
])
def test_magician_takes_the_item_of_the_foe_its_move_hit(foe_item, user_item, user_after, foe_after):
    _, user, foe = struck(SURF, user_ability="magician", draw=MISSES, foe_item=foe_item, user_item=user_item)
    assert (user.item, foe.item) == (user_after, foe_after)


@pytest.mark.parametrize(("user_ability", "move", "foe_ability", "draw", "status"), [
    ("poison-touch", TACKLE, None, TRIGGERS, "poison"), ("poison-touch", TACKLE, None, MISSES, None),
    ("poison-touch", EARTHQUAKE, None, TRIGGERS, None), ("poison-touch", TACKLE, "shield-dust", TRIGGERS, None),
    ("toxic-chain", EARTHQUAKE, None, TRIGGERS, "toxic"), ("toxic-chain", SURF, "immunity", TRIGGERS, None),
])
def test_the_holders_hit_may_poison_its_target(user_ability, move, foe_ability, draw, status):
    _, _, foe = struck(move, foe_ability, user_ability, draw)
    assert foe.status == status


@pytest.mark.parametrize(("user_ability", "draw", "acted", "flinched"), [
    ("stench", SURE, False, True), ("stench", MISSES, False, False), ("stench", SURE, True, False),
    (None, SURE, False, False),
])
def test_stench_may_flinch_a_target_that_has_not_moved(user_ability, draw, acted, flinched):
    user, foe, arena = facing(user_ability, None, **WEAK)
    foe.acted = acted
    user.combatant = replace(user.combatant, moves=(SURF,))
    battle._resolve(1, 0, (user, foe), 0, arena.weather, FixedRng(draw), arena)
    assert ("flinch" in foe.volatiles) == flinched


@pytest.mark.parametrize(("user_ability", "foe_ability", "confused"), [
    ("poison-puppeteer", None, True), (None, None, False), ("poison-puppeteer", "own-tempo", False),
])
def test_poison_puppeteer_confuses_the_foe_it_poisons(user_ability, foe_ability, confused):
    _, _, foe = struck(POISON_JAB, foe_ability, user_ability, SURE)
    assert foe.status == "poison"
    assert (foe.confusion_left > 0) == confused


@pytest.mark.parametrize(("move", "user_types", "burned"), [
    (SURF, ("normal",), True), (TACKLE, ("normal",), True), (TACKLE, ("fire",), False),
])
def test_spicy_spray_burns_the_user_of_any_damaging_move(move, user_types, burned):
    _, user, _ = struck(move, "spicy-spray", draw=MISSES, user_types=user_types)
    assert (user.status == "burn") == burned


@pytest.mark.parametrize(("foe_ability", "move", "slowed"), [
    ("gooey", TACKLE, True), ("tangling-hair", TACKLE, True), ("gooey", EARTHQUAKE, False),
])
def test_gooey_lowers_speed_only_after_contact(foe_ability, move, slowed):
    _, user, _ = struck(move, foe_ability, draw=MISSES)
    assert user.stages["speed"] == (-1 if slowed else 0)


@pytest.mark.parametrize(("foe_ability", "picked"), [(None, 0), ("rough-skin", 1), ("iron-barbs", 1)])
def test_the_chooser_takes_an_equal_non_contact_move_into_rough_skin(foe_ability, picked):
    user, foe, _ = facing(None, foe_ability, **WEAK)
    user.combatant = replace(user.combatant, moves=(TACKLE, replace(TACKLE, name="비접촉", id=ROCK_THROW.id)))
    user.pp = [TACKLE.pp, TACKLE.pp]
    assert battle._best_move(user, foe, None) == picked


@pytest.mark.parametrize(("event", "line"), [
    (AbilityAct(1, 1, "상대", "cursed-body", effect="disable", detail="지진", foe="사용자"),
     "🔴 상대 [저주받은바디] 지진 🚫사슬묶기 → 사용자"),
    (AbilityAct(1, 1, "상대", "pickpocket", effect="stole", detail="leftovers", foe="사용자"),
     "🔴 상대 [나쁜손버릇] 먹다남은음식 훔쳤다 → 사용자"),
    (AbilityAct(1, 1, "상대", "mummy", effect="spread", foe="사용자"), "🔴 상대 [미라] 특성 전염 → 사용자"),
    (AbilityAct(1, 1, "상대", "wandering-spirit", effect="swap", foe="사용자"), "🔴 상대 [떠도는영혼] 특성 교환 → 사용자"),
    (AbilityAct(1, 1, "상대", "perish-body", effect="perish", foe="사용자"), "🔴 상대 [멸망의바디] 🎵멸망 카운트 → 사용자"),
    (AbilityAct(1, 1, "상대", "aftermath", foe="사용자", foe_hp=75), "🔴 상대 [유폭] → 사용자 75%"),
    (AbilityAct(1, 0, "사용자", "poison-puppeteer", changes=(Change(1, "상대", "confusion"),)),
     "🔵 사용자 [독조종] → 상대 💫혼란"),
])
def test_the_lines_name_the_contact_ability(event, line):
    opening = Action(1, 0, "사용자", "상대", TACKLE.name)
    [(_, lines)] = battle_turns(BattleResult(winner=0, turns=1, events=[opening, event]))
    assert lines[1:] == [line]
