import random

from attacks import attack, draws, duel, first_seed, hit
from status_moves import data_move, resolve
from test_battle import TACKLE

from ypoke import battle
from ypoke.effects import hooks

IRON_HEAD, TRI_ATTACK, SECRET_POWER, MUD_SLAP = attack(442), attack(161), attack(290), attack(189)
SCALD, SURF, PSYSHIELD_BASH, MALIGNANT_CHAIN, DIRE_CLAW = attack(503), attack(57), attack(828), attack(919), attack(827)
SUBSTITUTE = data_move(164)


def test_a_flinch_stops_a_foe_that_has_not_moved_yet_and_wears_off_at_the_end_of_the_turn():
    user, foe, arena = duel()
    seed = first_seed(lambda seed: (hit(user, foe, IRON_HEAD, arena, seed), "flinch" in foe.volatiles)[1])
    assert resolve(foe, user, TACKLE, arena).blocked == "flinch"
    battle._volatile_upkeep(1, (user, foe), [], random.Random(0))
    assert "flinch" not in foe.volatiles
    foe.acted = True
    for seed in range(seed, seed + 50):
        hit(user, foe, IRON_HEAD, arena, seed)
        assert "flinch" not in foe.volatiles


def test_a_flinch_is_drawn_at_the_moves_own_chance():
    user, foe, arena = duel()
    hooks.move(IRON_HEAD, "secondary", user, foe, 0, draws(0.31))
    assert "flinch" not in foe.volatiles
    hooks.move(IRON_HEAD, "secondary", user, foe, 0, draws(0.29))
    assert "flinch" in foe.volatiles


def test_a_substitute_spares_its_holder_the_flinch():
    for seed in range(50):
        user, foe, arena = duel()
        resolve(foe, user, SUBSTITUTE, arena)
        resolve(user, foe, IRON_HEAD, arena, seed=seed)
        assert "flinch" not in foe.volatiles


def test_tri_attack_burns_freezes_or_paralyzes_but_never_a_type_immune_to_the_draw():
    landed = set()
    for seed in range(300):
        user, foe, arena = duel()
        hit(user, foe, TRI_ATTACK, arena, seed)
        landed.add(foe.status)
    assert landed == {None, "burn", "freeze", "paralysis"}
    for seed in range(300):
        user, foe, arena = duel(foe_types=("electric",))
        hit(user, foe, TRI_ATTACK, arena, seed)
        assert foe.status != "paralysis"


def test_dire_claw_draws_its_fifty_percent_and_picks_poison_paralysis_or_sleep():
    user, foe, arena = duel()
    assert hooks.move(DIRE_CLAW, "secondary", user, foe, 0, draws(0.51)) == ()
    changes = hooks.move(DIRE_CLAW, "secondary", user, foe, 0, draws(0.49))
    assert [change.kind for change in changes] == [foe.status] and foe.status in ("poison", "paralysis", "sleep")


def test_secret_power_paralyzes_outside_a_terrain_and_lowers_speed_in_psychic_terrain():
    user, foe, arena = duel()
    hooks.move(SECRET_POWER, "secondary", user, foe, 0, draws(0.0))
    assert foe.status == "paralysis"
    user, foe, arena = duel()
    arena.terrain = "psychic-terrain"
    hooks.move(SECRET_POWER, "secondary", user, foe, 0, draws(0.0))
    assert foe.status is None and foe.stages["speed"] == -1


def test_mud_slap_lowers_accuracy_and_the_gen_9_moves_take_their_filled_meta():
    user, foe, arena = duel()
    hit(user, foe, MUD_SLAP, arena)
    assert foe.stages["accuracy"] == -1
    hit(user, foe, PSYSHIELD_BASH, arena)
    assert user.stages["defense"] == 1
    assert MALIGNANT_CHAIN.ailment == "toxic" and MALIGNANT_CHAIN.ailment_chance == 50


def test_scald_thaws_its_frozen_user_where_surf_stays_frozen():
    for move, thawed in ((SCALD, True), (SURF, False)):
        user, foe, arena = duel()
        user.status = "freeze"
        action = resolve(user, foe, move, arena, seed=first_seed(lambda seed: random.Random(seed).random() >= 0.2))
        assert (user.status is None) == thawed and (action.blocked == "freeze") != thawed


def test_scald_thaws_a_frozen_target():
    user, foe, arena = duel()
    foe.status = "freeze"
    changes = battle._secondary_effects(0, SCALD, user, foe, draws(), True)[0]
    assert foe.status is None and [change.kind for change in changes] == ["thaw"]
