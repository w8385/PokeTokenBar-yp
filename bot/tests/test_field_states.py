import random
from dataclasses import replace

import pytest
from test_battle import TACKLE, mon

from ypoke import battle, move_power, narration
from ypoke import field_states as fs
from ypoke.battle import (
    AbilityField, Action, Carry, Change, FieldEnd, FieldStart, HazardDamage, HazardHit, Move, SendOut, TerrainHeal,
    _Arena, _Fighter, _Team, _Weather, simulate,
)
from ypoke.effects import hooks
from ypoke.narration import battle_turns

THUNDERBOLT = Move("10만볼트", "electric", 90, physical=False, accuracy=100)
EARTHQUAKE = Move("지진", "ground", 100, physical=True, accuracy=100, id=89)
DRAGON_CLAW = Move("드래곤크루", "dragon", 80, physical=True, accuracy=100)
SURF = Move("파도타기", "water", 90, physical=False, accuracy=100)
JET_PUNCH = Move("제트펀치", "water", 60, physical=True, accuracy=100, priority=1)
FLY = Move("공중날기", "flying", 90, physical=True, accuracy=95, id=19)
WEAK_SHOT = Move("빗나가기쉬운기술", "normal", 40, physical=True, accuracy=50)
FLOWER_TRICK = Move("트릭플라워", "grass", 70, physical=True, accuracy=None, id=870)
TACHYON_CUTTER = Move("타키온커터", "steel", 50, physical=False, accuracy=0, id=911)
RISING_VOLTAGE = Move("라이징볼트", "electric", 70, physical=False, accuracy=100, id=804)
EXPANDING_FORCE = Move("와이드포스", "psychic", 80, physical=False, accuracy=100, id=797)
TERRAIN_PULSE = Move("대지의파동", "normal", 50, physical=False, accuracy=100, id=805)
BODY_SLAM = Move("누르기", "normal", 85, physical=True, accuracy=100)
GRASSY_GLIDE = Move("그래스슬라이더", "grass", 55, physical=True, accuracy=100, id=803)
MISTY_EXPLOSION = Move("미스트버스트", "fairy", 100, physical=False, accuracy=100, id=802, effect="self-ko")
PSYBLADE = Move("사이코블레이드", "psychic", 80, physical=True, accuracy=100, id=875)
STEEL_ROLLER = Move("아이언롤러", "steel", 130, physical=True, accuracy=100, id=798)
ICE_SPINNER = Move("아이스스피너", "ice", 80, physical=True, accuracy=100, id=861)
STONE_AXE = Move("암석액스", "rock", 65, physical=True, accuracy=100, id=830)
BRICK_BREAK = Move("깨뜨리다", "fighting", 75, physical=True, accuracy=100, id=280)
RAPID_SPIN = Move("고속스핀", "normal", 50, physical=True, accuracy=100, effect="rapid-spin", id=229,
                  stat_changes=(("speed", 1),), stat_on_user=True, stat_chance=100)
MORTAL_SPIN = Move("킬러스핀", "poison", 30, physical=True, accuracy=100, effect="mortal-spin", id=866)


def status(name, key, kind="normal"):
    return Move(name, kind, 0, physical=False, effect=key)


REFLECT = status("리플렉터", "reflect", "psychic")
LIGHT_SCREEN = status("빛의장막", "light-screen", "psychic")
AURORA_VEIL = status("오로라베일", "aurora-veil", "ice")
TAILWIND = status("순풍", "tailwind", "flying")
SPIKES = status("압정뿌리기", "spikes", "ground")
TOXIC_SPIKES = status("독압정", "toxic-spikes", "poison")
STICKY_WEB = status("끈적끈적네트", "sticky-web", "bug")
GRAVITY = status("중력", "gravity", "psychic")
HAZE = status("흑안개", "haze", "ice")
DEFOG = status("안개제거", "defog", "flying")
COURT_CHANGE = status("코트체인지", "court-change")
TIDY_UP = status("대청소", "tidy-up")
MISTY_TERRAIN = status("미스트필드", "misty-terrain", "fairy")
ELECTRIC_TERRAIN = status("일렉트릭필드", "electric-terrain", "electric")


def put(combatant, arena, side=0, item=None, ability=None):
    fighter = _Fighter.enter(replace(combatant, ability=ability) if ability else combatant)
    fighter.item = item
    fighter.arena, fighter.side = arena, side
    return fighter


def resolve(user, target, move, arena, weather=None, seed=0):
    user.combatant = replace(user.combatant, moves=(move,))
    user.pp = [move.pp]
    fighters = (user, target) if user.side == 0 else (target, user)
    return battle._resolve(1, user.side, fighters, 0, weather or _Weather(), random.Random(seed), arena)


def actions(result):
    return [event for event in result.events if isinstance(event, Action)]


def wall(name, types=("normal",), moves=(TACKLE,), speed=80, **rest):
    return mon(name, types, moves=moves, hp=250, attack=20, defense=250, special_defense=250, speed=speed, **rest)


def test_electric_terrain_boosts_a_grounded_users_electric_move_and_keeps_grounded_pokemon_awake():
    arena = _Arena(terrain="electric-terrain", terrain_turns=5)
    grounded, flier, target = put(mon("땅", ("normal",)), arena), put(mon("새", ("flying",)), arena), put(
        mon("과녁", ("normal",)), arena, 1)
    assert battle._power(grounded, target, THUNDERBOLT, None, 1.0) == 90 * fs.TERRAIN_BOOST
    assert battle._power(flier, target, THUNDERBOLT, None, 1.0) == 90
    assert battle._power(grounded, target, SURF, None, 1.0) == 90
    assert not battle._open_to("sleep", grounded) and battle._open_to("sleep", flier)
    assert battle._open_to("paralysis", grounded)


def test_grassy_terrain_from_grassy_surge_heals_grounded_pokemon_for_five_turns():
    setter = replace(wall("풀밭"), ability="grassy-surge")
    result = simulate(((setter,), (wall("과녁"),)), seed=1, carried=[Carry(50, None)])
    assert result.events[0] == AbilityField(0, "풀밭", "grassy-surge", terrain="grassy-terrain")
    heals = [event for event in result.events if isinstance(event, TerrainHeal)]
    assert [event.turn for event in heals if event.side == 0] == [1, 2, 3, 4, 5]
    assert FieldEnd(5, "grassy-terrain") in result.events
    arena = _Arena(terrain="grassy-terrain", terrain_turns=5)
    grounded, flier = put(mon("풀", ("normal",), hp=200), arena), put(mon("새", ("flying",)), arena)
    grounded.hp, flier.hp = grounded.max_hp // 2, flier.max_hp // 2
    assert isinstance(hooks.key("moves", "grassy-terrain", "end_of_turn", grounded, 0, 1, random.Random(0)),
                      TerrainHeal)
    assert grounded.hp == grounded.max_hp // 2 + grounded.max_hp // fs.GRASSY_HEAL_FRACTION
    assert hooks.key("moves", "grassy-terrain", "end_of_turn", flier, 0, 1, random.Random(0)) is None


def test_grassy_terrain_halves_earthquake_on_a_grounded_target():
    arena = _Arena(terrain="grassy-terrain", terrain_turns=5)
    user, target = put(mon("땅", ("ground",)), arena), put(mon("과녁", ("normal",)), arena, 1)
    assert battle._power(user, target, EARTHQUAKE, None, 1.0) == 50


def test_psychic_terrain_stops_a_priority_move_on_a_grounded_target_after_its_pp():
    arena = _Arena(terrain="psychic-terrain", terrain_turns=5)
    user, target = put(mon("주먹", ("water",)), arena), put(mon("과녁", ("normal",)), arena, 1)
    action = resolve(user, target, JET_PUNCH, arena)
    assert (action.move, action.failed, action.blocked) == ("제트펀치", True, "psychic-terrain")
    assert target.hp == target.max_hp and user.pp == [JET_PUNCH.pp - 1]
    flier = put(mon("새", ("flying",)), arena, 1)
    assert resolve(user, flier, JET_PUNCH, arena).defender_hp < 100
    line = battle_turns(simulate_with_log(action))[0][1][0]
    assert "제트펀치 → 🔮사이코필드에 막힘" in line


def simulate_with_log(action):
    from ypoke.battle import BattleResult
    return BattleResult(winner=0, turns=1, events=[action], remaining=((100,), (100,)), statuses=((None,), (None,)))


def test_misty_terrain_halves_dragon_moves_on_grounded_targets_and_guards_them_from_every_status():
    arena = _Arena(terrain="misty-terrain", terrain_turns=5)
    user, target = put(mon("용", ("dragon",)), arena), put(mon("과녁", ("normal",)), arena, 1)
    flier = put(mon("새", ("flying",)), arena, 1)
    assert battle._power(user, target, DRAGON_CLAW, None, 1.0) == 40
    assert battle._power(user, flier, DRAGON_CLAW, None, 1.0) == 80
    for ailment in ("burn", "paralysis", "sleep", "poison", "confusion"):
        assert not battle._open_to(ailment, target) and battle._open_to(ailment, flier)


def test_a_terrain_extender_keeps_the_terrain_eight_turns_and_the_same_terrain_cannot_be_set_again():
    setter = replace(wall("전기"), ability="electric-surge", item="terrain-extender")
    again = replace(wall("또전기"), ability="electric-surge")
    result = simulate(((setter,), (again,)), seed=1)
    assert [event for event in result.events if isinstance(event, AbilityField)] == [
        AbilityField(0, "전기", "electric-surge", terrain="electric-terrain")]
    assert [event for event in result.events if isinstance(event, FieldEnd)] == [FieldEnd(8, "electric-terrain")]


def test_terrain_moves_use_the_terrain_and_the_grounding_they_need():
    arena = _Arena(terrain="electric-terrain", terrain_turns=5)
    grounded, flier = put(mon("땅", ("normal",)), arena), put(mon("새", ("flying",)), arena)
    target, high = put(mon("과녁", ("normal",)), arena, 1), put(mon("높이", ("flying",)), arena, 1)

    def power(move, user, foe):
        return move_power.power(move, user, foe, None, 1.0)

    assert power(RISING_VOLTAGE, flier, target) == 140 and power(RISING_VOLTAGE, grounded, high) == 70
    assert power(PSYBLADE, flier, target) == 120
    assert power(EXPANDING_FORCE, grounded, target) == 80
    pulse = move_power.typed(TERRAIN_PULSE, None, grounded)
    assert (pulse.type, power(pulse, grounded, target)) == ("electric", 100)
    assert move_power.typed(TERRAIN_PULSE, None, flier).type == "normal"
    arena.terrain = "psychic-terrain"
    assert power(EXPANDING_FORCE, grounded, target) == 120 and power(EXPANDING_FORCE, flier, target) == 80
    arena.terrain = "grassy-terrain"
    assert battle._move_priority(grounded, GRASSY_GLIDE) == 1 and battle._move_priority(flier, GRASSY_GLIDE) == 0
    arena.terrain = "misty-terrain"
    assert power(MISTY_EXPLOSION, grounded, target) == 150
    arena.terrain = None
    assert power(RISING_VOLTAGE, grounded, target) == 70 and power(TERRAIN_PULSE, grounded, target) == 50
    assert battle._move_priority(grounded, GRASSY_GLIDE) == 0


def test_misty_explosion_still_knocks_out_its_user():
    assert hooks.move(MISTY_EXPLOSION, "faints_user", default=False)


def test_steel_roller_fails_with_no_terrain_and_ends_one_like_ice_spinner():
    arena = _Arena()
    user, target = put(mon("롤러", ("steel",)), arena), put(wall("과녁"), arena, 1)
    assert resolve(user, target, STEEL_ROLLER, arena).failed
    for move in (STEEL_ROLLER, ICE_SPINNER):
        arena.terrain, arena.terrain_turns = "grassy-terrain", 5
        assert not resolve(user, target, move, arena).failed
        assert (arena.terrain, arena.log[-1]) == (None, FieldEnd(0, "grassy-terrain", -1, move.name))


def test_stone_axe_lays_stealth_rock_on_the_targets_side():
    arena = _Arena()
    user, target = put(mon("도끼", ("rock",)), arena), put(wall("과녁"), arena, 1)
    resolve(user, target, STONE_AXE, arena)
    assert arena.hazards == [{}, {"stealth-rock": 1}] and arena.log == [FieldStart(0, 1, "stealth-rock")]


@pytest.mark.parametrize(("screen", "physical", "special"), [("reflect", 0.5, 1.0), ("light-screen", 1.0, 0.5),
                                                             ("aurora-veil", 0.5, 0.5)])
def test_a_screen_halves_the_hits_it_covers_unless_critical_or_from_an_infiltrator(screen, physical, special):
    arena = _Arena()
    user, target = put(mon("공격", ("normal",)), arena), put(mon("과녁", ("normal",)), arena, 1)
    plain = [battle._unrolled_damage(user, target, move, 1.0, None) for move in (TACKLE, SURF)]
    arena.sides[1][screen] = 5
    screened = [battle._unrolled_damage(user, target, move, 1.0, None) for move in (TACKLE, SURF)]
    assert [after / before for after, before in zip(screened, plain)] == [physical, special]
    assert battle._unrolled_damage(user, target, TACKLE, 1.0, None, critical=True) == plain[0]
    sneak = put(mon("잠입", ("normal",)), arena, ability="infiltrator")
    assert battle._unrolled_damage(sneak, target, TACKLE, 1.0, None) == plain[0]
    assert battle._unrolled_damage(user, put(mon("내편", ("normal",)), arena), TACKLE, 1.0, None) == plain[0]


@pytest.mark.parametrize(("item", "last_turn"), [(None, 5), ("light-clay", 8)])
def test_reflect_is_set_once_as_its_user_enters_and_lasts_five_turns_or_eight_with_light_clay(item, last_turn):
    setter = replace(wall("벽", moves=(REFLECT, TACKLE)), item=item)
    result = simulate(((setter,), (mon("주먹", ("normal",), hp=250, attack=200, defense=250),)), seed=3)
    assert [(event.turn, event.effect) for event in actions(result) if event.effect] == [(1, "reflect")]
    assert [event for event in result.events if isinstance(event, FieldEnd)] == [FieldEnd(last_turn, "reflect", 0)]


def test_aurora_veil_fails_outside_hail_and_snow():
    arena = _Arena()
    user, target = put(mon("설인", ("ice",)), arena), put(wall("과녁"), arena, 1)
    assert resolve(user, target, AURORA_VEIL, arena).failed and not arena.sides[0]
    assert resolve(user, target, AURORA_VEIL, arena, _Weather("snow", 5)).effect == "aurora-veil"
    assert arena.sides[0] == {"aurora-veil": 5}


def test_brick_break_breaks_the_screens_before_the_hit_but_not_on_a_ghost():
    arena = _Arena(sides=[{}, {"reflect": 5, "light-screen": 5, "tailwind": 3}])
    user, target = put(mon("격투", ("fighting",)), arena), put(wall("과녁"), arena, 1)
    plain = battle._unrolled_damage(user, target, BRICK_BREAK, 2.0, None)
    action = resolve(user, target, BRICK_BREAK, arena)
    assert arena.sides[1] == {"tailwind": 3}
    assert [event.kind for event in arena.log] == ["reflect", "light-screen"]
    assert target.max_hp - target.hp >= int(plain * 0.85) and not action.failed
    ghost_arena = _Arena(sides=[{}, {"reflect": 5}])
    resolve(put(mon("격투", ("fighting",)), ghost_arena), put(wall("유령", ("ghost",)), ghost_arena, 1), BRICK_BREAK,
            ghost_arena)
    assert ghost_arena.sides[1] == {"reflect": 5}


@pytest.mark.parametrize(("layers", "eighths"), [(1, 3), (2, 4), (3, 6)])
def test_spikes_hurt_a_grounded_entrant_by_their_layers_unless_it_floats_or_wears_boots(layers, eighths):
    arena = _Arena()
    entrant = put(mon("착지", ("normal",), hp=200), arena, 1)
    event = hooks.key("moves", "spikes", "hazard", layers, entrant, 1, 3, random.Random(0))
    assert entrant.max_hp - entrant.hp == entrant.max_hp * eighths // 24
    assert event == HazardHit(3, 1, "착지", "spikes", entrant.hp_percent)
    for floater in (put(mon("새", ("flying",)), arena, 1), put(mon("부츠", ("normal",)), arena, 1,
                                                               item="heavy-duty-boots"),
                    put(mon("부유", ("normal",)), arena, 1, ability="levitate")):
        assert hooks.key("moves", "spikes", "hazard", layers, floater, 1, 3, random.Random(0)) is None
        assert floater.hp == floater.max_hp


def test_hazards_hit_a_faint_replacement_in_the_order_they_were_set():
    setter = mon("깔개", ("ground",), moves=(SPIKES, STICKY_WEB, TOXIC_SPIKES, TACKLE), hp=250, attack=255,
                 defense=250, speed=150)
    foes = (mon("선봉", ("normal",), hp=40, attack=10, defense=40), mon("둘째", ("normal",), hp=40, attack=10, defense=40),
            mon("셋째", ("normal",), hp=40, attack=10, defense=40), mon("넷째", ("normal",), hp=150, attack=10, defense=50))
    result = simulate(((setter,), foes), seed=4)
    assert [event.effect for event in actions(result) if event.side == 0][:3] == ["spikes", "toxic-spikes",
                                                                                   "sticky-web"]
    last = [event for event in result.events if isinstance(event, HazardHit) and event.pokemon == "넷째"]
    assert [event.hazard for event in last] == ["spikes", "toxic-spikes", "sticky-web"]
    assert last[1].change == Change(1, "넷째", "poison") and last[2].change == Change(1, "넷째", "speed", -1)
    assert sum(event.effect == "spikes" for event in actions(result)) == 1


def test_toxic_spikes_poison_or_badly_poison_and_a_grounded_poison_type_takes_them_away():
    arena = _Arena(hazards=[{}, {"toxic-spikes": 1}])
    one, two = put(mon("하나", ("normal",)), arena, 1), put(mon("둘", ("normal",)), arena, 1)
    assert hooks.key("moves", "toxic-spikes", "hazard", 1, one, 1, 2, random.Random(0)).change.kind == "poison"
    assert hooks.key("moves", "toxic-spikes", "hazard", 2, two, 1, 2, random.Random(0)).change.kind == "toxic"
    for immune in (put(mon("강철", ("steel",)), arena, 1), put(mon("부츠", ("normal",)), arena, 1,
                                                               item="heavy-duty-boots")):
        assert hooks.key("moves", "toxic-spikes", "hazard", 1, immune, 1, 2, random.Random(0)) is None
    sponge = put(mon("독", ("poison",)), arena, 1, item="heavy-duty-boots")
    event = hooks.key("moves", "toxic-spikes", "hazard", 1, sponge, 1, 2, random.Random(0))
    assert event.cleared and arena.hazards[1] == {} and sponge.status is None


def test_sticky_web_lowers_speed_unless_mist_covers_the_side():
    arena = _Arena()
    entrant = put(mon("거미밥", ("normal",)), arena, 1)
    assert hooks.key("moves", "sticky-web", "hazard", 1, entrant, 1, 2, random.Random(0)).change.stages == -1
    arena.sides[1]["mist"] = 5
    misted = put(mon("안개", ("normal",)), arena, 1)
    assert hooks.key("moves", "sticky-web", "hazard", 1, misted, 1, 2, random.Random(0)) is None
    assert misted.stages["speed"] == 0


def test_heavy_duty_boots_keep_stealth_rock_off():
    arena = _Arena()
    booted = put(mon("불새", ("fire", "flying")), arena, 1, item="heavy-duty-boots")
    assert hooks.key("moves", "stealth-rock", "hazard", 1, booted, 1, 2, random.Random(0)) is None
    bare = put(mon("불새", ("fire", "flying")), arena, 1)
    assert isinstance(hooks.key("moves", "stealth-rock", "hazard", 1, bare, 1, 2, random.Random(0)), HazardDamage)


def test_rapid_spin_and_mortal_spin_clear_their_users_hazards():
    arena = _Arena(hazards=[{"spikes": 2, "stealth-rock": 1}, {"spikes": 1}])
    spinner, target = put(mon("팽이", ("normal",)), arena), put(wall("과녁"), arena, 1)
    action = resolve(spinner, target, RAPID_SPIN, arena)
    assert arena.hazards == [{}, {"spikes": 1}] and Change(0, "팽이", "speed", 1) in action.changes
    arena.hazards[0]["sticky-web"] = 1
    action = resolve(spinner, target, MORTAL_SPIN, arena)
    assert arena.hazards == [{}, {"spikes": 1}] and Change(1, "과녁", "poison") in action.changes


def test_defog_clears_the_targets_side_states_both_sides_hazards_and_the_terrain():
    arena = _Arena(terrain="psychic-terrain", terrain_turns=3,
                   sides=[{"tailwind": 3}, {"reflect": 4, "safeguard": 2, "tailwind": 2}],
                   hazards=[{"spikes": 1}, {"stealth-rock": 1}])
    user, target = put(mon("바람", ("flying",)), arena), put(wall("과녁"), arena, 1)
    used = resolve(user, target, DEFOG, arena)
    assert used.effect == "defog" and used.changes == (Change(1, "과녁", "evasion", -1),)
    assert arena.sides == [{"tailwind": 3}, {"tailwind": 2}] and arena.hazards == [{}, {}]
    assert arena.terrain is None
    assert resolve(user, target, DEFOG, arena).effect == "defog" and target.stages["evasion"] == -2
    target.stages["evasion"] = -6
    assert resolve(user, target, DEFOG, arena).failed


def test_defog_drops_no_evasion_through_mist_and_still_clears():
    arena = _Arena(sides=[{}, {"mist": 3, "reflect": 2}])
    user, target = put(mon("바람", ("flying",)), arena), put(wall("과녁"), arena, 1)
    used = resolve(user, target, DEFOG, arena)
    assert used.effect == "defog" and used.changes == () and target.stages["evasion"] == 0
    assert arena.sides == [{}, {}]


def test_court_change_swaps_the_sides_and_fails_with_nothing_to_swap():
    arena = _Arena(sides=[{}, {"reflect": 4}], hazards=[{"spikes": 2}, {}])
    user, target = put(mon("코트", ("normal",)), arena), put(wall("과녁"), arena, 1)
    assert resolve(user, target, COURT_CHANGE, arena).effect == "court-change"
    assert arena.sides == [{"reflect": 4}, {}] and arena.hazards == [{}, {"spikes": 2}]
    assert resolve(user, target, COURT_CHANGE, _Arena()).failed


def test_tidy_up_clears_both_sides_hazards_and_raises_attack_and_speed():
    arena = _Arena(hazards=[{"spikes": 1}, {"sticky-web": 1}])
    user, target = put(mon("청소", ("normal",)), arena), put(wall("과녁"), arena, 1)
    action = resolve(user, target, TIDY_UP, arena)
    assert arena.hazards == [{}, {}]
    assert action.changes == (Change(0, "청소", "attack", 1), Change(0, "청소", "speed", 1))


def test_tailwind_doubles_its_sides_speed_for_four_turns():
    arena = _Arena(sides=[{"tailwind": 4}, {}])
    mine, theirs = put(mon("바람", ("flying",)), arena), put(mon("상대", ("flying",)), arena, 1)
    assert mine.stat("speed") == 2 * theirs.stat("speed")
    setter = wall("바람", ("flying",), moves=(TAILWIND, TACKLE), speed=40)
    result = simulate(((setter,), (wall("빠름", speed=120),)), seed=1)
    assert [(event.turn, event.effect) for event in actions(result) if event.effect][0] == (1, "tailwind")
    assert [event for event in result.events if isinstance(event, FieldEnd)][0] == FieldEnd(4, "tailwind", 0)


def test_safeguard_blocks_a_foes_status_but_not_an_infiltrators_or_the_holders_own():
    arena = _Arena(sides=[{"safeguard": 5}, {}])
    guarded = put(mon("부적", ("normal",)), arena)
    assert not battle._open_to("burn", guarded, by_foe=True) and battle._open_to("burn", guarded, by_foe=False)
    thunder_wave = Move("전기자석파", "electric", 0, physical=False, accuracy=100, effect="thunder-wave")
    plain, sneak = put(mon("전기", ("electric",)), arena, 1), put(mon("잠입", ("electric",)), arena, 1,
                                                                 ability="infiltrator")
    assert resolve(plain, guarded, thunder_wave, arena).failed
    assert resolve(sneak, guarded, thunder_wave, arena).effect == "thunder-wave"


def test_mist_keeps_foes_from_lowering_its_sides_stats():
    arena = _Arena(sides=[{"mist": 5}, {}])
    misted, intimidator = put(mon("안개", ("normal",)), arena), put(mon("위협", ("normal",)), arena, 1,
                                                                   ability="intimidate")
    assert hooks.ability(intimidator, "on_entry", intimidator, misted, 1, _Weather()) is None
    icy_wind = Move("얼다바람", "ice", 55, physical=False, accuracy=100, stat_changes=(("speed", -1),),
                    stat_chance=100)
    action = resolve(put(mon("얼음", ("ice",)), arena, 1), misted, icy_wind, arena)
    assert action.changes == () and misted.stages["speed"] == 0


def test_lucky_chant_stops_even_an_always_crit_move():
    arena = _Arena(sides=[{}, {"lucky-chant": 5}])
    user, target = put(mon("꽃", ("grass",)), arena), put(wall("과녁"), arena, 1)
    assert not any(resolve(user, target, FLOWER_TRICK, arena, seed=seed).critical for seed in range(20))


def test_gravity_grounds_flying_types_and_levitate_raises_accuracy_and_bans_airborne_moves():
    arena = _Arena()
    user = put(mon("중력", ("ground",)), arena)
    flier, floater = put(mon("새", ("flying",)), arena, 1), put(mon("부유", ("normal",)), arena, 1, ability="levitate")
    assert battle._multiplier(EARTHQUAKE, flier) == 0 and battle._multiplier(EARTHQUAKE, floater) == 0
    misses = sum(resolve(put(mon("중력", ("ground",)), arena), put(wall("과녁"), arena, 1), WEAK_SHOT, arena,
                         seed=seed).missed for seed in range(200))
    resolve(user, put(wall("과녁"), arena, 1), GRAVITY, arena)
    assert arena.gravity == fs.GRAVITY_TURNS
    assert battle._multiplier(EARTHQUAKE, flier) == 1.0 and battle._multiplier(EARTHQUAKE, floater) == 1.0
    assert battle._grounded(floater)
    gravity_misses = sum(resolve(put(mon("중력", ("ground",)), arena), put(wall("과녁"), arena, 1), WEAK_SHOT, arena,
                                 seed=seed).missed for seed in range(200))
    assert gravity_misses < misses * 0.5
    jumper = put(mon("새", ("flying",)), arena)
    action = resolve(jumper, put(wall("과녁"), arena, 1), FLY, arena)
    assert (action.move, action.blocked) == ("", "gravity") and jumper.pp == [FLY.pp]


def test_gravity_ends_after_five_turns():
    setter = wall("중력", ("psychic",), moves=(GRAVITY, EARTHQUAKE))
    result = simulate(((setter,), (wall("새", ("flying",)),)), seed=2)
    turn = next(event.turn for event in actions(result) if event.effect == "gravity")
    assert FieldEnd(turn + 4, "gravity") in result.events


def test_haze_resets_every_stat_stage_on_both_sides():
    arena = _Arena()
    user, target = put(mon("안개", ("ice",)), arena), put(wall("과녁"), arena, 1)
    user.stages["defense"], target.stages["attack"], target.stages["speed"] = -2, 4, 1
    assert resolve(user, target, HAZE, arena).effect == "haze"
    assert set(user.stages.values()) == {0} and set(target.stages.values()) == {0}


def test_field_stat_abilities_raise_their_stat_only_under_their_state():
    arena = _Arena()
    surfer, plain = put(mon("서퍼", ("electric",)), arena, ability="surge-surfer"), put(mon("보통", ("electric",)), arena)
    engine = put(mon("엔진", ("electric",)), arena, ability="hadron-engine")
    assert surfer.stat("speed") == plain.stat("speed")
    assert engine.stat("special_attack") == plain.stat("special_attack")
    arena.terrain = "electric-terrain"
    assert surfer.stat("speed") == 2 * plain.stat("speed")
    assert engine.stat("special_attack") == plain.stat("special_attack") * 5461 / 4096
    assert engine.stat("attack") == plain.stat("attack")


def test_screen_cleaner_clears_both_sides_screens_on_entry():
    arena = _Arena(sides=[{"reflect": 3, "tailwind": 2}, {"light-screen": 4}])
    cleaner = put(mon("청소부", ("psychic",)), arena, ability="screen-cleaner")
    foe = put(mon("상대", ("normal",)), arena, 1)
    event = hooks.ability(cleaner, "on_entry", cleaner, foe, 0, _Weather())
    assert event == AbilityField(0, "청소부", "screen-cleaner", cleared=("reflect", "light-screen"))
    assert arena.sides == [{"tailwind": 2}, {}]
    assert hooks.ability(cleaner, "on_entry", cleaner, foe, 0, _Weather()) is None
    assert narration._entry_segment(event).endswith("🛡️리플렉터·🛡️빛의장막 사라짐")


def test_flower_trick_always_crits_and_never_misses():
    arena = _Arena()
    for seed in range(40):
        user, target = put(mon("꽃", ("grass",)), arena), put(wall("과녁"), arena, 1)
        action = resolve(user, target, FLOWER_TRICK, arena, seed=seed)
        assert action.critical and not action.missed


def test_tachyon_cutter_never_misses_despite_pokeapis_zero_accuracy():
    arena = _Arena()
    for seed in range(20):
        user, target = put(mon("커터", ("steel",)), arena), put(wall("과녁"), arena, 1)
        assert not resolve(user, target, TACHYON_CUTTER, arena, seed=seed).missed


def test_the_chooser_spins_away_its_own_hazards_only_while_a_member_is_to_come():
    arena = _Arena(hazards=[{"spikes": 1}, {}])
    spinner = mon("팽이", ("normal",), moves=(BODY_SLAM, RAPID_SPIN))
    teams = (_Team((spinner, mon("후발", ("normal",))), arena=arena, side=0),
             _Team((wall("과녁", ("fire",)),), arena=arena, side=1))
    assert battle._choose(teams, 0, arena, None) == 1
    arena.hazards[0] = {}
    assert battle._choose(teams, 0, arena, None) == 0


def test_the_chooser_sets_a_terrain_that_helps_it_and_never_one_that_hurts_it():
    arena = _Arena()
    zapper = mon("전기", ("electric",), moves=(THUNDERBOLT, ELECTRIC_TERRAIN))
    dragon = mon("용", ("dragon",), moves=(DRAGON_CLAW, MISTY_TERRAIN))
    foe = (wall("과녁"),)
    assert battle._choose((_Team((zapper,), arena=arena), _Team(foe, arena=arena, side=1)), 0, arena, None) == 1
    assert battle._choose((_Team((dragon,), arena=arena), _Team(foe, arena=arena, side=1)), 0, arena, None) == 0


def test_field_events_read_as_korean_log_lines():
    from ypoke.battle import BattleResult
    events = [
        SendOut(2, 1, "둘째", 1), HazardHit(2, 1, "둘째", "spikes", 88),
        HazardHit(2, 1, "둘째", "toxic-spikes", 88, change=Change(1, "둘째", "toxic")),
        HazardHit(2, 1, "독", "toxic-spikes", 100, cleared=True), TerrainHeal(2, 0, "풀", 70),
        FieldEnd(2, "reflect", 0), FieldEnd(2, "spikes", 1, "고속스핀"), FieldEnd(2, "electric-terrain"),
        FieldStart(2, 1, "stealth-rock"),
    ]
    result = BattleResult(winner=0, turns=2, events=events, remaining=((100,), (100,)), statuses=((None,), (None,)))
    text = "\n".join(line for _, lines in battle_turns(result) for line in lines)
    for line in ("🔴 둘째 📌압정 88%", "🔴 둘째 ☠️독압정 ☠️맹독", "🔴 독 ☠️독압정 흡수", "🔵 풀 🌿그래스필드 70%",
                 "🔵 🛡️리플렉터 끝", "🔴 📌압정 사라짐 (고속스핀)", "⚡일렉트릭필드 끝", "🔴 쪽에 🪨스텔스록 깔림"):
        assert line in text
