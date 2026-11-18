"""Attacks that deal damage from other stats than their class's: the target's Defense for a special move (Psyshock),
the target's Attack (Foul Play), the user's Defense (Body Press) or the better class (Shell Side Arm); and attacks that
ignore the target's stat stages (Sacred Sword) or its ability (Sunsteel Strike). `user` and `target` are
`battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import Handler, register
from ypoke.effects.stats import arg


@register("moves", "stat-source")
class StatSource(Handler):
    """`args.attack` and `args.defense` name the stats; `args.from` "target" takes the attack stat from the target."""

    by_id = True

    def stat_source(self, move, user, target, weather):
        source = target if arg(move, "from") == "target" else user
        return source, arg(move, "attack"), arg(move, "defense")


@register("moves", "best-category")
class BestCategory(Handler):
    """Shell Side Arm hits physically when the user's Attack over the target's Defense beats its Special Attack over
    Special Defense."""

    by_id = True

    def stat_source(self, move, user, target, weather):
        physical = (user.stat("attack", weather) / max(1, target.stat("defense", weather))
                    > user.stat("special_attack", weather) / max(1, target.stat("special_defense", weather)))
        return user, *battle.STAT_PAIRS[physical]


@register("moves", "ignores-stages")
class IgnoresStages(Handler):
    by_id = True

    def ignores_stages(self, move):
        return True


@register("moves", "ignores-ability")
class IgnoresAbility(Handler):
    by_id = True

    def ignores_ability(self, move):
        return True
