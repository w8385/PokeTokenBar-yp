import random
from dataclasses import replace

from status_moves import choose, data_move, pair, put, resolve
from test_battle import EMBER, FLAMETHROWER, SURF, TACKLE, mon

from ypoke import battle, battle_data
from ypoke.battle import Move, _Arena, _Team
from ypoke.effects import callers
from ypoke.effects.changers import reshape

METRONOME, MIRROR_MOVE, COPYCAT, SLEEP_TALK = data_move(118), data_move(119), data_move(383), data_move(214)
ASSIST, ME_FIRST, NATURE_POWER = data_move(274), data_move(382), data_move(267)
MIMIC, SKETCH, TRANSFORM = data_move(102), data_move(166), data_move(144)
PROTECT, SWORDS_DANCE = data_move(182), data_move(14)
BIG_HIT = Move("큰기술", "normal", 150, physical=False, accuracy=100)


def fighters(user_moves=(TACKLE,), foe_moves=(TACKLE,), arena=None, foe_types=("normal",), **foe_stats):
    arena = arena or _Arena()
    user = put(mon("사용자", ("normal",), moves=tuple(user_moves)), arena)
    foe = put(mon("상대", foe_types, moves=tuple(foe_moves), **foe_stats), arena, 1)
    return user, foe, arena


def test_metronome_calls_a_random_move_the_battle_runs_and_names_itself_on_the_action():
    pool = callers.metronome_pool()
    entries = battle_data.table("moves")
    assert pool and all(not battle_data.is_todo(entries[str(move.id)]) for move in pool)
    assert not {move.id for move in pool} & {118, 182, 383, 144, 165}
    user, foe, arena = fighters()
    used = resolve(user, foe, METRONOME, arena, seed=3)
    assert used.via == METRONOME.name and used.move in {move.name for move in pool} and user.pp[0] == METRONOME.pp - 1


def test_mirror_move_uses_the_foes_last_move_and_fails_without_one_or_on_a_guard():
    user, foe, arena = fighters(foe_moves=(SURF, PROTECT))
    assert resolve(user, foe, MIRROR_MOVE, arena).failed
    foe.last_used = 0
    used = resolve(user, foe, MIRROR_MOVE, arena)
    assert used.move == SURF.name and used.via == MIRROR_MOVE.name and foe.hp < foe.max_hp
    foe.last_used = 1
    assert resolve(user, foe, MIRROR_MOVE, arena).failed


def test_copycat_uses_the_last_move_either_side_used():
    user, foe, arena = fighters()
    assert resolve(user, foe, COPYCAT, arena).failed
    arena.last_move = SWORDS_DANCE
    used = resolve(user, foe, COPYCAT, arena)
    assert used.move == SWORDS_DANCE.name and user.stages["attack"] == 2


def test_sleep_talk_uses_another_own_move_while_asleep_and_fails_awake():
    user, foe, arena = fighters(user_moves=(SLEEP_TALK, FLAMETHROWER))
    assert resolve(user, foe, SLEEP_TALK, arena).failed
    user.status, user.sleep_left = "sleep", 2
    used = resolve(user, foe, SLEEP_TALK, arena)
    assert used.move == FLAMETHROWER.name and used.via == SLEEP_TALK.name and user.sleep_left == 1
    user.combatant = replace(user.combatant, moves=(SLEEP_TALK, PROTECT))
    assert resolve(user, foe, SLEEP_TALK, arena).failed


def test_assist_calls_a_move_of_another_member_and_fails_alone():
    arena = _Arena()
    team = _Team((mon("사용자", ("normal",), moves=(ASSIST,)), mon("동료", ("water",), moves=(SURF, PROTECT))),
                 arena=arena)
    foes = _Team((mon("상대", ("normal",)),), arena=arena, side=1)
    arena.teams = (team, foes)
    used = battle._act(1, 0, (team.active, foes.active), 0, arena.weather, random.Random(0), arena)
    assert used.move == SURF.name and used.via == ASSIST.name
    teams, arena = pair((ASSIST,))
    assert battle._act(1, 0, (teams[0].active, teams[1].active), 0, arena.weather, random.Random(0), arena).failed


def test_me_first_uses_the_foes_picked_attack_harder_but_fails_once_the_foe_acted_or_on_a_status_pick():
    user, foe, arena = fighters(foe_moves=(SURF, SWORDS_DANCE))
    plain = resolve(user, foe, SURF, arena)
    foe.hp, foe.choice = foe.max_hp, 0
    used = resolve(user, foe, ME_FIRST, arena)
    assert used.move == SURF.name and 100 - used.defender_hp > 100 - plain.defender_hp
    foe.acted = True
    assert resolve(user, foe, ME_FIRST, arena).failed
    foe.acted, foe.choice = False, 1
    assert resolve(user, foe, ME_FIRST, arena).failed


def test_nature_power_turns_into_the_terrains_move_or_tri_attack():
    user, foe, arena = fighters()
    assert resolve(user, foe, NATURE_POWER, arena).move == data_move(161).name
    arena.terrain = "electric-terrain"
    assert resolve(user, foe, NATURE_POWER, arena).move == data_move(85).name


def test_mimic_copies_the_foes_last_move_with_full_pp_until_the_user_switches_out():
    user, foe, arena = fighters(user_moves=(MIMIC, TACKLE), foe_moves=(SURF,))
    foe.last_used = 0
    assert resolve(user, foe, MIMIC, arena).effect == "mimic"
    assert user.combatant.moves[0] == SURF and user.pp[0] == SURF.pp
    user.leave()
    assert user.combatant.moves[0] == MIMIC and user.pp[0] == MIMIC.pp - 1


def test_mimic_fails_on_a_move_the_user_knows_or_a_caller():
    user, foe, arena = fighters(user_moves=(MIMIC, TACKLE), foe_moves=(TACKLE, METRONOME))
    foe.last_used = 0
    assert resolve(user, foe, MIMIC, arena).failed
    foe.last_used = 1
    assert resolve(user, foe, MIMIC, arena).failed


def test_sketch_keeps_the_copied_move_through_a_switch_but_the_saved_party_keeps_sketch():
    saved = mon("사용자", ("normal",), moves=(SKETCH, TACKLE))
    arena = _Arena()
    user, foe = put(saved, arena), put(mon("상대", ("normal",), moves=(SURF,)), arena, 1)
    reshape(user, types=("water",))
    foe.last_used = 0
    used = battle._resolve(1, 0, (user, foe), 0, arena.weather, random.Random(0), arena)
    assert used.effect == "sketch"
    user.leave()
    assert user.combatant.moves[0] == SURF and user.pp[0] == SURF.pp and user.combatant.types == ("normal",)
    assert saved.moves[0] == SKETCH


def test_transform_copies_the_foe_but_its_hp_until_the_user_switches_out():
    user, foe, arena = fighters(user_moves=(TRANSFORM,), foe_moves=(SURF, EMBER), foe_types=("water",), attack=150)
    foe.stages["attack"] = 2
    hp, stats = user.hp, dict(user.stats)
    assert resolve(user, foe, TRANSFORM, arena).effect == "transform"
    assert user.combatant.types == ("water",) and user.stats == foe.stats and user.stages["attack"] == 2
    assert user.combatant.moves == (SURF, EMBER) and user.pp == [5, 5] and user.hp == hp
    user.leave()
    assert user.combatant.moves == (TRANSFORM,) and user.stats == stats and user.combatant.types == ("normal",)


def test_transform_fails_on_a_substitute_and_on_a_second_use():
    user, foe, arena = fighters(user_moves=(TRANSFORM,))
    foe.volatiles["substitute"] = 20
    assert resolve(user, foe, TRANSFORM, arena).failed
    del foe.volatiles["substitute"]
    resolve(user, foe, TRANSFORM, arena)
    assert resolve(user, foe, TRANSFORM, arena).failed


def test_the_chooser_calls_a_move_only_when_it_beats_the_users_best_attack():
    teams, arena = pair((MIRROR_MOVE, TACKLE), (FLAMETHROWER,), foe_types=("grass",))
    assert choose(teams, arena) == 1
    teams[1].active.last_used = 0
    assert choose(teams, arena) == 0
    teams, arena = pair((NATURE_POWER, TACKLE))
    assert choose(teams, arena) == 0
    teams, arena = pair((NATURE_POWER, BIG_HIT))
    assert choose(teams, arena) == 1


def test_the_chooser_uses_metronome_or_assist_only_when_no_attack_can_hurt_the_foe():
    teams, arena = pair((METRONOME, TACKLE))
    assert choose(teams, arena) == 1
    teams, arena = pair((METRONOME, TACKLE), foe_types=("ghost",))
    assert choose(teams, arena) == 0
    teams, arena = pair((ASSIST, TACKLE), foe_types=("ghost",))
    assert choose(teams, arena) == 1
    arena = _Arena()
    team = _Team((mon("사용자", ("normal",), moves=(ASSIST, TACKLE)), mon("동료", ("water",), moves=(SURF,))),
                 arena=arena)
    arena.teams = (team, _Team((mon("상대", ("ghost",)),), arena=arena, side=1))
    assert choose(arena.teams, arena) == 0


def test_the_chooser_talks_in_its_sleep_and_copies_only_a_stronger_move():
    teams, arena = pair((SLEEP_TALK, TACKLE))
    assert choose(teams, arena) == 1
    teams[0].active.status, teams[0].active.sleep_left = "sleep", 2
    assert choose(teams, arena) == 0
    teams, arena = pair((MIMIC, TACKLE), (SURF,))
    assert choose(teams, arena) == 1
    teams[1].active.last_used = 0
    assert choose(teams, arena) == 0


def test_the_chooser_transforms_into_a_stronger_foe_only_once():
    teams, arena = pair((TRANSFORM, TACKLE))
    assert choose(teams, arena) == 1
    teams, arena = pair((TRANSFORM, TACKLE), (TACKLE,))
    teams[1].active.stats = {key: value * 2 for key, value in teams[1].active.stats.items()}
    assert choose(teams, arena) == 0
    teams[0].active.volatiles["transform"] = True
    assert choose(teams, arena) == 1


def test_the_chooser_goes_first_with_me_first_against_a_strong_foe_attack():
    teams, arena = pair((ME_FIRST, TACKLE), (FLAMETHROWER,), foe_types=("grass",))
    teams[0].active.stats["speed"] = 300
    assert choose(teams, arena) == 0
    teams[0].active.stats["speed"] = 1
    assert choose(teams, arena) == 1
