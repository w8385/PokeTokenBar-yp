"""Multi-hit attacks beyond PokéAPI's hit counts: hits that each draw for accuracy."""

from ypoke.effects import Handler, register


@register("moves", "rolls-each-hit")
class RollsEachHit(Handler):
    """Triple Kick, Triple Axel and Population Bomb: each hit after the first draws for accuracy, and a miss ends the
    move."""

    by_id = True

    def rolls_each_hit(self, move):
        return True
