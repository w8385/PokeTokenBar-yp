"""Status moves that give the foe a status or confusion. A move's `args` name the `ailment` it gives, and the type
whose users never miss with it (`sure_for`, Toxic). `user` and `foe` are `battle._Fighter`s. Each is picked only
when it would land and the condition hurts this foe."""

from ypoke import battle
from ypoke.effects import register
from ypoke.effects.healing import cure
from ypoke.effects.moves import StatusMove
from ypoke.effects.stats import arg, guarded, shift_all, useful
from ypoke.move_effects import POWDER_MOVES

SHIFTED = ("burn", "poison", "toxic", "paralysis", "sleep")
THREAD_DROP = (("speed", -1),)


@register("moves", "inflict")
class Inflict(StatusMove):
    """Fails on a foe that has a status (or confusion, for a confusing move) already, one its type, a state or its
    ability guards, and a Grass type when the move is a powder."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        ailment = arg(move, "ailment")
        return reaches(move, user, foe) and lands(move, ailment, user, foe) and hurts(ailment, user, foe, weather)

    def never_misses(self, move, user):
        return arg(move, "sure_for") in user.combatant.types

    def _apply(self, move, user, foe, side, turn, arena, rng):
        ailment = arg(move, "ailment")
        if not lands(move, ailment, user, foe):
            return "", ()
        return self.key, (battle._inflict(ailment, foe, 1 - side, rng),)


def reaches(move, user, foe) -> bool:
    """No state on the foe's side stops the move (Substitute)."""
    return not any(battle._field(foe, "shields", move, user))


def lands(move, ailment: str, user, foe) -> bool:
    return (battle._open_to(ailment, foe, not battle._infiltrates(user))
            and not battle._blocks_ailment(foe, ailment)
            and not (move.id in POWDER_MOVES and "grass" in foe.combatant.types))


def hurts(ailment: str, user, foe, weather) -> bool:
    """Sleep always; paralysis on a faster foe; a burn on a physical attacker; poison and confusion while the foe
    has more than half its HP left."""
    if ailment == "paralysis":
        return foe.stat("speed", weather) > user.stat("speed", weather)
    if ailment == "burn":
        return useful(foe, user, "attack", weather)
    if ailment == "sleep":
        return True
    return foe.hp * 2 > foe.max_hp


@register("moves", "swagger")
class Swagger(StatusMove):
    """Confuses the foe and raises its stat by the move's `changes`; the raise lands on a foe that is confused
    already. Picked on a foe the raise does not help."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return (reaches(move, user, foe) and lands(move, "confusion", user, foe)
                and not any(useful(foe, user, key, weather) for key, _ in arg(move, "changes")))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        confused = (battle._inflict("confusion", foe, 1 - side, rng),) if lands(move, "confusion", user, foe) else ()
        raised = shift_all(foe, 1 - side, arg(move, "changes"))
        return (self.key if confused or raised else ""), (*confused, *raised)


@register("moves", "toxic-thread")
class ToxicThread(StatusMove):
    """Poisons the foe and lowers its Speed; works when either lands."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return reaches(move, user, foe) and lands(move, "poison", user, foe) and hurts("poison", user, foe, weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        poisoned = (battle._inflict("poison", foe, 1 - side, rng),) if lands(move, "poison", user, foe) else ()
        slowed = shift_all(foe, 1 - side, THREAD_DROP, guarded=guarded(user, foe), by=user)
        return (self.key if poisoned or slowed else ""), (*poisoned, *slowed)


@register("moves", "psycho-shift")
class PsychoShift(StatusMove):
    """Moves the user's status to the foe and cures the user; fails when the foe cannot take it."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return user.status in SHIFTED and reaches(move, user, foe) and lands(move, user.status, user, foe)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if user.status not in SHIFTED or not lands(move, user.status, user, foe):
            return "", ()
        given = battle._inflict(user.status, foe, 1 - side, rng)
        return self.key, (given, *cure(user, side))
