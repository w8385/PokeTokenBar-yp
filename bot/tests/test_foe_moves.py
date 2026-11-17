from ypoke import foe_moves, gyms
from ypoke.combatants import combatant
from ypoke.foe_moves import FoeMove, pick

HYPER_BEAM = 63
FLAMETHROWER = FoeMove(53, "fire", False, 90, 100, 1.0)
FIRE_BLAST = FoeMove(126, "fire", False, 110, 85, 1.0)
AIR_SLASH = FoeMove(403, "flying", False, 75, 95, 1.0)
EARTHQUAKE = FoeMove(89, "ground", True, 100, 100, 1.0)
SOLAR_BEAM = FoeMove(76, "grass", False, 120, 100, 1.0)
DRAGON_PULSE = FoeMove(406, "dragon", False, 85, 100, 1.0)
EMBER = FoeMove(52, "fire", False, 40, 100, 1.0)
HYPER = FoeMove(HYPER_BEAM, "normal", False, 150, 90, 1.0)


def test_a_foe_leads_with_its_best_expected_stab_then_covers_and_skips_a_recharge_move():
    moves = [EMBER, FLAMETHROWER, FIRE_BLAST, AIR_SLASH, EARTHQUAKE, SOLAR_BEAM, DRAGON_PULSE, HYPER]
    picked = pick(moves, ("fire", "flying"), attack=84, special_attack=109)
    assert picked[:2] == [FIRE_BLAST.id, AIR_SLASH.id]
    assert len(picked) == 4 and HYPER_BEAM not in picked and EMBER.id not in picked
    assert EARTHQUAKE.id in picked


def test_a_recharge_move_fills_only_a_slot_nothing_else_can():
    assert pick([EMBER, HYPER], ("fire",), attack=50, special_attack=50) == [EMBER.id, HYPER_BEAM]


def test_three_species_carry_the_committed_pick():
    assert foe_moves.species(6).picked == (315, 542, 89, 200)
    assert foe_moves.species(445).picked == (200, 89, 398, 38)
    assert foe_moves.species(94).picked == (247, 482, 411, 412)
    for species_id in (6, 445, 94):
        data = foe_moves.species(species_id)
        assert set(data.picked) <= data.learnable
        assert not set(data.picked) & foe_moves.LAST_RESORT


class LearnsEverything:
    def pokemon(self, pokemon_id):
        return {"name_ko": f"#{pokemon_id}", "types": ["normal"],
                "base": dict.fromkeys(("hp", "attack", "defense", "special_attack", "special_defense", "speed"), 80)}

    def attacking_moves(self, pokemon_id, level, machine_ids=()):
        assert level == gyms.LEARN_LEVEL
        return [_move(move_id) for move_id in foe_moves.species(pokemon_id).learnable]


def _move(move_id):
    data = foe_moves.move(move_id)
    return {
        "id": move_id, "name": f"m{move_id}", "type": data.type, "power": data.power,
        "damage_class": "physical" if data.physical else "special", "accuracy": data.accuracy, "pp": 10,
        "crit_rate": 0, "priority": 0, "ailment": None, "ailment_chance": 0, "stat_changes": [],
        "stat_target": "target", "stat_chance": 0, "drain": 0, "min_hits": 1, "max_hits": 1, "weather": None,
        "always_hits_in": [], "level": 1,
    }


def test_a_gym_foe_fights_with_the_moves_the_catalog_lists():
    opponent = gyms.find("kanto-8")
    for member, moves in zip(gyms.foe_members(opponent), opponent.moves, strict=True):
        fighter = combatant(LearnsEverything(), member)
        assert [move.name for move in fighter.moves] == [f"m{move_id}" for move_id in moves]
