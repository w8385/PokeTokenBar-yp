import random

from status_moves import choose, data_move
from test_battle import TACKLE, mon

from ypoke import battle
from ypoke.battle import Move, _Arena, _Team

TELEPORT, BATON_PASS, PARTING_SHOT, CHILLY_RECEPTION = data_move(100), data_move(226), data_move(575), data_move(881)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)


def squad(user_moves, foe_moves=(TACKLE,), bench=True, user_types=("grass",)):
    arena = _Arena()
    members = (mon("사용자", user_types, moves=tuple(user_moves)),) + (mon("후속", ("normal",)),) * bench
    teams = (_Team(members, arena=arena), _Team((mon("상대", ("normal",), moves=tuple(foe_moves)),), arena=arena, side=1))
    arena.teams = teams
    return teams, arena


def act(teams, arena, index=0):
    """The user's move and, when it switches the user out, the member that came in."""
    fighters = (teams[0].active, teams[1].active)
    used = battle._act(1, 0, fighters, index, arena.weather, random.Random(0), arena)
    if battle._pivots(teams[0], used, index):
        battle._pivot(teams, 0, 1, arena, arena.weather, random.Random(0), [])
    return used, teams[0].active


def test_teleport_switches_the_user_out_and_fails_with_no_member_waiting():
    teams, arena = squad((TELEPORT,))
    used, active = act(teams, arena)
    assert used.effect == "teleport" and active.combatant.name == "후속"
    teams, arena = squad((TELEPORT,), bench=False)
    used, active = act(teams, arena)
    assert used.failed and active.combatant.name == "사용자"


def test_baton_pass_hands_stages_confusion_and_a_substitute_to_the_next_member():
    teams, arena = squad((BATON_PASS,))
    user = teams[0].active
    user.stages["attack"], user.confusion_left = 2, 2
    user.volatiles.update({"substitute": 30, "torment": True})
    used, active = act(teams, arena)
    assert used.effect == "baton-pass" and active.combatant.name == "후속"
    assert active.stages["attack"] == 2 and active.confusion_left == 1
    assert active.volatiles == {"substitute": 30} and "baton-pass" not in arena.hazards[0]


def test_parting_shot_lowers_both_attacks_and_switches_but_stays_in_when_no_drop_lands():
    teams, arena = squad((PARTING_SHOT,))
    foe = teams[1].active
    used, active = act(teams, arena)
    assert (foe.stages["attack"], foe.stages["special_attack"]) == (-1, -1) and active.combatant.name == "후속"
    teams, arena = squad((PARTING_SHOT,))
    arena.sides[1]["mist"] = 5
    used, active = act(teams, arena)
    assert used.failed and active.combatant.name == "사용자"
    teams, arena = squad((PARTING_SHOT,))
    teams[1].active.stages.update(attack=-6, special_attack=-6)
    used, active = act(teams, arena)
    assert used.failed and active.combatant.name == "사용자"


def test_parting_shot_is_a_sound_move_that_passes_a_substitute():
    teams, arena = squad((PARTING_SHOT,))
    teams[1].active.volatiles["substitute"] = 30
    act(teams, arena)
    assert teams[1].active.stages["attack"] == -1


def test_chilly_reception_starts_snow_and_switches_out_even_when_it_already_snows():
    teams, arena = squad((CHILLY_RECEPTION,))
    used, active = act(teams, arena)
    assert used.effect == "chilly-reception" and arena.weather.kind == "snow" and active.combatant.name == "후속"
    teams, arena = squad((CHILLY_RECEPTION,))
    arena.weather.kind, arena.weather.turns_left = "snow", 1
    used, active = act(teams, arena)
    assert used.effect == "chilly-reception-dry" and arena.weather.turns_left == 1 and active.combatant.name == "후속"


def test_the_chooser_switches_out_under_a_super_effective_threat_only_with_a_member_waiting():
    for move in (TELEPORT, CHILLY_RECEPTION, PARTING_SHOT):
        teams, arena = squad((move, TACKLE), (EMBER,))
        assert choose(teams, arena) == 0, move.name
        teams, arena = squad((move, TACKLE), (TACKLE,))
        assert choose(teams, arena) == 1, move.name
        teams, arena = squad((move, TACKLE), (EMBER,), bench=False)
        assert choose(teams, arena) == 1, move.name


def test_the_chooser_skips_parting_shot_when_the_drops_would_not_matter():
    teams, arena = squad((PARTING_SHOT, TACKLE), (EMBER,))
    teams[1].active.stages.update(attack=-6, special_attack=-6)
    assert choose(teams, arena) == 1


def test_the_chooser_passes_boosts_or_a_substitute_but_never_a_curse_on_itself():
    teams, arena = squad((BATON_PASS, TACKLE))
    assert choose(teams, arena) == 1
    user = teams[0].active
    user.stages["attack"] = 2
    assert choose(teams, arena) == 0
    user.volatiles["leech-seed"] = True
    assert choose(teams, arena) == 1
    teams, arena = squad((BATON_PASS, TACKLE))
    teams[0].active.volatiles["substitute"] = 20
    assert choose(teams, arena) == 0
    teams, arena = squad((BATON_PASS, TACKLE), bench=False)
    teams[0].active.stages["attack"] = 2
    assert choose(teams, arena) == 1
