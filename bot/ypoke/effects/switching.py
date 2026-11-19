"""Status moves that switch their user out: the next member of its group comes in as after a pivot attack
(`battle._pivot`); each fails with no member waiting. `user` and `foe` are `battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import hooks, register
from ypoke.effects.moves import StatusMove
from ypoke.effects.stats import drop_wanted, shift_all

SNOW = "snow"
STAYS_DRY = "chilly-reception-dry"
PARTING_DROPS = (("attack", -1), ("special_attack", -1))
# The user's own states Baton Pass hands to the member coming in, with its stat stages and confusion.
PASSED = frozenset({"aqua-ring", "curse", "embargo", "focus-energy", "heal-block", "ingrain", "laser-focus",
                    "leech-seed", "magnet-rise", "perish-song", "substitute", "telekinesis"})
HARMFUL = ("curse", "leech-seed", "perish-song")
PASS_WORTH = 2


class SelfSwitch(StatusMove):
    """Picked when the foe has a super-effective hit on the user and a member can come in."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return team.pivot_target() is not None and battle._threatened(user, foe, weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        team = arena.teams[side] if arena.teams else None
        if team is None or team.pivot_target() is None:
            return "", ()
        return self.key, self._before(move, user, foe, side, arena)

    def _before(self, move, user, foe, side, arena) -> tuple:
        return ()

    def switches_user_out(self, move):
        return True


@register("moves", "teleport")
class Teleport(SelfSwitch):
    pass


@register("moves", "chilly-reception")
class ChillyReception(SelfSwitch):
    """Starts snow, unless it already snows or winds hold the sky, and switches out either way."""

    def _apply(self, move, user, foe, side, turn, arena, rng):
        effect, changes = super()._apply(move, user, foe, side, turn, arena, rng)
        weather = arena.weather
        if not effect or weather.current == SNOW or weather.held:
            return effect and STAYS_DRY, changes
        weather.kind = SNOW
        weather.turns_left = hooks.item(user, "weather_turns", SNOW, battle.WEATHER_TURNS, default=battle.WEATHER_TURNS)
        return effect, changes


@register("moves", "parting-shot")
class PartingShot(SelfSwitch):
    """Lowers the foe's Attack and Special Attack by one; the user stays in when neither drop lands. Picked like the
    other self-switches when a drop would matter."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        return (super().wanted(move, team, foes, side, arena, weather)
                and drop_wanted(PARTING_DROPS, team.active, foes.active, weather))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        team = arena.teams[side] if arena.teams else None
        if team is None or team.pivot_target() is None:
            return "", ()
        guarded = battle._stats_guarded(foe, not battle._infiltrates(user))
        landed = shift_all(foe, 1 - side, PARTING_DROPS, guarded=guarded, by=user)
        return (self.key if landed else ""), landed


@register("moves", "baton-pass")
class BatonPass(SelfSwitch):
    """The member coming in takes over the user's stat stages, confusion and the states in `PASSED`. Picked while the
    user has at least two stages more raised than lowered, or a Substitute, and none of `HARMFUL` on it."""

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        if team.pivot_target() is None or any(key in user.volatiles for key in HARMFUL):
            return False
        return sum(user.stages.values()) >= PASS_WORTH or "substitute" in user.volatiles

    def _before(self, move, user, foe, side, arena):
        volatiles = {key: value for key, value in user.volatiles.items() if key in PASSED}
        arena.hazards[side][self.key] = (dict(user.stages), user.confusion_left, volatiles)
        return ()

    def hazard(self, name, passed, fighter, side, turn, rng):
        del fighter.arena.hazards[side][name]
        stages, confusion, volatiles = passed
        fighter.stages, fighter.confusion_left = dict(stages), confusion
        fighter.volatiles.update(volatiles)
        return battle.VolatileTick(turn, side, fighter.combatant.name, name, fighter.hp_percent)
