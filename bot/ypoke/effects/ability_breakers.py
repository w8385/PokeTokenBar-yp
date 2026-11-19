"""Abilities that reach past or take over other abilities: ignoring the target's (Mold Breaker), switching the foe's
off (Neutralizing Gas) or copying the foe's (Trace). `fighter` and `foe` are
`battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import Handler, hooks, register
from ypoke.effects.changers import FIXED_ABILITIES, reshape

# Trace copies Wonder Guard, the one fixed ability Skill Swap leaves alone that it can take.
UNTRACEABLE = FIXED_ABILITIES - {"wonder-guard"}


@register("abilities", "mold-breaker")
class MoldBreaker(Handler):
    """Mold Breaker, Teravolt, Turboblaze: the holder's moves leave the target's breakable ability out."""

    def on_entry(self, name, fighter, foe, side, weather):
        return battle.AbilityEntry(side, fighter.combatant.name, name, effect="breaks")

    def breaks_abilities(self, name, move):
        return True


@register("abilities", "neutralizing-gas")
class NeutralizingGas(Handler):
    """The foe's abilities do nothing while the holder is out, but the ones bound to a form (`UNSUPPRESSED`)."""

    def on_entry(self, name, fighter, foe, side, weather):
        return battle.AbilityEntry(side, fighter.combatant.name, name, effect="gas")

    def suppresses_abilities(self, name):
        return True


@register("abilities", "trace")
class Trace(Handler):
    """Entering copies the foe's ability, which then acts as if it had just entered (a traced Intimidate)."""

    def on_entry(self, name, fighter, foe, side, weather):
        copied = foe.ability
        if foe.hp == 0 or copied is None or copied in UNTRACEABLE:
            return None
        reshape(fighter, ability=copied)
        battle._announce(fighter, hooks.ability(fighter, "on_entry", fighter, foe, side, weather))
        return battle.AbilityEntry(side, fighter.combatant.name, name, effect="trace", detail=copied)
