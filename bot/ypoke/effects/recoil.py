"""Attacks that cost their user HP beyond the PokéAPI recoil share of the damage: a crash when the move misses, a share
of max HP paid for using it, or one paid once it hits. `user` is a `battle._Fighter`."""

from ypoke import battle
from ypoke.effects import Handler, register

CRASH_SHARE = 2
COST_SHARE = 2


@register("moves", "crash")
class Crash(Handler):
    """Jump Kick, High Jump Kick, Axe Kick and Supercell Slam: half the user's max HP when the move misses, hits an
    immune target or meets Protect."""

    by_id = True

    def hp_paid(self, move, user):
        return user.max_hp // CRASH_SHARE * (100 - (move.accuracy or 100)) / 100

    def crashes(self, move, user):
        return pay(user, user.max_hp // CRASH_SHARE, "crash")


@register("moves", "hp-cost")
class HPCost(Handler):
    """Steel Beam and Mind Blown: half the user's max HP, rounded up, once used, hit or miss."""

    by_id = True

    def hp_paid(self, move, user):
        return half_max_hp(user)

    def pays_hp(self, move, user):
        return pay(user, half_max_hp(user), "hp-cost")


@register("moves", "hp-cost-on-hit")
class HPCostOnHit(Handler):
    """Chloroblast: half the user's max HP, rounded up, once it hits."""

    by_id = True

    def hp_paid(self, move, user):
        return half_max_hp(user)

    def after_move(self, move, user, target, dealt):
        return (pay(user, half_max_hp(user), "hp-cost"),)


def pay(user, hp: int, kind: str):
    if not battle._chip_free(user):
        user.hp = max(0, user.hp - max(1, hp))
    return battle.Change(user.side, user.combatant.name, kind)


def half_max_hp(user) -> int:
    return -(-user.max_hp // COST_SHARE)
