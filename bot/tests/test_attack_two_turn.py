import random

from attacks import attack, duel
from status_moves import choose, data_move, pair, resolve, weather
from test_battle import TACKLE

from ypoke import battle, narration
from ypoke.battle import Action, Change

SOLAR_BEAM, SKULL_BASH, ELECTRO_SHOT, SKY_ATTACK = attack(76), attack(130), attack(905), attack(143)
FLY, DIG, DIVE, PHANTOM_FORCE = attack(19), attack(91), attack(291), attack(566)
GUST, EARTHQUAKE, SURF, THUNDER, SMACK_DOWN = attack(16), attack(89), attack(57), attack(87), attack(479)
HYPER_BEAM = attack(63)
THUNDER_WAVE = data_move(86)


def act(user, foe, arena, index=0, seed=0, turn=1, sky=None):
    fighters = (user, foe) if user.side == 0 else (foe, user)
    return battle._act(turn, user.side, fighters, index, sky or arena.weather, random.Random(seed), arena)


def armed(user, *moves):
    user.combatant = battle.replace(user.combatant, moves=moves)
    user.pp = [move.pp for move in moves]


def test_solar_beam_charges_for_a_turn_then_hits_without_paying_pp_again():
    user, foe, arena = duel()
    armed(user, SOLAR_BEAM)
    charging = act(user, foe, arena)
    assert (charging.effect, charging.defender_hp, user.pp[0]) == ("charge-turn", 100, SOLAR_BEAM.pp - 1)
    assert battle._choose(_teams(user, foe, arena), 0, arena, None) == 0
    released = act(user, foe, arena, turn=2)
    assert released.move == SOLAR_BEAM.name and released.defender_hp < 100 and not released.effect
    assert user.pp[0] == SOLAR_BEAM.pp - 1 and "charge-turn" not in user.volatiles


def test_solar_beam_hits_at_once_in_sun():
    user, foe, arena = duel()
    armed(user, SOLAR_BEAM)
    action = act(user, foe, arena, sky=weather("sun"))
    assert not action.effect and action.defender_hp < 100 and "charge-turn" not in user.volatiles


def test_a_user_that_cannot_act_on_the_second_turn_loses_the_charge():
    user, foe, arena = duel()
    armed(user, SOLAR_BEAM, TACKLE)
    act(user, foe, arena)
    user.status, user.sleep_left = "sleep", 2
    assert act(user, foe, arena, turn=2).blocked == "sleep"
    user.status = None
    assert act(user, foe, arena, index=1, turn=3).move == TACKLE.name


def test_skull_bash_raises_defense_as_it_charges_and_electro_shot_in_rain_raises_and_hits_at_once():
    user, foe, arena = duel()
    armed(user, SKULL_BASH)
    charging = act(user, foe, arena)
    assert charging.changes == (Change(0, user.combatant.name, "defense", 1),) and user.stages["defense"] == 1
    user, foe, arena = duel()
    armed(user, ELECTRO_SHOT)
    shot = act(user, foe, arena, sky=weather("rain"))
    assert shot.defender_hp < 100 and shot.changes[0] == Change(0, user.combatant.name, "special_attack", 1)


def test_a_semi_invulnerable_turn_dodges_a_normal_hit_and_a_status_move():
    user, foe, arena = duel()
    armed(user, DIG)
    assert act(user, foe, arena).effect == "underground"
    tackle = resolve(foe, user, TACKLE, arena, turn=1)
    assert tackle.missed and user.hp == user.max_hp
    assert resolve(foe, user, THUNDER_WAVE, arena, turn=1).missed and user.status is None
    assert act(user, foe, arena, turn=2).defender_hp < 100
    assert not resolve(foe, user, TACKLE, arena, turn=2).missed


def test_a_move_that_reaches_the_hiding_place_hits_it_with_its_bonus():
    user, foe, arena = hiding(DIG)
    assert battle._hidden(user, EARTHQUAKE) == 2 and battle._hidden(user, SURF) == 0
    assert battle._power(foe, user, EARTHQUAKE, None, 1.0) == 2 * EARTHQUAKE.power
    assert not resolve(foe, user, EARTHQUAKE, arena, turn=1).missed
    user = hiding(FLY)[0]
    assert (battle._hidden(user, GUST), battle._hidden(user, THUNDER), battle._hidden(user, EARTHQUAKE)) == (2, 1, 0)
    assert battle._hidden(hiding(DIVE)[0], SURF) == 2
    user = hiding(PHANTOM_FORCE)[0]
    assert battle._hidden(user, EARTHQUAKE) == battle._hidden(user, GUST) == 0


def hiding(move):
    user, foe, arena = duel()
    armed(user, move)
    act(user, foe, arena)
    return user, foe, arena


def test_smack_down_knocks_a_flying_user_out_of_the_sky():
    user, foe, arena = duel()
    armed(user, FLY)
    act(user, foe, arena)
    downed = resolve(foe, user, SMACK_DOWN, arena, turn=1)
    assert Change(0, user.combatant.name, "grounded") in downed.changes
    assert "semi-invulnerable" not in user.volatiles and battle._hidden(user, TACKLE) == 1


def test_thunder_drops_to_half_accuracy_in_sun():
    assert battle.move_power.typed(THUNDER, "sun").accuracy == 50
    assert battle.move_power.typed(THUNDER, None).accuracy == THUNDER.accuracy


def test_hyper_beam_needs_a_turn_of_rest_after_a_hit_but_not_after_a_miss():
    user, foe, arena = duel()
    armed(user, HYPER_BEAM, TACKLE)
    assert act(user, foe, arena).defender_hp < 100
    battle._volatile_upkeep(1, (user, foe), [], random.Random(0))
    assert act(user, foe, arena, index=1, turn=2).blocked == "recharge"
    battle._volatile_upkeep(2, (user, foe), [], random.Random(0))
    assert "recharge" not in user.volatiles and act(user, foe, arena, index=1, turn=3).move == TACKLE.name
    missed = act(user, foe, arena, seed=_miss_seed(), turn=4)
    assert missed.missed and "recharge" not in user.volatiles


def test_the_chooser_counts_half_a_two_turn_move_and_nothing_for_one_that_cannot_reach_the_hiding_foe():
    teams, arena = pair([SOLAR_BEAM, attack(85)], foe_moves=[DIG])
    user, foe = teams[0].active, teams[1].active
    full = battle._damage_score(user, foe, SOLAR_BEAM, None)
    assert battle._move_score(user, foe, SOLAR_BEAM, None) == full / 2
    assert battle._move_score(user, foe, SOLAR_BEAM, "sun") == battle._damage_score(user, foe, SOLAR_BEAM, "sun")
    act(foe, user, arena)
    assert battle._move_score(user, foe, attack(85), None) == 0
    teams, arena = pair([TACKLE, EARTHQUAKE], foe_moves=[DIG])
    act(teams[1].active, teams[0].active, arena)
    assert choose(teams, arena) == 1


def test_the_charge_and_recharge_lines_read_in_korean():
    charge = Action(1, 0, "A", "B", SOLAR_BEAM.name, effect="charge-turn")
    dig = Action(1, 0, "A", "B", DIG.name, effect="underground")
    rest = Action(2, 0, "A", "B", "", blocked="recharge")
    assert narration._action_line(charge, "▶").endswith("⏳힘을 모으는 중")
    assert narration._action_line(dig, "▶").endswith("⛏️땅속으로 파고들었다")
    assert narration._action_line(rest, "▶").endswith("😮‍💨반동으로 못 움직임")


def test_a_full_battle_charges_then_strikes_on_the_next_turn():
    teams, arena = pair([SKY_ATTACK], foe_moves=[TACKLE], hp=200)
    result = battle.simulate((teams[0].roster, teams[1].roster), seed=3)
    mine = [event for event in result.events if isinstance(event, Action) and event.side == 0]
    assert mine[0].effect == "charge-turn" and mine[1].move == SKY_ATTACK.name and not mine[1].effect
    assert mine[2].effect == "charge-turn"


def _teams(user, foe, arena):
    teams = (battle._Team((user.combatant,), arena=arena), battle._Team((foe.combatant,), arena=arena, side=1))
    teams[0].place(0, user)
    teams[1].place(0, foe)
    return teams


def _miss_seed():
    return next(seed for seed in range(200) if random.Random(seed).random() * 100 >= HYPER_BEAM.accuracy)
