"""Attacks that take two turns: a charge turn before the hit (Solar Beam), a turn hidden out of reach before it (Fly,
Dig), or a turn of rest after it (Hyper Beam). The charged move waits in `fighter.volatiles[key]`, so switching out
or failing to act on the next turn drops it. `user` and `fighter` are `battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import Handler, hooks, register
from ypoke.effects.stats import arg, shift_all

TWO_TURN_SHARE = 0.5
RECHARGE_TURNS = 2


@register("moves", "charge-turn")
class ChargeTurn(Handler):
    """Charges for a turn, then hits on the next one. A weather in `args.skips_in` lets it hit at once (Solar Beam in
    sun); `args.raise` lifts the user's stats as it charges (Skull Bash), in that weather too (Electro Shot)."""

    by_id = True

    def charges(self, move, user, side, weather):
        raised = shift_all(user, side, arg(move, "raise", ()))
        if weather in arg(move, "skips_in", ()):
            return "", raised
        user.volatiles[self.key] = move
        return self._shown(move), raised

    def readied(self, name, fighter):
        return fighter.volatiles.pop(name)

    def forces_move(self, name, attacker):
        return attacker.last_used

    def score_share(self, move, weather):
        return 1.0 if weather in arg(move, "skips_in", ()) else TWO_TURN_SHARE

    def _shown(self, move) -> str:
        return self.key


@register("moves", "semi-invulnerable")
class SemiInvulnerable(ChargeTurn):
    """Hides for a turn (`args.where`: flying, underground, underwater, vanished), then hits. While hidden only a
    move that reaches that place hits it (`reaches`)."""

    def hides(self, name, move, holder):
        return hooks.move(move, "reaches", arg(holder.volatiles[name], "where"), default=0.0)

    def _shown(self, move) -> str:
        return arg(move, "where")


@register("moves", "reaches-hidden")
class ReachesHidden(Handler):
    """Hits a target hiding in `args.where` (Earthquake on Dig), with `args.power` times the power (default 1)."""

    by_id = True

    def reaches(self, move, where):
        return arg(move, "power", 1.0) if where == arg(move, "where") else 0.0


@register("moves", "recharge")
class Recharge(Handler):
    """After a hit its user rests through its next turn (Hyper Beam); a miss or a failure needs no rest."""

    by_id = True

    def after_move(self, move, user, target, dealt):
        user.volatiles[self.key] = RECHARGE_TURNS

    def bans_move(self, name, move, fighter):
        return name if fighter.volatiles[name] < RECHARGE_TURNS else None

    def volatile_end(self, name, fighter, side, turn, rng):
        fighter.volatiles[name] -= 1
        if not fighter.volatiles[name]:
            del fighter.volatiles[name]

    def score_share(self, move, weather):
        return TWO_TURN_SHARE
