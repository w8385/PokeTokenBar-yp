"""Attacks with an effect on the target beyond their PokéAPI ailment and stat changes, run through the `secondary`
hook once the hits left the target standing. `user` and `target` are `battle._Fighter`s."""

from ypoke import battle, battle_data, pokeapi
from ypoke.effects import Handler, register
from ypoke.effects.stats import arg, shift

SECRET_POWER = {"electric-terrain": ("paralysis", None), "grassy-terrain": ("sleep", None),
                "misty-terrain": (None, ("special_attack", -1)), "psychic-terrain": (None, ("speed", -1))}


@register("moves", "flinch")
class Flinch(Handler):
    """A target that has not moved yet this turn may skip its move; the flinch wears off at the end of the turn."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        if not target.acted and chance(move, rng, "flinch_chance") and not battle._blocks_ailment(target, "flinch"):
            target.volatiles["flinch"] = True
        return ()

    def bans_move(self, name, move, fighter):
        return name

    def volatile_end(self, name, fighter, side, turn, rng):
        del fighter.volatiles[name]


@register("moves", "random-ailment")
class RandomAilment(Handler):
    """One of `args.ailments` at random (Tri Attack: burn, freeze or paralysis)."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        if not chance(move, rng):
            return ()
        landed = afflict(rng.choice(arg(move, "ailments")), user, target, side, rng)
        return () if landed is None else (landed,)


@register("moves", "secret-power")
class SecretPower(Handler):
    """Paralysis outside a terrain; the terrain picks sleep, paralysis or a stat drop."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        if not chance(move, rng):
            return ()
        terrain = user.arena.terrain if user.arena is not None else None
        ailment, drop = SECRET_POWER.get(terrain, ("paralysis", None))
        if drop is not None:
            landed = None if battle._stats_guarded(target, not battle._infiltrates(user)) else shift(
                target, 1 - side, *drop)
        else:
            landed = afflict(ailment, user, target, side, rng)
        return () if landed is None else (landed,)


@register("moves", "thaw")
class Thaw(Handler):
    by_id = True

    def thaws_user(self, move):
        return True


def afflict(ailment: str, user, target, side: int, rng):
    """The ailment lands on the target unless its type, a state or its ability keeps it off; None when it does not."""
    if not battle._open_to(ailment, target, not battle._infiltrates(user)):
        return None
    if battle._blocks_ailment(target, ailment):
        return None
    return battle._inflict(ailment, target, 1 - side, rng)


def chance(move, rng, field: str = "ailment_chance") -> bool:
    return rng.random() * 100 < meta(move, field)


def meta(move, field: str, default=0):
    """The move's PokéAPI meta field with its `args.meta` fill."""
    entry = battle_data.table("moves").get(str(move.id))
    return pokeapi.merged_meta(entry).get(field) or default if entry else default
