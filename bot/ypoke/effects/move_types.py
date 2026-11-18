"""Attacks whose type comes from their user (Revelation Dance, Raging Bull) or its held item (Techno Blast,
Multi-Attack), or that hit some types harder than the type chart says (Freeze-Dry, Flying Press). `user` is a
`battle._Fighter`."""

from dataclasses import replace

from ypoke.effects import Handler, elsewhere, register
from ypoke.effects.stats import arg
from ypoke.type_chart import effectiveness

SUPER_EFFECTIVE = 2.0


@register("moves", "user-type")
class UserType(Handler):
    """The user's first type, or its last with `args.last` (Raging Bull follows a Paldean Tauros' breed)."""

    by_id = True

    def modify_type(self, move, weather, user):
        if user is None:
            return move
        types = user.combatant.types
        return replace(move, type=types[-1] if arg(move, "last", False) else types[0])


@register("moves", "adds-type")
class AddsType(Handler):
    """Flying Press also hits as `args.type`."""

    by_id = True

    def type_multiplier(self, move, types):
        return effectiveness(arg(move, "type"), types)


@register("moves", "super-vs")
class SuperVs(Handler):
    """Freeze-Dry hits `args.type` super effectively."""

    by_id = True

    def type_multiplier(self, move, types):
        weak = arg(move, "type")
        return SUPER_EFFECTIVE / effectiveness(move.type, (weak,)) if weak in types else 1.0


elsewhere("moves", "combatants: the move takes the type its user's held item gives (`args.types`)", "item-type")
