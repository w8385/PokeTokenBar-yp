"""Status moves that guard the user for the turn (the Protect family, Endure, Quick Guard, Crafty Shield, Mat Block)
and Substitute, and the attacks that break through them (Feint). A guard used again on the next turn works with a 1/3 chance per straight success (Gen 9); the
chooser never uses one two turns in a row. `user`, `foe` and `fighter` are `battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import REGISTRY, Handler, hooks, register
from ypoke.effects.healing import foe_hit
from ypoke.effects.moves import StatusMove
from ypoke.effects.stats import arg, shift
from ypoke.move_effects import SOUND_MOVES

STREAK_ODDS = 3
SUBSTITUTE_SHARE = 4
SPIKY_SHARE = 8
ENDURE_PAYOFF = frozenset({175, 179, 283})
TICKING_STATUSES = ("poison", "toxic", "burn")
TICKING_STATES = ("leech-seed", "perish-song", "curse", "nightmare", "octolock", "salt-cure")


class Guard(StatusMove):
    """Sets a state on the user that lasts until the end of the turn. It fails when the user moves last, and on a
    repeat turn unless the 1/3-per-success draw lands (`counted`)."""

    counted = True

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return not guarded_last_turn(user, arena) and self._worth(user, foes.active, weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        streak = streak_of(user, turn)
        if foe.acted or not self._ready(user) or (self.counted and streak and rng.random() * STREAK_ODDS ** streak >= 1):
            user.memory["guard"] = (turn, 0)
            return "", ()
        user.memory["guard"] = (turn, streak + 1 if self.counted else 0)
        user.volatiles[self.key] = True
        return self.key, ()

    def _worth(self, user, foe, weather) -> bool:
        return stalling(user, foe)

    def _ready(self, user) -> bool:
        return True

    def volatile_end(self, name, fighter, side, turn, rng):
        del fighter.volatiles[name]
        return None


def guarded_last_turn(user, arena) -> bool:
    return user.memory.get("guard", (None, 0))[0] == arena.turn - 1


def stalling(user, foe) -> bool:
    """A turn of guarding gains something: the user's Wish lands, or the foe takes damage at the end of it."""
    return (user.volatiles.get("wish", (0,))[0] == 1 or foe.status in TICKING_STATUSES
            or any(state in foe.volatiles for state in TICKING_STATES))


def streak_of(user, turn: int) -> int:
    last_turn, streak = user.memory.get("guard", (None, 0))
    return streak if last_turn == turn - 1 else 0


@register("moves", "protect")
class Protect(Guard):
    """Stops every move aimed at the user, its status moves too unless `blocks_status` is false."""

    blocks_status = True

    def stops_move(self, name, move, priority, target):
        if breaks_guard(move):
            return None
        return name if attacking(move) or self.blocks_status and aimed(move) else None


def breaks_guard(move) -> bool:
    return hooks.move(move, "breaks_guard", default=False)


def attacking(move) -> bool:
    return move.effect not in battle.STATUS_EFFECTS and not move.weather


def aimed(move) -> bool:
    return move.effect in battle.STATUS_EFFECTS and hooks.move(move, "targets_foe", default=False)


@register("moves", "kings-shield", "obstruct", "silk-trap")
class DropShield(Protect):
    """Stops attacks only; a physical one also lowers its user's stat."""

    blocks_status = False
    DROPS = {"kings-shield": ("attack", -1), "obstruct": ("defense", -2), "silk-trap": ("speed", -1)}

    def punishes(self, name, move, attacker, side, rng):
        if not move.physical or not attacking(move):
            return ()
        dropped = shift(attacker, side, *self.DROPS[name])
        return (dropped,) if dropped else ()


@register("moves", "spiky-shield")
class SpikyShield(Protect):
    """A physical move's user loses 1/8 of its max HP."""

    def punishes(self, name, move, attacker, side, rng):
        if move.physical and attacking(move):
            attacker.hp = max(0, attacker.hp - max(1, attacker.max_hp // SPIKY_SHARE))
        return ()


@register("moves", "baneful-bunker", "burning-bulwark")
class AilmentShield(Protect):
    """A physical move's user is poisoned (Baneful Bunker) or burned (Burning Bulwark)."""

    AILMENTS = {"baneful-bunker": "poison", "burning-bulwark": "burn"}

    def punishes(self, name, move, attacker, side, rng):
        ailment = self.AILMENTS[name]
        if (not move.physical or not attacking(move) or not battle._open_to(ailment, attacker, True)
                or hooks.ability(attacker, "blocks_ailment", ailment, default=False)):
            return ()
        return (battle._inflict(ailment, attacker, side, rng),)


@register("moves", "mat-block")
class MatBlock(Protect):
    """Stops attacks, on the user's first turn in only."""

    blocks_status = False
    counted = False

    def _worth(self, user, foe, weather):
        return user.fresh

    def _ready(self, user):
        return user.last_used is None


@register("moves", "quick-guard")
class QuickGuard(Guard):
    """Stops the foe's raised-priority moves. Picked when the foe's last move was one."""

    counted = False

    def _worth(self, user, foe, weather):
        last = last_move(foe)
        return last is not None and last.priority > 0 and attacking(last)

    def stops_move(self, name, move, priority, target):
        return name if priority > 0 and (attacking(move) or aimed(move)) and not breaks_guard(move) else None


@register("moves", "crafty-shield")
class CraftyShield(Guard):
    """Stops the foe's status moves aimed at the user. Picked when the foe's last move was one."""

    counted = False

    def _worth(self, user, foe, weather):
        last = last_move(foe)
        return last is not None and aimed(last)

    def stops_move(self, name, move, priority, target):
        return name if aimed(move) else None


def last_move(fighter):
    """The move `fighter` used last, which the chooser expects it to use again."""
    return None if fighter.last_used is None else fighter.combatant.moves[fighter.last_used]


@register("moves", "endure")
class Endure(Guard):
    """A hit that would knock the user out this turn leaves it 1 HP. Picked when the foe can knock the user out and
    the user has Flail, Reversal or Endeavor to follow."""

    def _worth(self, user, foe, weather):
        return (user.hp > 1 and any(move.id in ENDURE_PAYOFF for move in user.combatant.moves)
                and foe_hit(user, foe, weather) >= user.hp)

    def endures(self, name, fighter, from_full, rng):
        return True


@register("moves", "substitute")
class Substitute(StatusMove):
    """Pays a quarter of the max HP for a doll that takes hits and stops the foe's status moves until it breaks.
    Sound moves and an Infiltrator user pass it. Picked above half HP when a hit would not break it at once or the
    foe has a status move for the user."""

    snatchable = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return (self.key not in user.volatiles and user.hp * 2 > user.max_hp
                and (foe_hit(user, foe, weather) < user.max_hp // SUBSTITUTE_SHARE
                     or any(aimed(foe_move) for foe_move in foe.combatant.moves)))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        cost = max(1, user.max_hp // SUBSTITUTE_SHARE)
        if self.key in user.volatiles or user.hp <= cost:
            return "", ()
        user.hp -= cost
        user.volatiles[self.key] = cost
        return self.key, ()

    def shields(self, name, move, user):
        return None if bypasses(move, user) else name

    def takes_hit(self, name, damage, attacker, defender, move):
        if bypasses(move, attacker):
            return False
        doll = defender.volatiles[name] - damage
        log = defender.arena.log if defender.arena is not None else []
        turn = defender.arena.turn if defender.arena is not None else 0
        if doll <= 0:
            del defender.volatiles[name]
            log.append(battle.VolatileEnd(turn, defender.side, defender.combatant.name, name))
        else:
            defender.volatiles[name] = doll
            share = max(1, doll * 100 // max(1, defender.max_hp // SUBSTITUTE_SHARE))
            log.append(battle.VolatileTick(turn, defender.side, defender.combatant.name, name, share))
        return True


def bypasses(move, user) -> bool:
    return (move.id in SOUND_MOVES or battle._infiltrates(user)
            or hooks.move(move, "passes_substitute", default=False))


@register("moves", "breaks-guard")
class BreaksGuard(Handler):
    """Passes the Protect family and Quick Guard. With `args.lifts` a hit also takes the target's guard down (Feint),
    and with `args.substitute` the move passes a Substitute too (Hyperspace Hole)."""

    by_id = True

    def breaks_guard(self, move):
        return True

    def passes_substitute(self, move):
        return arg(move, "substitute", False)

    def after_move(self, move, user, target, dealt):
        guards = [name for name in target.volatiles if isinstance(REGISTRY["moves"].get(name), (Protect, QuickGuard,
                                                                                                CraftyShield))]
        if not arg(move, "lifts", False) or not guards:
            return ()
        for name in guards:
            del target.volatiles[name]
        return (battle.Change(target.side, target.combatant.name, "guard-lifted"),)


@register("moves", "shed-tail")
class ShedTail(StatusMove):
    """Pays half the max HP for a Substitute that the next member takes over as the user switches out; fails with no
    member to come."""

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return team.pivot_target() is not None and user.hp * 2 > user.max_hp

    def _apply(self, move, user, foe, side, turn, arena, rng):
        team = arena.teams[side] if arena.teams else None
        cost = max(1, user.max_hp // 2)
        if team is None or team.pivot_target() is None or user.hp <= cost:
            return "", ()
        user.hp -= cost
        arena.hazards[side][self.key] = max(1, user.max_hp // SUBSTITUTE_SHARE)
        return self.key, ()

    def switches_user_out(self, move):
        return True

    def hazard(self, name, layers, fighter, side, turn, rng):
        del fighter.arena.hazards[side][name]
        fighter.volatiles["substitute"] = layers
        return battle.VolatileTick(turn, side, fighter.combatant.name, name)
