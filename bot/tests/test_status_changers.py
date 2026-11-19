from dataclasses import replace

from status_moves import choose, data_move, pair, put, resolve
from test_battle import TACKLE, mon

from ypoke.battle import Move, _Arena

CONVERSION, CONVERSION_2, CAMOUFLAGE, REFLECT_TYPE = data_move(160), data_move(176), data_move(293), data_move(513)
SOAK, MAGIC_POWDER, TRICK_OR_TREAT, FORESTS_CURSE = data_move(487), data_move(750), data_move(567), data_move(571)
ROLE_PLAY, SKILL_SWAP, ENTRAINMENT, SIMPLE_BEAM = data_move(272), data_move(285), data_move(494), data_move(493)
WORRY_SEED, GASTRO_ACID, DOODLE = data_move(388), data_move(380), data_move(867)
EMBER = Move("불꽃세례", "fire", 40, physical=False, accuracy=100)
WATER_GUN = Move("물대포", "water", 40, physical=False, accuracy=100)
THUNDER_SHOCK = Move("전기쇼크", "electric", 40, physical=False, accuracy=100)


def fighters(user_types=("normal",), foe_types=("normal",), user_ability=None, foe_ability=None, foe_moves=(TACKLE,)):
    arena = _Arena()
    user = put(mon("사용자", user_types), arena, ability=user_ability)
    foe = put(mon("상대", foe_types, moves=foe_moves), arena, 1, ability=foe_ability)
    return user, foe, arena


def test_conversion_takes_the_first_moves_type_and_switching_out_brings_the_old_one_back():
    user, foe, arena = fighters(user_types=("fire",))
    assert resolve(user, foe, CONVERSION, arena).effect == "conversion"
    assert user.combatant.types == ("normal",)
    assert resolve(user, foe, CONVERSION, arena).failed
    user.leave()
    assert user.combatant.types == ("fire",)


def test_conversion_2_takes_the_type_that_best_resists_the_foes_last_move():
    user, foe, arena = fighters(foe_moves=(EMBER, WATER_GUN))
    assert resolve(user, foe, CONVERSION_2, arena).failed
    foe.last_used = 0
    resolve(user, foe, CONVERSION_2, arena)
    assert user.combatant.types == ("dragon",)


def test_camouflage_follows_the_terrain_and_reflect_type_copies_the_foe():
    user, foe, arena = fighters(foe_types=("ghost", "steel"))
    arena.terrain = "grassy-terrain"
    resolve(user, foe, CAMOUFLAGE, arena)
    assert user.combatant.types == ("grass",)
    resolve(user, foe, REFLECT_TYPE, arena)
    assert user.combatant.types == ("ghost", "steel")


def test_a_terastallized_pokemon_keeps_its_type():
    user, foe, arena = fighters()
    foe.combatant = replace(foe.combatant, tera=True)
    assert resolve(user, foe, SOAK, arena).failed and foe.combatant.types == ("normal",)


def test_soak_and_magic_powder_replace_the_foes_types_and_grass_ignores_the_powder():
    user, foe, arena = fighters(foe_types=("fire", "flying"))
    assert resolve(user, foe, SOAK, arena).effect == "soak" and foe.combatant.types == ("water",)
    assert resolve(user, foe, SOAK, arena).failed
    user, foe, arena = fighters(foe_types=("grass",))
    assert resolve(user, foe, MAGIC_POWDER, arena).failed


def test_an_added_type_replaces_the_one_added_before():
    user, foe, arena = fighters(foe_types=("water",))
    resolve(user, foe, TRICK_OR_TREAT, arena)
    assert foe.combatant.types == ("water", "ghost")
    resolve(user, foe, FORESTS_CURSE, arena)
    assert foe.combatant.types == ("water", "grass")
    assert resolve(user, foe, FORESTS_CURSE, arena).failed


def test_ability_moves_copy_swap_hand_over_replace_and_suppress():
    user, foe, arena = fighters(user_ability="blaze", foe_ability="levitate")
    resolve(user, foe, ROLE_PLAY, arena)
    assert (user.ability, foe.ability) == ("levitate", "levitate")
    assert resolve(user, foe, ROLE_PLAY, arena).failed
    user, foe, arena = fighters(user_ability="blaze", foe_ability="levitate")
    resolve(user, foe, SKILL_SWAP, arena)
    assert (user.ability, foe.ability) == ("levitate", "blaze")
    resolve(user, foe, ENTRAINMENT, arena)
    assert foe.ability == "levitate"
    resolve(user, foe, SIMPLE_BEAM, arena)
    assert foe.ability == "simple"
    resolve(user, foe, GASTRO_ACID, arena)
    assert foe.ability is None and resolve(user, foe, GASTRO_ACID, arena).failed
    foe.leave()
    assert foe.ability == "levitate"


def test_worry_seed_wakes_the_foe_and_fixed_abilities_never_move():
    user, foe, arena = fighters(foe_ability="levitate")
    foe.status, foe.sleep_left = "sleep", 2
    resolve(user, foe, WORRY_SEED, arena)
    assert foe.ability == "insomnia" and foe.status is None
    user, foe, arena = fighters(user_ability="blaze", foe_ability="multitype")
    assert all(resolve(user, foe, move, arena).failed for move in (ROLE_PLAY, SKILL_SWAP, ENTRAINMENT, GASTRO_ACID))
    user, foe, arena = fighters(user_ability="disguise", foe_ability="levitate")
    assert resolve(user, foe, DOODLE, arena).failed and resolve(user, foe, ENTRAINMENT, arena).failed


def test_the_chooser_changes_its_type_only_to_dodge_the_foes_attacks():
    teams, arena = pair((REFLECT_TYPE, TACKLE), foe_moves=(EMBER,), user_types=("grass",), foe_types=("water",))
    assert choose(teams, arena) == 0
    teams, arena = pair((REFLECT_TYPE, TACKLE), foe_moves=(EMBER,), user_types=("water",), foe_types=("grass",))
    assert choose(teams, arena) == 1


def test_the_chooser_soaks_a_foe_only_when_its_attacks_hit_the_new_type_harder():
    teams, arena = pair((SOAK, THUNDER_SHOCK), foe_types=("ground",))
    assert choose(teams, arena) == 0
    teams, arena = pair((SOAK, EMBER), foe_types=("grass",))
    assert choose(teams, arena) == 1


def test_the_chooser_takes_a_working_ability_only_when_its_own_does_nothing():
    teams, arena = pair((ROLE_PLAY, TACKLE))
    put_abilities(teams, "run-away", "levitate")
    assert choose(teams, arena) == 0
    put_abilities(teams, "blaze", "levitate")
    assert choose(teams, arena) == 1
    teams, arena = pair((GASTRO_ACID, TACKLE))
    put_abilities(teams, "blaze", "levitate")
    assert choose(teams, arena) == 0
    put_abilities(teams, "blaze", "run-away")
    assert choose(teams, arena) == 1


def put_abilities(teams, mine, theirs):
    for team, ability in zip(teams, (mine, theirs)):
        team.active.combatant = replace(team.active.combatant, ability=ability)
