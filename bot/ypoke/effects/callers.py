"""Status moves that use another move in their place (`calls`): the called move acts as if its user had picked it,
and the action names the caller in `via`. Then the copiers, which change the user's moveset for the battle only:
Mimic until the user switches out, Sketch for the rest of the battle, Transform the whole Pokémon until it switches
out. `user` and `foe` are `battle._Fighter`s; each is picked when the move it would use scores higher than the
user's best damaging move."""

from dataclasses import replace
from functools import cache

from ypoke import battle, battle_data, moves
from ypoke.effects import Handler, register
from ypoke.effects.changers import reshape
from ypoke.effects.moves import StatusMove
from ypoke.effects.protection import last_move

# The keys no caller or copier uses: its own family, the guards, the moves that act on the slot the user picked (a
# self-KO, a switch) and the item swaps.
UNCALLABLE = frozenset({
    "metronome", "mirror-move", "copycat", "sleep-talk", "assist", "me-first", "nature-power", "mimic", "sketch",
    "transform", "struggle", "protect", "kings-shield", "spiky-shield", "baneful-bunker", "obstruct", "silk-trap",
    "burning-bulwark", "mat-block", "quick-guard", "crafty-shield", "endure", "destiny-bond", "snatch", "trick",
    "switcheroo", "bestow", "self-ko", "pivot", "teleport", "baton-pass", "parting-shot", "chilly-reception",
    "shed-tail",
})
NATURE_POWER = {"electric-terrain": 85, "grassy-terrain": 412, "misty-terrain": 585, "psychic-terrain": 94}
PLAIN_NATURE_POWER = 161
ME_FIRST_BOOST = 1.5
TRANSFORM_PP = 5


class Caller(Handler):
    def calls(self, move, user, foe, side, arena, rng):
        called = self._pick(move, user, foe, side, arena, rng)
        return called if called is not None and callable_move(called) else None

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return worth(self._expected(move, user, foe, side, arena, weather), user, foe, weather)

    def _pick(self, move, user, foe, side, arena, rng):
        raise NotImplementedError

    def _expected(self, move, user, foe, side, arena, weather):
        """The move the chooser expects the call to use."""
        raise NotImplementedError


@register("moves", "mirror-move")
class MirrorMove(Caller):
    """The move the foe used last."""

    def _pick(self, move, user, foe, side, arena, rng):
        return last_move(foe)

    def _expected(self, move, user, foe, side, arena, weather):
        return last_move(foe)


@register("moves", "copycat")
class Copycat(Caller):
    """The move used last by either side."""

    def _pick(self, move, user, foe, side, arena, rng):
        return arena.last_move

    def _expected(self, move, user, foe, side, arena, weather):
        return arena.last_move


@register("moves", "me-first")
class MeFirst(Caller):
    """The damaging move the foe picked this turn, at 1.5× power, before the foe acts; fails once it has acted. The
    chooser expects the foe's best damaging move and needs to move first."""

    def _pick(self, move, user, foe, side, arena, rng):
        picked = None if foe.acted or foe.choice is None else foe.combatant.moves[foe.choice]
        return boosted(picked) if picked is not None and picked.damaging else None

    def _expected(self, move, user, foe, side, arena, weather):
        faster = (user.stat("speed", weather) > foe.stat("speed", weather)) != bool(arena.trick_room)
        index = battle._best_move(foe, user, weather) if faster else None
        return None if index is None else boosted(foe.combatant.moves[index])


@register("moves", "nature-power")
class NaturePower(Caller):
    """Thunderbolt, Energy Ball, Moonblast or Psychic on a terrain, Tri Attack without one."""

    def _pick(self, move, user, foe, side, arena, rng):
        return nature_move(arena.terrain)

    def _expected(self, move, user, foe, side, arena, weather):
        return nature_move(arena.terrain)


class LastResort(Caller):
    """A random move: picked only when no damaging move of the user can hurt the foe."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return battle._best_score(user, foe, weather) == 0 and bool(self._pool(move, user, side, arena))

    def _pick(self, move, user, foe, side, arena, rng):
        pool = self._pool(move, user, side, arena)
        return rng.choice(pool) if pool else None

    def _pool(self, move, user, side, arena) -> tuple:
        raise NotImplementedError


@register("moves", "metronome")
class Metronome(LastResort):
    """Any move the battle runs but `UNCALLABLE`."""

    def _pool(self, move, user, side, arena):
        return metronome_pool()


@register("moves", "assist")
class Assist(LastResort):
    """A move of another member of the user's team."""

    def _pool(self, move, user, side, arena):
        team = arena.teams[side] if arena.teams else None
        if team is None:
            return ()
        return tuple(known for index, member in enumerate(team.roster) if index != team.current
                     for known in member.moves if callable_move(known))


@register("moves", "sleep-talk")
class SleepTalk(Caller):
    """Another of the user's own moves, at random, while it sleeps. Picked whenever the user will still be asleep."""

    def acts_asleep(self, move):
        return True

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return user.status == "sleep" and user.sleep_left > 0 and bool(own_calls(move, user))

    def _pick(self, move, user, foe, side, arena, rng):
        pool = own_calls(move, user) if user.status == "sleep" else ()
        return rng.choice(pool) if pool else None


class Copier(StatusMove):
    """The foe's last move takes the copier's slot. Picked when that move scores higher than the user's best."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        copied = last_move(foe)
        return copied is not None and not knows(user, copied) and worth(copied, user, foe, weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        copied = last_move(foe)
        if copied is None or not callable_move(copied) or knows(user, copied):
            return "", ()
        self._copy(user, slot(user, move), copied)
        return self.key, ()

    def _copy(self, user, index, copied) -> None:
        raise NotImplementedError


@register("moves", "mimic")
class Mimic(Copier):
    """Until the user switches out, with the copied move's full PP."""

    def _copy(self, user, index, copied):
        user.entered_pp = user.entered_pp or list(user.pp)
        reshape(user, moves=swapped(user.combatant.moves, index, copied))
        user.pp[index] = copied.pp


@register("moves", "sketch")
class Sketch(Copier):
    """For the rest of the battle, with the copied move's full PP; the saved party keeps Sketch."""

    def _copy(self, user, index, copied):
        user.combatant = replace(user.combatant, moves=swapped(user.combatant.moves, index, copied))
        user.pp[index] = copied.pp
        if user.entered_as is not None:
            user.entered_as = replace(user.entered_as, moves=swapped(user.entered_as.moves, index, copied))
        if user.entered_pp is not None:
            user.entered_pp[index] = copied.pp


@register("moves", "transform")
class Transform(StatusMove):
    """The user takes the foe's types, ability, stats but HP, stat stages and moves (5 PP each) until it switches
    out; fails on a foe behind a Substitute or on one transformed already. Picked while the foe's stats outweigh the
    user's."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return transformable(user, foe) and sum(foe.stats.values()) > sum(user.stats.values())

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not transformable(user, foe):
            return "", ()
        user.entered_stats = user.entered_stats or dict(user.stats)
        user.entered_pp = user.entered_pp or list(user.pp)
        reshape(user, types=foe.combatant.types, ability=foe.ability, moves=foe.combatant.moves)
        user.stats, user.stages = dict(foe.stats), dict(foe.stages)
        user.pp = [min(TRANSFORM_PP, known.pp) for known in foe.combatant.moves]
        user.volatiles[self.key] = True
        user.locked = None
        return self.key, ()


def worth(called, user, foe, weather) -> bool:
    return (called is not None and called.damaging and callable_move(called)
            and battle._move_score(user, foe, called, weather) > battle._best_score(user, foe, weather))


def callable_move(move) -> bool:
    entry = battle_data.table("moves").get(str(move.id))
    return not {move.effect, *(battle_data.keys(entry) if entry else ())} & UNCALLABLE


def boosted(move):
    return replace(move, power=int(move.power * ME_FIRST_BOOST))


def nature_move(terrain):
    return moves.from_data(NATURE_POWER.get(terrain, PLAIN_NATURE_POWER))


@cache
def metronome_pool() -> tuple:
    return tuple(moves.from_data(int(move_id)) for move_id, entry in battle_data.table("moves").items()
                 if battle_data.keys(entry) and not battle_data.is_todo(entry)
                 and not set(battle_data.keys(entry)) & UNCALLABLE)


def own_calls(move, user) -> tuple:
    return tuple(known for known in user.combatant.moves if known.id != move.id and callable_move(known))


def knows(user, move) -> bool:
    return any(known.id == move.id and known.name == move.name for known in user.combatant.moves)


def slot(user, move) -> int:
    return next(index for index, known in enumerate(user.combatant.moves) if known.id == move.id)


def swapped(known: tuple, index: int, move) -> tuple:
    return (*known[:index], move, *known[index + 1:])


def transformable(user, foe) -> bool:
    return "transform" not in user.volatiles and not {"transform", "substitute"} & foe.volatiles.keys()
