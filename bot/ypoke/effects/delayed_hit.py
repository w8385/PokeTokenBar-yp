"""Future Sight and Doom Desire: the hit lands at the end of the second turn after on whoever then stands across from
the user, through Protect, even after the user fainted. `user` and `fighter` are `battle._Fighter`s."""

from dataclasses import replace

from ypoke import battle
from ypoke.effects import Handler, register

DELAY = 3
SHARE = 0.5
RELEASED = "delayed-hit-released"


@register("moves", "delayed-hit")
class DelayedHit(Handler):
    """Fails while one is already pending on the target's side. The hit uses the user's stats when it lands, even
    from the bench."""

    by_id = True

    def score_share(self, move, weather):
        return SHARE

    def fails(self, move, user, target):
        return user.arena is not None and self.key in user.arena.pending[1 - user.side]

    def breaks_guard(self, move):
        return True

    def use(self, move, user, target, side, turn, weather, arena, rng):
        if user.memory.pop(RELEASED, False):
            return None
        arena.pending[1 - side][self.key] = (DELAY, user, move)
        return {"effect": self.key}

    def end_of_turn(self, name, fighter, side, turn, rng):
        arena = fighter.arena
        turns, user, move = arena.pending[side][name]
        if turns > 1:
            arena.pending[side][name] = (turns - 1, user, move)
            return None
        del arena.pending[side][name]
        user.memory[RELEASED] = True
        try:
            landed = battle._strike(turn, user.side, user, fighter, move, (), arena.weather, rng, arena)
            return replace(landed, attacker_fainted=False)
        finally:
            user.memory.pop(RELEASED, None)
