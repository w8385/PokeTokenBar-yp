"""Abilities about statuses. `fighter` is a `battle._Fighter`."""

from ypoke import abilities, battle
from ypoke.effects import Handler, register


@register("abilities", "shed-skin")
class ShedSkin(Handler):
    def cures_status(self, name, fighter, side, turn, rng):
        return _cured(fighter, side, name) if rng.random() < abilities.SHED_SKIN_CHANCE else None


def _cured(fighter, side: int, name: str):
    fighter.status, fighter.sleep_left, fighter.toxic_ticks = None, 0, 0
    return battle.AbilityTrigger(side, fighter.combatant.name, name,
                                 change=battle.Change(side, fighter.combatant.name, "cure"))
