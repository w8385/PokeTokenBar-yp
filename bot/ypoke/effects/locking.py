"""Attacks that hold a Pokémon in place. A lock makes its user repeat the move with no PP paid (Outrage, Rollout,
Uproar, Bide): `fighter.volatiles[key]` holds the uses left and `fighter.memory[key]` the move, the turn it last
landed, how many times in a row and what the last use did. A bind hurts its target at each end of turn (Wrap).
`user`, `target` and `fighter` are `battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import Handler, hooks, register
from ypoke.effects.stats import shift
from ypoke.effects.volatiles import due, hurt, ticked

RAMPAGE_USES = (2, 3)
UPROAR_USES = 3
ROLLOUT_USES = 5
BIDE_TURNS = 2
BIND_TURNS = (4, 5)
BIND_SHARE = 8


class Lock(Handler):
    """The user repeats the move for `_uses` turns in a row; a turn it does not land the move ends the lock early,
    and `_spent` acts when the lock runs its course."""

    by_id = True

    def draws(self, move, user, rng):
        if self.key not in user.volatiles:
            user.volatiles[self.key] = self._uses(rng)
            user.memory[self.key] = (move, _turn(user), 0, ())
        landed = user.memory[self.key][2] + 1
        user.volatiles[self.key] -= 1
        spent = ()
        if not user.volatiles[self.key]:
            del user.volatiles[self.key]
            spent = self._spent(user, rng)
        user.memory[self.key] = (move, _turn(user), landed, spent)

    def after_move(self, move, user, target, dealt):
        _, _, landed, spent = user.memory[self.key]
        started = landed == 1 and self.key in user.volatiles
        return (*((battle.Change(user.side, user.combatant.name, self.key),) if started else ()), *spent)

    def readied(self, name, fighter):
        return fighter.memory[name][0]

    def forces_move(self, name, attacker):
        return attacker.last_used

    def volatile_end(self, name, fighter, side, turn, rng):
        if fighter.memory[name][1] != turn:
            del fighter.volatiles[name]

    def _uses(self, rng) -> int:
        raise NotImplementedError

    def _spent(self, user, rng) -> tuple:
        return ()


@register("moves", "rampage")
class Rampage(Lock):
    """Outrage and Thrash: two or three turns, then the tired user is confused."""

    def _uses(self, rng):
        return rng.randint(*RAMPAGE_USES)

    def _spent(self, user, rng):
        if not battle._open_to("confusion", user):
            return ()
        user.confusion_left = rng.randint(*battle.CONFUSION_TURNS)
        return (battle.Change(user.side, user.combatant.name, "fatigue"),)


@register("moves", "uproar")
class Uproar(Lock):
    """Three turns, during which its user cannot fall asleep; each hit wakes a sleeping target."""

    def _uses(self, rng):
        return UPROAR_USES

    def guards_ailment(self, name, ailment, fighter, by_foe):
        return ailment == "sleep"

    def after_move(self, move, user, target, dealt):
        changes = super().after_move(move, user, target, dealt)
        if target.status != "sleep" or target.hp == 0:
            return changes
        target.status, target.sleep_left = None, 0
        return (*changes, battle.Change(target.side, target.combatant.name, "woke"))


@register("moves", "rollout")
class Rollout(Lock):
    """Five turns, doubling its power with each hit in a row."""

    def _uses(self, rng):
        return ROLLOUT_USES

    def base_power(self, move, power, scene):
        memory = scene.user.memory.get(self.key)
        landed = memory[2] if memory else 0
        if scene.hit is not None:
            return power * 2 ** max(0, landed - 1)
        return power * 2 ** landed if self.key in scene.user.volatiles else power


@register("moves", "bide")
class Bide(Handler):
    """Stores the damage it takes for two turns, then strikes for twice that; fails when it took none."""

    by_id = True

    def use(self, move, user, foe, side, turn, weather, arena, rng):
        stored = user.volatiles.get(self.key)
        if stored is None:
            user.volatiles[self.key] = [BIDE_TURNS, user.hp, move]
            return {"effect": self.key}
        stored[0] -= 1
        if stored[0]:
            return {"effect": self.key}
        del user.volatiles[self.key]
        user.memory[self.key] = 2 * max(0, stored[1] - user.hp)
        return None if user.memory[self.key] else {"failed": True}

    def fixed_damage(self, move, user, target, rng):
        return user.memory.pop(self.key, 0) if rng is not None else 0

    def readied(self, name, fighter):
        return fighter.volatiles[name][2]

    def forces_move(self, name, attacker):
        return attacker.last_used


@register("moves", "rage")
class Rage(Handler):
    """Each hit the user takes while it keeps using Rage raises its Attack, counted as it rages again."""

    by_id = True

    def draws(self, move, user, rng):
        since = user.volatiles.get(self.key, user.times_hit)
        user.volatiles[self.key] = user.times_hit
        raised = shift(user, user.side, "attack", user.times_hit - since) if user.times_hit > since else None
        user.memory[self.key] = (move.id, () if raised is None else (raised,))

    def after_move(self, move, user, target, dealt):
        return user.memory[self.key][1]

    def volatile_end(self, name, fighter, side, turn, rng):
        if fighter.last_used is None or fighter.combatant.moves[fighter.last_used].id != fighter.memory[name][0]:
            del fighter.volatiles[name]


@register("moves", "binding")
class Binding(Handler):
    """Wrap and its kind: the target loses 1/8 of its max HP at each end of turn for four or five turns, while the
    user stays in. The user's item can make it last longer (Grip Claw) or hurt more (Binding Band)."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        if self.key in target.volatiles:
            return ()
        user.memory[self.key] = token = (_turn(user), user.combatant.name)
        turns = hooks.item(user, "bind_turns", default=None) or rng.randint(*BIND_TURNS)
        target.volatiles[self.key] = [turns, token, hooks.item(user, "bind_share", default=BIND_SHARE)]
        return (battle.Change(1 - side, target.combatant.name, self.key),)

    def tick_due(self, name, fighter):
        turns, _, share = fighter.volatiles[name]
        return due(fighter, share) if turns else 0

    def volatile_end(self, name, fighter, side, turn, rng):
        bind = fighter.volatiles[name]
        if bind[0] == 0 or not _held(fighter, side, bind[1]):
            del fighter.volatiles[name]
            return battle.VolatileEnd(turn, side, fighter.combatant.name, name)
        bind[0] -= 1
        hurt(fighter, bind[2])
        return ticked(fighter, side, turn, name)


def _held(fighter, side: int, token: tuple) -> bool:
    """Whether the Pokémon that bound `fighter` is still in: the foe facing it carries the bind's token."""
    teams = fighter.arena.teams if fighter.arena is not None else None
    if teams is None:
        return True
    binder = teams[1 - side].active
    return binder.hp > 0 and binder.memory.get("binding") == token


def _turn(fighter) -> int:
    return fighter.arena.turn if fighter.arena is not None else 0
