"""Abilities about statuses: ones that cure, pass back, block or stand in for a status, or that change what a status
or indirect damage does to their holder. `fighter` and `holder` are `battle._Fighter`s."""

from ypoke import abilities, battle
from ypoke.effects import Handler, register


@register("abilities", "synchronize")
class Synchronize(Handler):
    def passes_ailment(self, name, ailment):
        return ailment in abilities.SYNCED_AILMENTS[name]


@register("abilities", "shed-skin")
class ShedSkin(Handler):
    def cures_status(self, name, fighter, side, turn, rng):
        return _cured(fighter, side, name) if rng.random() < abilities.SHED_SKIN_CHANCE else None


@register("abilities", "hydration")
class Hydration(Handler):
    def cures_status(self, name, fighter, side, turn, rng):
        return _cured(fighter, side, name) if battle._weather_of(fighter) == "rain" else None


@register("abilities", "natural-cure")
class NaturalCure(Handler):
    def on_switch_out(self, name, fighter, side):
        return None if fighter.status is None else _cured(fighter, side, name)


@register("abilities", "regenerator")
class Regenerator(Handler):
    def on_switch_out(self, name, fighter, side):
        if fighter.hp in (0, fighter.max_hp):
            return None
        fighter.hp = min(fighter.max_hp, fighter.hp + fighter.max_hp // abilities.REGENERATOR_SHARE)
        return battle.AbilityAct(fighter.arena.turn, side, fighter.combatant.name, name, hp=fighter.hp_percent)


@register("abilities", "poison-heal")
class PoisonHeal(Handler):
    """Poison heals 1/8 of the holder's max HP at the end of a turn instead of hurting it."""

    def status_damage(self, name, damage, fighter, side, turn):
        if fighter.status not in abilities.POISONS:
            return None
        if fighter.hp == fighter.max_hp:
            return ()
        fighter.hp = min(fighter.max_hp, fighter.hp + max(1, fighter.max_hp // abilities.POISON_HEAL_SHARE))
        return (battle.AbilityAct(turn, side, fighter.combatant.name, name, hp=fighter.hp_percent),)

    def welcomes_ailment(self, name, ailment):
        return ailment in abilities.POISONS


@register("abilities", "magic-guard")
class MagicGuard(Handler):
    def blocks_indirect(self, name):
        return True


@register("abilities", "comatose")
class Comatose(Handler):
    """The holder counts as asleep but acts, and no status lands on it."""

    def status_as(self, name):
        return abilities.COMATOSE_STATUS

    def blocks_ailment(self, name, ailment, holder):
        return ailment in abilities.MAJOR_AILMENTS


@register("abilities", "leaf-guard")
class LeafGuard(Handler):
    def blocks_ailment(self, name, ailment, holder):
        return ailment in abilities.MAJOR_AILMENTS and battle._weather_of(holder) == "sun"


@register("abilities", "flower-veil")
class FlowerVeil(Handler):
    """A Grass-type holder keeps its stats from a foe and takes no status."""

    def guards_stat(self, name, key, holder):
        return abilities.FLOWER_VEIL_TYPE in holder.combatant.types

    def blocks_ailment(self, name, ailment, holder):
        return ailment in abilities.MAJOR_AILMENTS and abilities.FLOWER_VEIL_TYPE in holder.combatant.types


@register("abilities", "corrosion")
class Corrosion(Handler):
    def poisons_any_type(self, name):
        return True


@register("abilities", "early-bird")
class EarlyBird(Handler):
    def wakes_early(self, name):
        return 1


def _cured(fighter, side: int, name: str):
    fighter.status, fighter.sleep_left, fighter.toxic_ticks = None, 0, 0
    return battle.AbilityTrigger(side, fighter.combatant.name, name,
                                 change=battle.Change(side, fighter.combatant.name, "cure"))
