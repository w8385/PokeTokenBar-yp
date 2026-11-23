from ypoke import entry_rules, moves
from ypoke.battle import Action, BaseStats, Combatant, simulate
from ypoke.dex import sprite_url

RAPID_STRIKE = 10191
URSHIFU = 892
SURGING_STRIKES = 818
IVS = BaseStats(15, 15, 15, 15, 15, 15)


def test_rapid_strike_counts_as_urshifu_and_keeps_its_own_sprite():
    assert entry_rules.species_id(RAPID_STRIKE) == URSHIFU
    assert sprite_url(RAPID_STRIKE, False).endswith("/10191.png")


def test_surging_strikes_lands_three_critical_water_hits():
    surging = moves.from_data(SURGING_STRIKES)
    assert surging.type == "water"
    urshifu = combatant("우라오스", ["fighting", "water"], [surging], speed=200)
    target = combatant("B", ["normal"], [moves.from_data(33)], speed=1)
    for seed in range(5):
        first = next(event for event in simulate((urshifu, target), seed).events if isinstance(event, Action))
        assert (first.move, first.hits, first.critical) == (surging.name, 3, True)


def combatant(name, types, move_list, speed):
    return Combatant(name=name, level=50, types=tuple(types), base=BaseStats(100, 130, 100, 63, 60, speed), ivs=IVS,
                     moves=tuple(move_list))
