import random

from status_moves import choose, data_move, pair, put, resolve
from test_battle import TACKLE, mon

from ypoke import battle
from ypoke.battle import Move, _Arena

TAUNT, ENCORE, DISABLE, TORMENT, SPITE = data_move(269), data_move(227), data_move(50), data_move(259), data_move(180)
PERISH_SONG, DESTINY_BOND, GRUDGE, LEECH_SEED = data_move(195), data_move(194), data_move(288), data_move(73)
CURSE, NIGHTMARE, HEAL_BLOCK, IMPRISON = data_move(174), data_move(171), data_move(377), data_move(286)
LOCK_ON, FORESIGHT, MAGNET_RISE, POWDER = data_move(199), data_move(193), data_move(393), data_move(600)
MAGIC_COAT, TAR_SHOT, MUD_SPORT, FOCUS_ENERGY = data_move(277), data_move(749), data_move(300), data_move(116)
LASER_FOCUS, OCTOLOCK, ELECTRIFY = data_move(673), data_move(753), data_move(582)
GROWL, RECOVER, SPORE, SWORDS_DANCE = data_move(45), data_move(105), data_move(147), data_move(14)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)
THUNDER_SHOCK = Move("전기쇼크", "electric", 40, physical=False, accuracy=100)
EARTHQUAKE = Move("지진", "ground", 100, physical=True, accuracy=100)
DYNAMIC_PUNCH = Move("폭발펀치", "fighting", 100, physical=True, accuracy=50)
HUGE_HIT = Move("큰기술", "normal", 250, physical=True, accuracy=100)


def fighters(user_types=("normal",), foe_types=("normal",)):
    arena = _Arena()
    return put(mon("사용자", user_types), arena), put(mon("상대", foe_types), arena, 1), arena


def upkeep(user, foe, turn=1):
    events = []
    battle._volatile_upkeep(turn, (user, foe), events, random.Random(0))
    return events


def test_taunt_stops_status_moves_for_three_turns():
    user, foe, arena = fighters()
    assert resolve(user, foe, TAUNT, arena).effect == "taunt"
    assert resolve(foe, user, GROWL, arena).blocked == "taunt" and user.stages["attack"] == 0
    assert resolve(foe, user, TACKLE, arena).blocked == ""
    upkeep(user, foe, 1)
    upkeep(user, foe, 2)
    assert resolve(foe, user, GROWL, arena).blocked == "taunt"
    assert isinstance(upkeep(user, foe, 3)[-1], battle.VolatileEnd)
    assert resolve(foe, user, GROWL, arena).blocked == "" and user.stages["attack"] == -1


def test_encore_locks_the_foe_into_its_last_move_and_fails_with_none():
    teams, arena = pair((ENCORE, TACKLE), foe_moves=(TACKLE, HUGE_HIT))
    user, foe = teams[0].active, teams[1].active
    assert resolve(user, foe, ENCORE, arena).failed
    assert choose(teams, arena, side=1) == 1
    foe.last_used = 0
    assert resolve(user, foe, ENCORE, arena).effect == "encore"
    assert choose(teams, arena, side=1) == 0
    for turn in (1, 2, 3):
        upkeep(user, foe, turn)
    assert "encore" not in foe.volatiles and choose(teams, arena, side=1) == 1


def test_disable_and_torment_ban_the_foes_last_move_and_spite_drains_it():
    user, foe, arena = fighters()
    foe.combatant = foe.combatant.__class__(**{**foe.combatant.__dict__, "moves": (TACKLE, EMBER)})
    foe.pp = [move.pp for move in foe.combatant.moves]
    foe.last_used = 0
    resolve(user, foe, DISABLE, arena)
    assert battle._banned(foe, TACKLE) == "disable" and battle._banned(foe, EMBER) == ""
    user, foe, arena = fighters()
    foe.last_used = 0
    resolve(user, foe, TORMENT, arena)
    assert battle._banned(foe, TACKLE) == "torment"
    foe.last_used = None
    assert battle._banned(foe, TACKLE) == ""
    foe.last_used, foe.pp[0] = 0, 6
    assert resolve(user, foe, SPITE, arena).effect == "spite" and foe.pp[0] == 2
    foe.pp[0] = 0
    assert resolve(user, foe, SPITE, arena).failed


def test_perish_song_counts_both_down_and_knocks_them_out_after_three_more_turns():
    user, foe, arena = fighters()
    assert resolve(user, foe, PERISH_SONG, arena).effect == "perish-song"
    counts = [[event.count for event in upkeep(user, foe, turn)] for turn in (1, 2, 3)]
    assert counts == [[3, 3], [2, 2], [1, 1]] and user.hp > 0
    last = upkeep(user, foe, 4)
    assert [event.count for event in last] == [0, 0] and all(event.fainted for event in last)
    assert user.hp == foe.hp == 0


def test_destiny_bond_takes_the_foe_down_with_the_user_and_grudge_empties_its_move():
    teams, arena = pair((DESTINY_BOND, TACKLE), foe_moves=(HUGE_HIT,))
    user, foe = teams[0].active, teams[1].active
    assert resolve(user, foe, DESTINY_BOND, arena).effect == "destiny-bond"
    used = resolve(foe, user, HUGE_HIT, arena)
    assert used.knockout and used.attacker_fainted and foe.hp == 0
    assert arena.log[-1] == battle.VolatileEnd(1, 0, "사용자", "destiny-bond")
    teams, arena = pair((GRUDGE, TACKLE), foe_moves=(HUGE_HIT,))
    user, foe = teams[0].active, teams[1].active
    resolve(user, foe, GRUDGE, arena)
    resolve(foe, user, HUGE_HIT, arena)
    assert foe.hp > 0 and foe.pp[0] == 0


def test_destiny_bond_wears_off_and_fails_right_after_it_worked():
    user, foe, arena = fighters()
    resolve(user, foe, DESTINY_BOND, arena, turn=1)
    upkeep(user, foe, 1)
    upkeep(user, foe, 2)
    assert "destiny-bond" not in user.volatiles
    arena.turn = 2
    assert resolve(user, foe, DESTINY_BOND, arena, turn=2).failed


def test_leech_seed_drains_the_foe_to_the_user_and_misses_grass_types():
    teams, arena = pair((LEECH_SEED, TACKLE))
    user, foe = teams[0].active, teams[1].active
    resolve(user, foe, LEECH_SEED, arena, seed=1)
    user.hp = user.max_hp // 2
    seeded, healed = upkeep(user, foe)
    assert foe.hp == foe.max_hp - foe.max_hp // 8 and user.hp == user.max_hp // 2 + foe.max_hp // 8
    assert (seeded.kind, healed.kind) == ("leech-seed", "leech-seed-heal")
    teams, arena = pair((LEECH_SEED, TACKLE), foe_types=("grass",))
    assert resolve(teams[0].active, teams[1].active, LEECH_SEED, arena, seed=1).failed


def test_a_ghost_curse_costs_half_and_hurts_each_turn_and_any_other_trades_speed_for_power():
    user, foe, arena = fighters(user_types=("ghost",))
    assert resolve(user, foe, CURSE, arena).effect == "curse" and user.hp == user.max_hp - user.max_hp // 2
    upkeep(user, foe)
    assert foe.hp == foe.max_hp - foe.max_hp // 4
    user, foe, arena = fighters()
    resolve(user, foe, CURSE, arena)
    assert (user.stages["attack"], user.stages["defense"], user.stages["speed"]) == (1, 1, -1)


def test_nightmare_hurts_only_a_sleeping_foe():
    user, foe, arena = fighters()
    assert resolve(user, foe, NIGHTMARE, arena).failed
    foe.status, foe.sleep_left = "sleep", 2
    resolve(user, foe, NIGHTMARE, arena)
    upkeep(user, foe)
    assert foe.hp == foe.max_hp - foe.max_hp // 4
    foe.status = None
    assert upkeep(user, foe, 2) == [] and "nightmare" not in foe.volatiles


def test_heal_block_and_imprison_ban_moves():
    user, foe, arena = fighters()
    resolve(user, foe, HEAL_BLOCK, arena)
    assert battle._banned(foe, RECOVER) == "heal-block" and battle._banned(foe, TACKLE) == ""
    teams, arena = pair((IMPRISON, TACKLE), foe_moves=(TACKLE, EMBER))
    user, foe = teams[0].active, teams[1].active
    resolve(user, foe, IMPRISON, arena)
    assert battle._banned(foe, TACKLE) == "imprison" and battle._banned(foe, EMBER) == ""


def test_lock_on_and_foresight_make_hits_land():
    user, foe, arena = fighters()
    resolve(user, foe, LOCK_ON, arena)
    assert all(not resolve(user, foe, DYNAMIC_PUNCH, arena, seed=seed).missed for seed in range(20))
    user, foe, arena = fighters(foe_types=("ghost",))
    assert resolve(user, foe, TACKLE, arena).multiplier == 0
    resolve(user, foe, FORESIGHT, arena)
    assert resolve(user, foe, TACKLE, arena).multiplier == 1


def test_magnet_rise_floats_over_ground_moves():
    user, foe, arena = fighters()
    resolve(user, foe, MAGNET_RISE, arena)
    assert resolve(foe, user, EARTHQUAKE, arena).multiplier == 0


def test_powder_blows_up_a_fire_move_and_electrify_turns_a_move_electric():
    user, foe, arena = fighters()
    assert resolve(user, foe, POWDER, arena).effect == "powder"
    assert resolve(foe, user, EMBER, arena).blocked == "powder" and foe.hp == foe.max_hp - foe.max_hp // 4
    user, foe, arena = fighters(user_types=("ground",))
    resolve(user, foe, ELECTRIFY, arena)
    assert resolve(foe, user, TACKLE, arena).multiplier == 0
    foe.acted = True
    upkeep(user, foe)
    assert resolve(user, foe, ELECTRIFY, arena).failed


def test_magic_coat_bounces_a_status_move_back():
    user, foe, arena = fighters()
    resolve(user, foe, MAGIC_COAT, arena)
    resolve(foe, user, GROWL, arena)
    assert user.stages["attack"] == 0 and foe.stages["attack"] == -1
    assert arena.log[-1] == battle.VolatileEnd(1, 0, "사용자", "magic-coat")


def test_the_chooser_waits_with_magic_coat_only_for_a_foe_that_keeps_using_its_status_move():
    teams, arena = pair((MAGIC_COAT, TACKLE), foe_moves=(SPORE, TACKLE))
    user, foe = teams[0].active, teams[1].active
    assert choose(teams, arena) == 1
    foe.last_used = 0
    assert choose(teams, arena) == 0
    resolve(user, foe, MAGIC_COAT, arena)
    upkeep(user, foe)
    assert choose(teams, arena) == 1
    foe.pp[0] -= 1
    assert choose(teams, arena) == 0
    foe.status = "sleep"
    assert choose(teams, arena) == 1


def test_tar_shot_doubles_fire_damage_and_mud_sport_weakens_electric():
    user, foe, arena = fighters()
    resolve(user, foe, TAR_SHOT, arena)
    assert foe.stages["speed"] == -1 and resolve(user, foe, EMBER, arena).multiplier == 2
    user, foe, arena = fighters()
    resolve(foe, user, THUNDER_SHOCK, arena, seed=3)
    plain = user.max_hp - user.hp
    user.hp = user.max_hp
    resolve(user, foe, MUD_SPORT, arena)
    resolve(foe, user, THUNDER_SHOCK, arena, seed=3)
    assert user.max_hp - user.hp < plain / 2
    assert resolve(user, foe, MUD_SPORT, arena).failed


def test_octolock_lowers_both_defenses_each_turn():
    user, foe, arena = fighters()
    resolve(user, foe, OCTOLOCK, arena)
    upkeep(user, foe)
    assert (foe.stages["defense"], foe.stages["special_defense"]) == (-1, -1)


def test_focus_energy_and_laser_focus_raise_the_critical_hit_chance():
    user, foe, arena = fighters()
    resolve(user, foe, FOCUS_ENERGY, arena)
    assert sum(battle._field(user, "crit_stage")) == 2
    user, foe, arena = fighters()
    resolve(user, foe, LASER_FOCUS, arena)
    assert resolve(user, foe, TACKLE, arena).critical
    upkeep(user, foe, 1)
    upkeep(user, foe, 2)
    assert "laser-focus" not in user.volatiles


def test_the_chooser_taunts_a_foe_with_status_moves_and_never_twice():
    teams, arena = pair((TAUNT, TACKLE), foe_moves=(TACKLE,))
    assert choose(teams, arena) == 1
    teams, arena = pair((TAUNT, TACKLE), foe_moves=(SPORE, TACKLE))
    assert choose(teams, arena) == 0
    teams[1].active.volatiles["taunt"] = 2
    assert choose(teams, arena) == 1


def test_the_chooser_bonds_only_when_it_moves_first_and_the_foe_would_knock_it_out():
    teams, arena = pair((DESTINY_BOND, TACKLE), foe_moves=(HUGE_HIT,), speed=200)
    assert choose(teams, arena) == 0
    teams, arena = pair((DESTINY_BOND, TACKLE), foe_moves=(TACKLE,), speed=200)
    assert choose(teams, arena) == 1
    teams, arena = pair((DESTINY_BOND, TACKLE), foe_moves=(HUGE_HIT,), speed=1)
    assert choose(teams, arena) == 1


def test_the_chooser_sings_perish_song_only_with_more_members_standing():
    teams, arena = pair((PERISH_SONG, TACKLE))
    assert choose(teams, arena) == 1
    arena = _Arena()
    teams = (battle._Team((mon("사용자", ("normal",), moves=(PERISH_SONG, TACKLE)), mon("둘", ("normal",))), arena=arena),
             battle._Team((mon("상대", ("normal",)),), arena=arena, side=1))
    arena.teams = teams
    assert choose(teams, arena) == 0
