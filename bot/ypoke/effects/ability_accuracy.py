"""Abilities that change whether a move lands and how well: accuracy, evasion, critical hits, stat stages and the
types a move can touch. `holder` and `fighter` are `battle._Fighter`s; the numbers live in `ypoke.abilities`."""

from ypoke import abilities, battle
from ypoke.effects import Handler, register


@register("abilities", "accuracy-boost")
class AccuracyBoost(Handler):
    """Compound Eyes, Victory Star: the holder's moves ×`args.accuracy`."""

    def accuracy_as_user(self, name, move):
        return abilities.ACCURACY_BOOST[name]


@register("abilities", "stat-guard")
class StatGuard(Handler):
    """A foe cannot lower the stats in `args.stats` (Keen Eye on accuracy)."""

    def guards_stat(self, name, key, fighter):
        return key in abilities.GUARDED_STATS[name]


@register("abilities", "ignores-evasion")
class IgnoresEvasion(Handler):
    def ignores_evasion(self, name):
        return True


@register("abilities", "scrappy")
class Scrappy(Handler):
    """Normal and Fighting moves hit Ghost types."""

    def exposes(self, name, move_type):
        return "ghost" if move_type in abilities.SCRAPPY_TYPES else None


@register("abilities", "intimidate-immune")
class IntimidateImmune(Handler):
    def answers_intimidate(self, name, holder, side):
        turn = holder.arena.turn if holder.arena is not None else 0
        return battle.AbilityAct(turn, side, holder.combatant.name, name, effect="guard")


@register("abilities", "tangled-feet")
class TangledFeet(Handler):
    def accuracy_as_target(self, name, move, holder):
        return abilities.TANGLED_FEET_ACCURACY if "confusion" in holder.volatiles else 1.0


@register("abilities", "weather-evasion")
class WeatherEvasion(Handler):
    """Sand Veil, Snow Cloak: moves aimed at the holder land less often in `args.weather`."""

    def accuracy_as_target(self, name, move, holder):
        hidden = abilities.in_weather(battle._weather_of(holder), abilities.EVASION_WEATHER[name])
        return abilities.WEATHER_EVASION_ACCURACY if hidden else 1.0


@register("abilities", "wonder-skin")
class WonderSkin(Handler):
    """A status move aimed at the holder lands at 50% at best."""

    def accuracy_as_target(self, name, move, holder):
        capped = not move.damaging and (move.accuracy or 0) > abilities.WONDER_SKIN_ACCURACY
        return abilities.WONDER_SKIN_ACCURACY / move.accuracy if capped else 1.0


@register("abilities", "super-luck")
class SuperLuck(Handler):
    def crit_stage(self, name):
        return 1


@register("abilities", "merciless")
class Merciless(Handler):
    def always_crits(self, name, target):
        return target.status in ("poison", "toxic")


@register("abilities", "crit-guard")
class CritGuard(Handler):
    """Battle Armor, Shell Armor."""

    def guards_crit(self, name):
        return True


@register("abilities", "no-guard")
class NoGuard(Handler):
    def sure_hits(self, name):
        return True


@register("abilities", "unaware")
class Unaware(Handler):
    """The foe's stat stages count for nothing in the holder's damage and accuracy, either way."""

    def ignores_foe_stages(self, name):
        return True
