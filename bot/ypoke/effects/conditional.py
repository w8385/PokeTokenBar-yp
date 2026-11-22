"""Attacks that work only at the right moment: on the user's first turn in, against a foe about to attack, after a
hit on the user, against a sleeping foe or one holding an item. `fails` judges the moment as the move is used; the
move chooser runs before this turn's picks, so there `target.choice` is the foe's pick from the last turn. A move
that judges a hit taken this turn does so in `use`, and `wasted` is the chooser's guess at it. `user` and `target`
are `battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import Handler, register
from ypoke.effects.stats import arg

GLAIVE_RUSH_TURNS = 2
GLAIVE_RUSH_DAMAGE = 2.0


class Condition(Handler):
    by_id = True


@register("moves", "first-turn")
class FirstTurn(Condition):
    """Fake Out and First Impression: only before the user used any move since it came in."""

    def fails(self, move, user, target):
        return user.last_used is not None


@register("moves", "foe-attacking")
class FoeAttacking(Condition):
    """Sucker Punch and Thunderclap: only against a target that is about to use a damaging move; Upper Hand
    (`args.priority`) also needs that move to have raised priority."""

    def fails(self, move, user, target):
        picked = picked_move(target)
        return target.acted or not picked.damaging or (arg(move, "priority", False) and picked.priority <= 0)


@register("moves", "focus-punch")
class FocusPunch(Condition):
    """Fails once the foe's damage struck the user this turn; the chooser expects that from a foe that attacks."""

    def use(self, move, user, foe, side, turn, weather, arena, rng):
        return {"failed": True, "blocked": "lost-focus"} if user.hit_by_foe else None

    def wasted(self, move, user, target):
        return "substitute" not in user.volatiles and picked_move(target).damaging


@register("moves", "shell-trap")
class ShellTrap(Condition):
    """Goes off only after a physical hit struck the user this turn."""

    def use(self, move, user, foe, side, turn, weather, arena, rng):
        return None if user.hurt is not None and user.hurt.physical else {"failed": True, "blocked": self.key}

    def wasted(self, move, user, target):
        picked = picked_move(target)
        return not (picked.damaging and picked.physical)


@register("moves", "beak-blast")
class BeakBlast(Condition):
    """Burns a foe whose contact hit struck the user this turn before the beak went off."""

    def after_move(self, move, user, target, result):
        if (user.hurt is None or not user.hurt.contact or target.hp == 0 or not battle._open_to("burn", target, True)
                or battle._blocks_ailment(target, "burn")):
            return ()
        return (battle._inflict("burn", target, target.side, None, user),)


@register("moves", "last-resort")
class LastResort(Condition):
    """Fails until the user has used each of its other moves, and always when it knows no other."""

    def fails(self, move, user, target):
        others = [index for index, known in enumerate(user.combatant.moves) if known.id != move.id]
        return not others or any(user.pp[index] == user.combatant.moves[index].pp for index in others)


@register("moves", "belch")
class Belch(Condition):
    """Fails until the user has eaten a berry in this battle."""

    def fails(self, move, user, target):
        return not user.ate_berry


@register("moves", "shares-type")
class SharesType(Condition):
    """Synchronoise: only on a target that shares a type with the user."""

    def fails(self, move, user, target):
        return not set(user.combatant.types) & set(target.combatant.types)


@register("moves", "target-item")
class TargetItem(Condition):
    """Poltergeist: only on a target holding an item."""

    def fails(self, move, user, target):
        return target.item is None


@register("moves", "target-asleep")
class TargetAsleep(Condition):
    """Dream Eater: only on a sleeping target."""

    def fails(self, move, user, target):
        return battle._status_of(target) != "sleep"


@register("moves", "user-asleep")
class UserAsleep(Condition):
    """Snore: only while the user sleeps, which it does not stop."""

    def acts_asleep(self, move):
        return True

    def fails(self, move, user, target):
        return battle._status_of(user) != "sleep"


@register("moves", "no-repeat")
class NoRepeat(Condition):
    """Gigaton Hammer and Blood Moon fail right after the user used them."""

    def fails(self, move, user, target):
        return user.last_used is not None and user.combatant.moves[user.last_used].id == move.id


@register("moves", "glaive-rush")
class GlaiveRush(Condition):
    """Once it hits, moves on the user never miss and deal double damage through the end of the next turn."""

    def after_move(self, move, user, target, result):
        user.volatiles[self.key] = GLAIVE_RUSH_TURNS
        return ()

    def sure_hit(self, name, attacker):
        return True

    def takes_more(self, name, attacker):
        return GLAIVE_RUSH_DAMAGE

    def volatile_end(self, name, fighter, side, turn, rng):
        fighter.volatiles[name] -= 1
        if not fighter.volatiles[name]:
            del fighter.volatiles[name]


def picked_move(fighter):
    """The move `fighter` picked: this turn's once the turn is under way, the last turn's while moves are chosen."""
    return battle.STRUGGLE if fighter.choice is None else fighter.combatant.moves[fighter.choice]
