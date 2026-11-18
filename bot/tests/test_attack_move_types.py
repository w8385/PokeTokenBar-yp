from attacks import attack, duel
from test_attack_two_turn import act, armed
from test_champion_items import FakePokeAPI, move_dict

from ypoke import battle, move_power
from ypoke.battle import Change
from ypoke.combatants import combatant

TECHNO_BLAST, MULTI_ATTACK, REVELATION_DANCE, RAGING_BULL = 546, 718, attack(686), attack(873)
FLYING_PRESS, FREEZE_DRY, SPARKLING_ARIA = attack(560), attack(573), attack(664)


def test_techno_blast_and_multi_attack_take_the_type_of_their_own_held_item_only():
    assert [move.type for move in build(649, "burn-drive", moves=[TECHNO_BLAST, MULTI_ATTACK, 33]).moves] == [
        "fire", "normal", "normal"]
    assert [move.type for move in build(773, "dragon-memory", moves=[MULTI_ATTACK, TECHNO_BLAST]).moves] == [
        "dragon", "normal"]
    assert build(25, None, moves=[MULTI_ATTACK]).moves[0].type == "normal"


def test_revelation_dance_takes_the_users_first_type_and_raging_bull_its_last():
    user, foe, arena = duel(user_types=("fire", "flying"), foe_types=("grass",))
    assert move_power.typed(REVELATION_DANCE, None, user).type == "fire"
    armed(user, REVELATION_DANCE)
    assert act(user, foe, arena).multiplier == 2.0
    user.combatant = battle.replace(user.combatant, types=("fighting", "water"))
    assert move_power.typed(RAGING_BULL, None, user).type == "water"
    user.combatant = battle.replace(user.combatant, types=("normal",))
    assert move_power.typed(RAGING_BULL, None, user).type == "normal"
    assert move_power.typed(RAGING_BULL, None, None) is RAGING_BULL


def test_flying_press_hits_as_fighting_and_flying_at_once():
    user, foe, arena = duel()
    for types, multiplier in ((("grass",), 2.0), (("fighting",), 2.0), (("rock",), 1.0), (("ghost",), 0.0),
                              (("normal",), 2.0), (("steel", "rock"), 1.0)):
        foe.combatant = battle.replace(foe.combatant, types=types)
        assert battle._multiplier(FLYING_PRESS, foe) == multiplier, types


def test_freeze_dry_hits_water_types_super_effectively():
    user, foe, arena = duel()
    for types, multiplier in ((("water",), 2.0), (("water", "flying"), 4.0), (("water", "grass"), 4.0),
                              (("grass",), 2.0), (("steel",), 0.5)):
        foe.combatant = battle.replace(foe.combatant, types=types)
        assert battle._multiplier(FREEZE_DRY, foe) == multiplier, types


def test_sparkling_aria_cures_the_targets_burn_without_more_power():
    user, foe, arena = duel()
    armed(user, SPARKLING_ARIA)
    plain = battle._unrolled_damage(user, foe, SPARKLING_ARIA, 1.0, None)
    foe.status = "burn"
    assert battle._unrolled_damage(user, foe, SPARKLING_ARIA, 1.0, None) == plain
    cured = act(user, foe, arena)
    assert Change(1, foe.combatant.name, "cure") in cured.changes and foe.status is None


class OfferedMoves(FakePokeAPI):
    def __init__(self, move_ids):
        self.move_ids = move_ids

    def attacking_moves(self, pokemon_id, level, machine_ids=()):
        return [move_dict(move_id) for move_id in self.move_ids]


def build(pokemon_id, item, moves):
    member = {"pokemon_id": pokemon_id, "level": 50, "ivs": {}, "shiny": False, "moves": list(moves),
              **({"held_item": item} if item else {})}
    return combatant(OfferedMoves(moves), member)
