import random
from dataclasses import replace

from attacks import attack, duel, hit
from status_moves import data_move, resolve
from test_battle import TACKLE, mon

from ypoke import battle
from ypoke.battle import simulate
from ypoke.effects import hooks
from ypoke.move_power import Scene

THIEF, PLUCK, INCINERATE, FELL_STINGER = attack(168), attack(365), attack(510), attack(565)
SPECTRAL_THIEF, CLEAR_SMOG, SMACK_DOWN, THOUSAND_ARROWS = attack(712), attack(499), attack(479), attack(614)
THROAT_CHOP, SALT_CURE, SYRUP_BOMB, PSYCHIC_NOISE = attack(675), attack(864), attack(903), attack(917)
SAPPY_SEED, EERIE_SPELL, CORE_ENFORCER, BURNING_JEALOUSY = attack(738), attack(826), attack(687), attack(807)
ALLURING_VOICE, BURN_UP, SMELLING_SALTS, WAKE_UP_SLAP = attack(914), attack(682), attack(265), attack(358)
FALSE_SWIPE, PLASMA_FISTS, GRAV_APPLE, KNOCK_OFF, EARTHQUAKE = (attack(206), attack(721), attack(788), attack(282),
                                                               attack(89))
HYPER_VOICE, RECOVER = data_move(304), data_move(105)


def test_thief_takes_the_targets_item_only_when_the_user_holds_none():
    user, foe, arena = duel()
    foe.item = "leftovers"
    hit(user, foe, THIEF, arena)
    assert (user.item, foe.item) == ("leftovers", None)
    user, foe, arena = duel()
    user.item, foe.item = "life-orb", "leftovers"
    hit(user, foe, THIEF, arena)
    assert (user.item, foe.item) == ("life-orb", "leftovers")


def test_item_moves_change_only_the_battle_copy_never_the_saved_pokemon():
    thief = replace(mon("도둑", ("dark",), moves=(THIEF, KNOCK_OFF)), item=None)
    holder = replace(mon("주인", ("normal",), moves=(TACKLE,)), item="leftovers")
    for seed in range(5):
        simulate((thief, holder), seed)
        assert (thief.item, holder.item) == (None, "leftovers")


def test_pluck_eats_the_targets_berry_for_the_user():
    user, foe, arena = duel()
    foe.item = "sitrus-berry"
    user.hp = user.max_hp // 2
    resolve(user, foe, PLUCK, arena)
    assert foe.item is None and user.hp > user.max_hp // 2 and user.item is None


def test_incinerate_burns_a_berry_but_not_another_item():
    user, foe, arena = duel()
    foe.item = "sitrus-berry"
    hit(user, foe, INCINERATE, arena)
    assert foe.item is None
    foe.item = "leftovers"
    hit(user, foe, INCINERATE, arena)
    assert foe.item == "leftovers"


def test_fell_stinger_raises_attack_by_three_only_on_a_knockout():
    user, foe, arena = duel()
    hit(user, foe, FELL_STINGER, arena)
    assert user.stages["attack"] == 0
    foe.hp = 1
    resolve(user, foe, FELL_STINGER, arena)
    assert foe.hp == 0 and user.stages["attack"] == 3


def test_spectral_thief_takes_the_raised_stages_before_its_damage():
    user, foe, arena = duel(foe_types=("psychic",))
    foe.stages.update(attack=2, defense=-1)
    action = hit(user, foe, SPECTRAL_THIEF, arena)
    assert (user.stages["attack"], foe.stages["attack"], foe.stages["defense"]) == (2, 0, -1)
    assert [(change.kind, change.stages) for change in action.changes] == [("attack", 2)]


def test_spectral_thief_steals_nothing_from_an_immune_target():
    user, foe, arena = duel(foe_types=("normal",))
    foe.stages["attack"] = 2
    hit(user, foe, SPECTRAL_THIEF, arena)
    assert (user.stages["attack"], foe.stages["attack"]) == (0, 2)


def test_clear_smog_resets_the_targets_stages():
    user, foe, arena = duel()
    foe.stages.update(attack=2, speed=-1)
    action = hit(user, foe, CLEAR_SMOG, arena)
    assert set(foe.stages.values()) == {0} and [change.kind for change in action.changes] == ["reset"]


def test_smack_down_grounds_a_flying_target_so_ground_moves_hit_it():
    user, foe, arena = duel(foe_types=("flying",))
    assert resolve(user, foe, EARTHQUAKE, arena).multiplier == 0
    action = hit(user, foe, SMACK_DOWN, arena)
    assert [change.kind for change in action.changes] == ["grounded"]
    assert resolve(user, foe, EARTHQUAKE, arena).multiplier == 1


def test_thousand_arrows_hits_a_flying_target_neutrally_and_grounds_it():
    user, foe, arena = duel(foe_types=("flying", "fire"))
    action = hit(user, foe, THOUSAND_ARROWS, arena)
    assert action.multiplier == 2 and "smack-down" in foe.volatiles


def test_throat_chop_bars_sound_moves_through_the_next_turn():
    user, foe, arena = duel()
    hit(user, foe, THROAT_CHOP, arena)
    assert resolve(foe, user, HYPER_VOICE, arena).blocked == "throat-chop"
    assert resolve(foe, user, TACKLE, arena).blocked == ""
    for turn in (1, 2):
        battle._volatile_upkeep(turn, (user, foe), [], random.Random(0))
    assert "throat-chop" not in foe.volatiles


def test_salt_cure_takes_an_eighth_and_a_quarter_from_water_and_steel_types():
    for types, share in ((("normal",), 8), (("water",), 4), (("steel", "fire"), 4)):
        user, foe, arena = duel(foe_types=types)
        hit(user, foe, SALT_CURE, arena)
        before = foe.hp
        events = []
        battle._volatile_upkeep(1, (user, foe), events, random.Random(0))
        assert before - foe.hp == foe.max_hp // share and [event.kind for event in events] == ["salt-cure"]


def test_syrup_bomb_lowers_speed_at_three_ends_of_turn_then_stops():
    user, foe, arena = duel()
    hit(user, foe, SYRUP_BOMB, arena)
    for turn in range(1, 6):
        battle._volatile_upkeep(turn, (user, foe), [], random.Random(0))
    assert foe.stages["speed"] == -3 and "syrup-bomb" not in foe.volatiles


def test_psychic_noise_blocks_healing_for_two_turns():
    user, foe, arena = duel()
    hit(user, foe, PSYCHIC_NOISE, arena)
    assert resolve(foe, user, RECOVER, arena).blocked == "heal-block"
    for turn in (1, 2):
        battle._volatile_upkeep(turn, (user, foe), [], random.Random(0))
    assert "heal-block" not in foe.volatiles


def test_sappy_seed_seeds_the_target_but_not_a_grass_type():
    user, foe, arena = duel()
    hit(user, foe, SAPPY_SEED, arena)
    assert "leech-seed" in foe.volatiles
    user, foe, arena = duel(foe_types=("grass",))
    hit(user, foe, SAPPY_SEED, arena)
    assert "leech-seed" not in foe.volatiles


def test_eerie_spell_takes_three_pp_from_the_targets_last_move():
    user, foe, arena = duel()
    foe.last_used, foe.pp[0] = 0, 10
    hit(user, foe, EERIE_SPELL, arena)
    assert foe.pp[0] == 7


def test_core_enforcer_takes_the_ability_of_a_target_that_already_moved():
    user, foe, arena = duel()
    foe.combatant = replace(foe.combatant, ability="intimidate")
    hit(user, foe, CORE_ENFORCER, arena)
    assert foe.ability == "intimidate"
    foe.acted = True
    hit(user, foe, CORE_ENFORCER, arena)
    assert foe.ability is None


def test_burning_jealousy_and_alluring_voice_act_only_on_a_target_raised_this_turn():
    for move, landed in ((BURNING_JEALOUSY, lambda foe: foe.status == "burn"),
                         (ALLURING_VOICE, lambda foe: foe.confusion_left > 0)):
        user, foe, arena = duel()
        foe.turn_stages = dict(foe.stages)
        hit(user, foe, move, arena)
        assert not landed(foe)
        foe.stages["attack"] = 1
        hit(user, foe, move, arena)
        assert landed(foe)


def test_burn_up_fails_without_the_fire_type_and_takes_it_after_a_hit():
    user, foe, arena = duel()
    assert resolve(user, foe, BURN_UP, arena).failed
    user, foe, arena = duel(user_types=("fire", "flying"))
    action = hit(user, foe, BURN_UP, arena)
    assert user.combatant.types == ("flying",) and [change.kind for change in action.changes] == ["lost-fire"]
    assert resolve(user, foe, BURN_UP, arena).failed


def test_smelling_salts_and_wake_up_slap_double_on_their_status_and_cure_it():
    for move, status in ((SMELLING_SALTS, "paralysis"), (WAKE_UP_SLAP, "sleep")):
        user, foe, arena = duel()
        plain = hit(user, foe, move, arena, seed=3).defender_hp
        foe.status, foe.sleep_left = status, 2
        doubled = hit(user, foe, move, arena, seed=3)
        assert 100 - doubled.defender_hp > (100 - plain) * 1.8 and foe.status is None


def test_false_swipe_leaves_one_hp():
    user, foe, arena = duel()
    foe.hp = 1
    resolve(user, foe, FALSE_SWIPE, arena)
    assert foe.hp == 1


def test_plasma_fists_turns_normal_moves_electric_for_the_turn():
    user, foe, arena = duel(user_types=("ground",))
    assert resolve(foe, user, TACKLE, arena).multiplier == 1
    hit(user, foe, PLASMA_FISTS, arena)
    assert resolve(foe, user, TACKLE, arena).multiplier == 0


def test_grav_apple_hits_harder_under_gravity():
    user, foe, arena = duel()
    plain = hooks.move(GRAV_APPLE, "base_power", 80, _scene(user, foe))
    arena.gravity = 5
    assert (plain, hooks.move(GRAV_APPLE, "base_power", 80, _scene(user, foe))) == (80, 120)


def test_a_substitute_spares_its_holder_the_states_an_attack_leaves():
    for move in (SALT_CURE, THROAT_CHOP, SAPPY_SEED):
        user, foe, arena = duel()
        foe.volatiles["substitute"] = foe.max_hp
        resolve(user, foe, move, arena)
        assert not {"salt-cure", "throat-chop", "leech-seed"} & set(foe.volatiles)


def _scene(user, foe):
    return Scene(user, foe, None, 1.0, None, 1)
