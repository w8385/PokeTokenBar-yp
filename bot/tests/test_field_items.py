import pytest
from test_ability_items import holding
from test_battle import EMBER
from status_moves import data_move, resolve

from ypoke import abilities, battle, items
from ypoke.battle import ItemEffect
from ypoke.effects import hooks
from ypoke.effects.ability_weather import ENERGIZED
from ypoke.narration import battle_log

SLEEP_POWDER, GASTRO_ACID, SOLAR_BEAM, FAKE_OUT = data_move(79), data_move(380), data_move(76), data_move(252)


@pytest.mark.parametrize(("seed", "terrain", "stat"), [(slug, *entry) for slug, entry in
                                                       sorted(items.TERRAIN_SEEDS.items())])
def test_a_seed_raises_its_stat_once_its_terrain_is_up(seed, terrain, stat):
    holder, _, arena = holding(item=seed)
    assert hooks.item(holder, "on_update", holder, 0, 1) is None and holder.item == seed
    arena.terrain = next(other for other, _ in items.TERRAIN_SEEDS.values() if other != terrain)
    assert hooks.item(holder, "on_update", holder, 0, 1) is None and holder.item == seed
    arena.terrain = terrain
    hooks.item(holder, "on_update", holder, 0, 1)
    assert holder.item is None and holder.stages[stat] == 1


def test_booster_energy_sets_off_protosynthesis_without_sun_and_is_used_up():
    holder, _, arena = holding(ability="protosynthesis", item="booster-energy")
    event = hooks.ability(holder, "on_update", holder, 0, 1)
    assert event.effect == "paradox" and holder.item is None and ENERGIZED in holder.memory
    best = holder.memory["protosynthesis"]
    assert hooks.ability(holder, "modify_stat", best, None, holder) > 1.0
    assert ItemEffect(1, 0, holder.combatant.name, "booster-energy", "energized") in arena.log


def test_booster_energy_stays_in_sun_and_on_a_holder_without_a_paradox_ability():
    holder, _, arena = holding(ability="protosynthesis", item="booster-energy")
    arena.weather.kind = "sun"
    hooks.ability(holder, "on_update", holder, 0, 1)
    assert holder.item == "booster-energy" and holder.memory["protosynthesis"]
    plain, _, _ = holding(item="booster-energy")
    hooks.ability(plain, "on_update", plain, 0, 1)
    hooks.item(plain, "on_update", plain, 0, 1)
    assert plain.item == "booster-energy"


def test_utility_umbrella_keeps_sun_off_the_moves_that_hit_its_holder_its_stats_and_its_charge_moves():
    _, holder, arena = holding(foe_ability="chlorophyll", foe_item="utility-umbrella")
    _, plain, _ = holding(foe_ability="chlorophyll")
    assert battle._weather_boost(EMBER, "sun", holder) == 1.0
    assert battle._weather_boost(EMBER, "sun", plain) == battle.WEATHER_MOVE_BOOST["sun"]["fire"]
    assert holder.stat("speed", "sun") == holder.stat("speed", None) < plain.stat("speed", "sun")
    arena.weather.kind = "sun"
    assert resolve(holder, arena.teams[0].active, SOLAR_BEAM, arena).effect == "charge-turn"


def test_safety_goggles_keep_powder_moves_and_sandstorm_chip_off_its_holder():
    user, holder, arena = holding(foe_item="safety-goggles")
    assert resolve(user, holder, SLEEP_POWDER, arena).blocked == "safety-goggles" and holder.status is None
    assert not resolve(user, holder, EMBER, arena).blocked and holder.hp < holder.max_hp
    assert not battle._chipped_by(holder, "sandstorm")
    user, plain, arena = holding()
    resolve(user, plain, SLEEP_POWDER, arena, seed=1)
    assert plain.status == "sleep" and battle._chipped_by(plain, "sandstorm")


def test_covert_cloak_keeps_added_effects_off_its_holder_only():
    user, holder, _ = holding(foe_item="covert-cloak")
    assert battle._chance_scale(FAKE_OUT, user, holder) == 0.0
    assert battle._chance_scale(FAKE_OUT, holder, user) == 1.0


def test_clear_amulet_keeps_a_foes_drop_but_not_the_holders_own():
    user, holder, arena = holding(ability="intimidate", foe_item="clear-amulet")
    hooks.ability(user, "on_entry", user, holder, 0, arena.weather)
    assert holder.stages["attack"] == 0
    assert ItemEffect(1, 1, holder.combatant.name, "clear-amulet", "guard") in arena.log
    battle.shift_stage(holder, 1, "defense", -1)
    assert holder.stages["defense"] == -1


def test_ability_shield_keeps_the_ability_from_being_lost_or_ignored():
    user, holder, arena = holding(foe_ability="levitate", foe_item="ability-shield")
    resolve(user, holder, GASTRO_ACID, arena)
    assert holder.combatant.ability == "levitate"
    holder.ability_ignored = True
    assert holder.ability == "levitate"
    user, plain, arena = holding(foe_ability="levitate")
    resolve(user, plain, GASTRO_ACID, arena)
    assert plain.combatant.ability is None
    plain.combatant = battle.replace(plain.combatant, ability="levitate")
    plain.ability_ignored = True
    assert plain.ability is None and "levitate" in abilities.BREAKABLE


def test_ability_shield_keeps_neutralizing_gas_off_the_ability():
    _, holder, _ = holding(ability="neutralizing-gas", foe_ability="levitate", foe_item="ability-shield")
    _, plain, _ = holding(ability="neutralizing-gas", foe_ability="levitate")
    assert holder.ability == "levitate" and plain.ability is None


def test_the_log_names_the_item_that_stopped_the_move():
    events = (battle.Action(1, 0, "사용자", "상대", "수면가루", failed=True, blocked="safety-goggles"),
              ItemEffect(1, 1, "상대", "clear-amulet", "guard"))
    log = "".join(battle_log(battle.BattleResult(0, 1, events, ((50,), (50,)))))
    assert "@방진고글에 막힘" in log and "상대 @클리어참 능력 하락을 막음" in log
