"""Held items that change a stat, the turn order or the critical-hit stage, and the species-bound ones
(`tera_forms.usable_item` drops them on any other species). `holder` is a `battle._Fighter`, None outside a battle."""

from ypoke import items
from ypoke.effects import Handler, register


@register("items", "speed-halver", "iron-ball")
class SpeedHalver(Handler):
    """Macho Brace, the Power items, Iron Ball: the holder's Speed is halved; an Iron Ball also grounds it."""

    def modify_stat(self, name, stat, weather, statused, can_evolve, holder):
        return items.SPEED_HALVED if stat == "speed" else 1.0

    def grounds(self, name):
        return self.key == "iron-ball"


@register("items", "moves-last")
class MovesLast(Handler):
    def moves_last(self, name):
        return True


@register("items", "species-stat")
class SpeciesStat(Handler):
    """Light Ball, Thick Club, the Deep Sea items and the Ditto powders double `args.stats` until the holder
    transforms."""

    def modify_stat(self, name, stat, weather, statused, can_evolve, holder):
        if stat not in items.SPECIES_STATS[name] or holder is not None and "transform" in holder.volatiles:
            return 1.0
        return items.SPECIES_STAT_MULTIPLIER


@register("items", "species-crit")
class SpeciesCrit(Handler):
    def crit_stage(self, name):
        return items.SPECIES_CRIT_STAGES[name]


@register("items", "incense")
class Incense(Handler):
    def modify_damage(self, name, move_type, effectiveness, physical, punch):
        return items.BOOST_MULTIPLIER if move_type is not None and items.INCENSES[name] == move_type else 1.0
