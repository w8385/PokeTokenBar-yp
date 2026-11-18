import random

from status_moves import choose, data_move, pair, put, resolve, weather
from test_battle import TACKLE, mon

from ypoke import battle, narration
from ypoke.battle import Carry, Change, Move, _Arena, _Team

RECOVER, LIFE_DEW, JUNGLE_HEALING, MORNING_SUN = data_move(105), data_move(791), data_move(816), data_move(234)
SHORE_UP, ROOST, SWALLOW, WISH = data_move(659), data_move(355), data_move(256), data_move(273)
HEAL_PULSE, FLORAL_HEALING, PURIFY, STRENGTH_SAP = data_move(505), data_move(666), data_move(685), data_move(668)
PAIN_SPLIT, REST, AQUA_RING, INGRAIN = data_move(220), data_move(156), data_move(392), data_move(275)
HEAL_BELL, REFRESH, HEALING_WISH, REVIVAL_BLESSING = data_move(215), data_move(287), data_move(361), data_move(863)
MEMENTO = data_move(262)
EARTHQUAKE = Move("지진", "ground", 100, physical=True, accuracy=100)
HUGE_HIT = Move("큰기술", "normal", 250, physical=True, accuracy=100)


def fighters(arena=None, user_types=("normal",), foe_types=("normal",)):
    arena = arena or _Arena()
    return put(mon("사용자", user_types), arena), put(mon("상대", foe_types), arena, 1), arena


def hurt(fighter, share=4):
    fighter.hp = fighter.max_hp // share
    return fighter.hp


def upkeep(user, foe, turn=1):
    events = []
    battle._volatile_upkeep(turn, (user, foe), events, random.Random(0))
    return events


def test_recover_heals_half_and_fails_at_full_hp():
    user, foe, arena = fighters()
    before = hurt(user)
    assert resolve(user, foe, RECOVER, arena).effect == "heal"
    assert user.hp == before + user.max_hp // 2
    user.hp = user.max_hp
    assert resolve(user, foe, RECOVER, arena).failed


def test_a_quarter_heal_that_cures_still_works_at_full_hp():
    user, foe, arena = fighters()
    before = hurt(user, 2)
    assert resolve(user, foe, LIFE_DEW, arena).changes == () and user.hp == before + user.max_hp // 4
    user.hp, user.status = user.max_hp, "burn"
    used = resolve(user, foe, JUNGLE_HEALING, arena)
    assert not used.failed and used.changes == (Change(0, "사용자", "cure"),) and user.status is None


def test_weather_heals_two_thirds_in_their_weather_and_a_quarter_in_another():
    user, foe, arena = fighters()
    for kind, move, share in ((None, MORNING_SUN, (1, 2)), ("sun", MORNING_SUN, (2, 3)), ("rain", MORNING_SUN, (1, 4)),
                              ("sandstorm", SHORE_UP, (2, 3)), ("rain", SHORE_UP, (1, 2))):
        arena.weather = weather(kind) if kind else battle._Weather()
        user.hp = 1
        resolve(user, foe, move, arena)
        assert user.hp == 1 + user.max_hp * share[0] // share[1], (kind, move.name)


def test_roost_lands_a_flying_user_until_the_end_of_the_turn():
    user, foe, arena = fighters(user_types=("flying", "fire"))
    hurt(user)
    resolve(user, foe, ROOST, arena)
    assert user.combatant.types == ("fire",) and battle._multiplier(EARTHQUAKE, user, None) > 0
    upkeep(user, foe)
    assert user.combatant.types == ("flying", "fire") and "roost" not in user.volatiles


def test_swallow_heals_by_the_stockpile_count_and_gives_its_stages_back():
    user, foe, arena = fighters()
    assert resolve(user, foe, SWALLOW, arena).failed
    user.memory["stockpile"], user.stages["defense"], user.stages["special_defense"] = 2, 2, 2
    before = hurt(user)
    used = resolve(user, foe, SWALLOW, arena)
    assert user.hp == before + user.max_hp // 2 and "stockpile" not in user.memory
    assert [(change.kind, change.stages) for change in used.changes] == [("defense", -2), ("special_defense", -2)]


def test_wish_heals_half_at_the_end_of_the_next_turn_and_not_twice():
    user, foe, arena = fighters()
    before = hurt(user)
    assert resolve(user, foe, WISH, arena).effect == "wish"
    assert resolve(user, foe, WISH, arena).failed
    assert upkeep(user, foe, 1) == [] and user.hp == before
    tick = upkeep(user, foe, 2)
    assert user.hp == before + user.max_hp // 2 and tick[0].kind == "wish" and "wish" not in user.volatiles


def test_heal_pulse_heals_the_foe_more_in_grassy_terrain_and_is_never_picked():
    user, foe, arena = fighters()
    foe.hp = 1
    resolve(user, foe, HEAL_PULSE, arena)
    assert foe.hp == 1 + foe.max_hp // 2
    foe.hp, arena.terrain = 1, "grassy-terrain"
    resolve(user, foe, FLORAL_HEALING, arena)
    assert foe.hp == 1 + foe.max_hp * 2 // 3
    teams, arena = pair((HEAL_PULSE, TACKLE))
    teams[1].active.hp = 1
    assert choose(teams, arena) == 1


def test_purify_needs_a_foe_status_and_cures_it_to_heal():
    user, foe, arena = fighters()
    hurt(user)
    assert resolve(user, foe, PURIFY, arena).failed
    foe.status = "poison"
    used = resolve(user, foe, PURIFY, arena)
    assert used.changes == (Change(1, "상대", "cure"),) and foe.status is None and user.hp > user.max_hp // 4


def test_strength_sap_heals_by_the_foes_attack_and_lowers_it_until_minus_six():
    user, foe, arena = fighters()
    user.hp = 1
    attack = int(foe.stat("attack"))
    used = resolve(user, foe, STRENGTH_SAP, arena)
    assert user.hp == 1 + attack and used.changes == (Change(1, "상대", "attack", -1),)
    foe.stages["attack"], user.hp = -6, 1
    assert resolve(user, foe, STRENGTH_SAP, arena).failed and user.hp == 1


def test_pain_split_averages_both_hp():
    user, foe, arena = fighters()
    user.hp = 10
    total = user.hp + foe.hp
    resolve(user, foe, PAIN_SPLIT, arena)
    assert user.hp == foe.hp == total // 2


def test_rest_heals_fully_and_sleeps_two_turns_unless_it_cannot_sleep():
    user, foe, arena = fighters()
    user.status = "burn"
    hurt(user)
    used = resolve(user, foe, REST, arena)
    assert user.hp == user.max_hp and user.status == "sleep" and user.sleep_left == 2
    assert used.changes == (Change(0, "사용자", "sleep"),)
    user.status = None
    assert resolve(user, foe, REST, arena).failed
    hurt(user)
    arena.terrain = "electric-terrain"
    assert resolve(user, foe, REST, arena).failed and user.status is None


def test_aqua_ring_heals_a_sixteenth_each_turn_and_ingrain_grounds_a_flyer():
    user, foe, arena = fighters(user_types=("flying",))
    before = hurt(user)
    resolve(user, foe, AQUA_RING, arena)
    assert resolve(user, foe, AQUA_RING, arena).failed
    upkeep(user, foe)
    assert user.hp == before + user.max_hp // 16
    assert battle._multiplier(EARTHQUAKE, user, None) == 0
    resolve(user, foe, INGRAIN, arena)
    assert battle._multiplier(EARTHQUAKE, user, None) > 0 and battle._grounded(user)


def test_heal_bell_cures_the_whole_team_and_refresh_only_its_user():
    arena = _Arena()
    team = _Team((mon("사용자", ("normal",)), mon("후속", ("normal",))), carried=(None, Carry(50, "paralysis")),
                 arena=arena)
    foe_team = _Team((mon("상대", ("normal",)),), arena=arena, side=1)
    arena.teams = (team, foe_team)
    user, foe = team.active, foe_team.active
    user.status = "sleep"
    used = resolve(user, foe, HEAL_BELL, arena)
    assert used.effect == "heal-bell" and user.status is None and team.carried[1].status is None
    assert resolve(user, foe, HEAL_BELL, arena).failed
    user.status = "sleep"
    assert resolve(user, foe, REFRESH, arena).failed
    user.status = "burn"
    assert resolve(user, foe, REFRESH, arena).changes == (Change(0, "사용자", "cure"),)


def test_healing_wish_faints_its_user_and_fully_heals_the_next_member():
    arena = _Arena()
    team = _Team((mon("사용자", ("normal",)), mon("후속", ("normal",))), carried=(None, Carry(30, "burn")), arena=arena)
    foe_team = _Team((mon("상대", ("normal",)),), arena=arena, side=1)
    arena.teams = (team, foe_team)
    used = resolve(team.active, foe_team.active, HEALING_WISH, arena)
    assert used.attacker_fainted and team.active.hp == 0
    events = []
    battle._send_in(team, 0, 1, arena, events, random.Random(0))
    assert team.active.hp == team.active.max_hp and team.active.status is None
    assert "healing-wish" not in arena.hazards[0] and events[-1].kind == "healing-wish"
    assert resolve(team.active, foe_team.active, HEALING_WISH, arena).failed and team.active.hp > 0


def test_revival_blessing_brings_back_a_fainted_member_at_half_hp():
    arena = _Arena()
    team = _Team((mon("사용자", ("normal",)), mon("쓰러진", ("normal",))), arena=arena)
    foe_team = _Team((mon("상대", ("normal",)),), arena=arena, side=1)
    arena.teams = (team, foe_team)
    assert resolve(team.active, foe_team.active, REVIVAL_BLESSING, arena).failed
    fallen = battle._Fighter.enter(team.roster[1])
    fallen.hp = 0
    team.place(1, fallen)
    team.queue.remove(1)
    used = resolve(team.active, foe_team.active, REVIVAL_BLESSING, arena)
    assert used.changes == (Change(0, "쓰러진", "revive"),) and fallen.hp == fallen.max_hp // 2 and team.queue == [1]


def test_memento_drops_the_foe_and_faints_its_user():
    user, foe, arena = fighters()
    used = resolve(user, foe, MEMENTO, arena)
    assert used.attacker_fainted and user.hp == 0
    assert [(change.kind, change.stages) for change in used.changes] == [("attack", -2), ("special_attack", -2)]


def test_the_chooser_heals_at_half_hp_only_when_the_heal_outpaces_the_foe():
    teams, arena = pair((RECOVER, TACKLE))
    assert choose(teams, arena) == 1
    hurt(teams[0].active, 2)
    assert choose(teams, arena) == 0
    teams, arena = pair((RECOVER, TACKLE), foe_moves=(HUGE_HIT,))
    hurt(teams[0].active, 2)
    assert choose(teams, arena) == 1


def test_the_chooser_rests_only_at_a_quarter_and_sacrifices_only_with_a_member_to_come():
    teams, arena = pair((REST, TACKLE))
    hurt(teams[0].active, 2)
    assert choose(teams, arena) == 1
    hurt(teams[0].active, 5)
    assert choose(teams, arena) == 0
    teams, arena = pair((HEALING_WISH, MEMENTO, TACKLE), foe_moves=(HUGE_HIT,))
    hurt(teams[0].active, 5)
    assert choose(teams, arena) == 2
    teams[0].queue.append(0)
    assert choose(teams, arena) == 0


def test_every_healing_effect_has_a_korean_line():
    user, foe, arena = fighters()
    hurt(user)
    for move in (RECOVER, WISH, AQUA_RING, INGRAIN, PAIN_SPLIT, MEMENTO):
        used = resolve(user, foe, move, arena)
        line = narration._action_line(used, "🔵")
        assert used.effect and "→ 실패" not in line, move.name
        user.hp = max(1, user.max_hp // 4)
    assert "💚" in narration._action_line(resolve(user, foe, RECOVER, arena), "🔵")
