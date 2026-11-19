"""Abilities that change when or whether their holder acts: priority, the order inside a priority bracket, loafing,
the PP a foe pays, self-KO moves and copied dances. `fighter` and `holder` are `battle._Fighter`s."""

from ypoke import abilities
from ypoke.effects import Handler, register
from ypoke.effects.protection import aimed


@register("abilities", "prankster")
class Prankster(Handler):
    """Status moves gain priority, and one aimed at a Dark-type foe fails."""

    def modify_priority(self, name, move, fighter):
        return 0 if move.damaging else abilities.PRANKSTER_PRIORITY

    def fails_against(self, name, move, target):
        return aimed(move) and abilities.PRANKSTER_FOILED_TYPE in target.combatant.types


@register("abilities", "triage")
class Triage(Handler):
    def modify_priority(self, name, move, fighter):
        return abilities.TRIAGE_PRIORITY if move.flagged(abilities.TRIAGE_FLAG) else 0


@register("abilities", "stall")
class Stall(Handler):
    def moves_last(self, name, move):
        return True


@register("abilities", "quick-draw")
class QuickDraw(Handler):
    """Draws for a damaging move only."""

    def moves_first(self, name, move, rng):
        return move.damaging and rng.random() < abilities.QUICK_DRAW_CHANCE


@register("abilities", "mycelium-might")
class MyceliumMight(Handler):
    """Status moves go last in their bracket and leave the target's breakable ability out."""

    def moves_last(self, name, move):
        return not move.damaging

    def breaks_abilities(self, name, move):
        return not move.damaging


@register("abilities", "unburden")
class Unburden(Handler):
    """Speed doubles once the item the holder entered with is gone, until it leaves."""

    def on_entry(self, name, fighter, foe, side, weather):
        fighter.memory[name] = fighter.item is not None

    def modify_stat(self, name, stat, weather, fighter):
        unburdened = stat == "speed" and fighter.memory.get(name) and fighter.item is None
        return 2.0 if unburdened else 1.0


@register("abilities", "truant")
class Truant(Handler):
    """Acts, then loafs the next turn it would act; entering starts it on an acting turn."""

    def skips_turn(self, name, fighter):
        loafing = fighter.memory.pop(name, False)
        if not loafing:
            fighter.memory[name] = True
        return loafing


@register("abilities", "pressure")
class Pressure(Handler):
    def pp_cost(self, name, move):
        return int(move.damaging or aimed(move))


@register("abilities", "damp")
class Damp(Handler):
    """Self-Destruct, Explosion, Misty Explosion and Mind Blown (`args.moves`) fail, and their user stays in."""

    def stops_move(self, name, move, priority, holder, attacker):
        return move.id in abilities.DAMP_MOVES[name]

    def prevents_self_ko(self, name, move):
        return move.id in abilities.DAMP_MOVES[name]


@register("abilities", "dancer")
class Dancer(Handler):
    def copies_dance(self, name):
        return True
