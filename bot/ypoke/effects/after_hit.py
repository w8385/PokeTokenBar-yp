"""Attacks that act on the target or the user once they hit: they take or burn held items, change stat stages, ground
the target, leave a state on it, or take a type from the user. The states they leave count down like the status
moves' (`fighter.volatiles[key]` holds the turns left). `user`, `target` and `fighter` are `battle._Fighter`s."""

from ypoke import battle, move_power
from ypoke.effects import Handler, hooks, register
from ypoke.effects.changers import FIXED_ABILITIES, reshape, shielded
from ypoke.effects.item_moves import hold, received, yields
from ypoke.effects.secondary import afflict
from ypoke.effects.stats import arg, shift
from ypoke.effects.volatiles import due, hurt, ticked
from ypoke.move_effects import SOUND_MOVES

FELL_STINGER_STAGES = 3
EERIE_SPELL_PP = 3
SALT_CURE_SHARE = 8
SALT_CURE_HARSH_SHARE = 4
SALT_CURE_HARSH_TYPES = ("water", "steel")
SYRUP_TURNS = 3
THROAT_CHOP_TURNS = 2
HEAL_BLOCK_TURNS = 2
GRAV_APPLE_BOOST = 1.5
LIFTING_STATES = ("magnet-rise", "telekinesis")


@register("moves", "steal-item")
class StealItem(Handler):
    """Thief and Covet take the target's item when the user holds none."""

    by_id = True

    def after_move(self, move, user, target, dealt):
        if dealt <= 0 or user.hp == 0 or move_power.holds_item(user) or target.item is None or not yields(target):
            return ()
        item = target.item
        hold(target, None)
        hold(user, item)
        log(user).extend(received(user, user.side, turn(user)))
        return ()


@register("moves", "eat-berry")
class EatBerry(Handler):
    """Pluck and Bug Bite eat the target's berry, and its effect acts on the user."""

    by_id = True

    def after_move(self, move, user, target, dealt):
        berry = target.item
        if dealt <= 0 or user.hp == 0 or not hooks.has("items", berry, "eaten") or move_power.kept(target):
            return ()
        hold(target, None)
        held = user.item
        user.item = berry
        log(user).append(hooks.call("items", berry, "eaten", user, user.side, turn(user)))
        user.item = held
        return ()


@register("moves", "burn-berry")
class BurnBerry(Handler):
    """Incinerate burns up the target's berry."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        berry = target.item
        if not hooks.has("items", berry, "eaten") or move_power.kept(target):
            return ()
        hold(target, None)
        log(user).append(battle.ItemEffect(turn(user), 1 - side, target.combatant.name, berry, "burnt"))
        return ()


@register("moves", "fell-stinger")
class FellStinger(Handler):
    by_id = True

    def after_move(self, move, user, target, dealt):
        if dealt <= 0 or target.hp > 0 or user.hp == 0:
            return ()
        change = shift(user, user.side, "attack", FELL_STINGER_STAGES)
        return () if change is None else (change,)


@register("moves", "spectral-thief")
class SpectralThief(Handler):
    """Takes the target's raised stages before the damage, unless the target is immune."""

    by_id = True

    def before_hit(self, move, user, target):
        weather = user.arena.weather.kind if user.arena is not None else None
        if battle._multiplier(move, target, weather) == 0:
            return
        stolen = []
        for key, stage in target.stages.items():
            if stage > 0:
                target.stages[key] = 0
                stolen.append(shift(user, user.side, key, stage))
        user.memory[self.key] = tuple(change for change in stolen if change is not None)

    def after_move(self, move, user, target, dealt):
        return user.memory.pop(self.key, ())


@register("moves", "clear-smog")
class ClearSmog(Handler):
    by_id = True

    def secondary(self, move, user, target, side, rng):
        if not any(target.stages.values()):
            return ()
        target.stages = dict.fromkeys(target.stages, 0)
        return (battle.Change(1 - side, target.combatant.name, "reset"),)


@register("moves", "smack-down")
class SmackDown(Handler):
    """Smack Down and Thousand Arrows bring a floating target down until it switches out, and one flying up (Fly)
    down before it strikes."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        hiding = target.volatiles.get("semi-invulnerable")
        flying = hiding is not None and arg(hiding, "where") == "flying"
        floating = flying or not battle._grounded(target)
        for state in (*LIFTING_STATES, *("semi-invulnerable",) * flying):
            target.volatiles.pop(state, None)
        target.volatiles[self.key] = True
        return (battle.Change(1 - side, target.combatant.name, "grounded"),) if floating else ()

    def grounds(self, name):
        return True


@register("moves", "hits-airborne")
class HitsAirborne(Handler):
    by_id = True

    def hits_airborne(self, move):
        return True


class Countdown(Handler):
    """A state left on the target that lasts `turns` turns, this one included; `_tick` acts at each end of turn."""

    by_id = True
    turns = 0

    def secondary(self, move, user, target, side, rng):
        if self.key in target.volatiles or not self._lands(user, target):
            return ()
        target.volatiles[self.key] = self.turns or True
        return (battle.Change(1 - side, target.combatant.name, self.key),)

    def volatile_end(self, name, fighter, side, turn, rng):
        tick = self._tick(fighter, side, turn)
        if fighter.volatiles[name] is not True:
            fighter.volatiles[name] -= 1
            if fighter.volatiles[name] <= 0:
                del fighter.volatiles[name]
                end = battle.VolatileEnd(turn, side, fighter.combatant.name, name)
                return end if tick is None else (tick, end)
        return tick

    def _lands(self, user, target) -> bool:
        return True

    def _tick(self, fighter, side, turn):
        return None


@register("moves", "throat-chop")
class ThroatChop(Countdown):
    turns = THROAT_CHOP_TURNS

    def bans_move(self, name, move, fighter):
        return name if move.id in SOUND_MOVES else None


@register("moves", "salt-cure")
class SaltCure(Countdown):
    """The target loses 1/8 of its max HP at each end of turn, Water and Steel types 1/4, until it switches out."""

    def tick_due(self, name, fighter):
        return due(fighter, self._share(fighter))

    def _tick(self, fighter, side, turn):
        hurt(fighter, self._share(fighter))
        return ticked(fighter, side, turn, self.key)

    def _share(self, fighter) -> int:
        harsh = any(kind in fighter.combatant.types for kind in SALT_CURE_HARSH_TYPES)
        return SALT_CURE_HARSH_SHARE if harsh else SALT_CURE_SHARE


@register("moves", "syrup-bomb")
class SyrupBomb(Countdown):
    """The target's Speed drops one stage at each of the next three ends of turn."""

    turns = SYRUP_TURNS

    def _tick(self, fighter, side, turn):
        shift(fighter, side, "speed", -1)
        return ticked(fighter, side, turn, self.key)


@register("moves", "psychic-noise")
class PsychicNoise(Handler):
    """Heal Block on the target for two turns."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        if "heal-block" in target.volatiles:
            return ()
        target.volatiles["heal-block"] = HEAL_BLOCK_TURNS
        return (battle.Change(1 - side, target.combatant.name, "heal-block"),)


@register("moves", "sappy-seed")
class SappySeed(Handler):
    """Leech Seed on the target, which Grass types shrug off."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        if "leech-seed" in target.volatiles or "grass" in target.combatant.types:
            return ()
        target.volatiles["leech-seed"] = True
        return (battle.Change(1 - side, target.combatant.name, "leech-seed"),)


@register("moves", "eerie-spell")
class EerieSpell(Handler):
    by_id = True

    def secondary(self, move, user, target, side, rng):
        if target.last_used is None or target.pp[target.last_used] == 0:
            return ()
        target.pp[target.last_used] = max(0, target.pp[target.last_used] - EERIE_SPELL_PP)
        return (battle.Change(1 - side, target.combatant.name, "spite"),)


@register("moves", "core-enforcer")
class CoreEnforcer(Handler):
    """A target that already moved this turn loses its ability."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        if not target.acted or target.ability is None or target.ability in FIXED_ABILITIES or shielded(target):
            return ()
        reshape(target, ability=None)
        return (battle.Change(1 - side, target.combatant.name, "ability-lost"),)


@register("moves", "if-raised")
class IfRaised(Handler):
    """Burning Jealousy burns and Alluring Voice confuses a target whose stats rose this turn (`args.ailment`)."""

    by_id = True

    def secondary(self, move, user, target, side, rng):
        before = target.turn_stages or {}
        if not any(stage > before.get(key, 0) for key, stage in target.stages.items()):
            return ()
        landed = afflict(arg(move, "ailment"), user, target, side, rng)
        return () if landed is None else (landed,)


@register("moves", "loses-type")
class LosesType(Handler):
    """Burn Up and Double Shock fail unless the user has the move's type, then take that type from it."""

    by_id = True

    def fails(self, move, user, target):
        return move.type not in user.combatant.types

    def after_move(self, move, user, target, dealt):
        if move.type not in user.combatant.types:
            return ()
        reshape(user, types=tuple(kind for kind in user.combatant.types if kind != move.type))
        return (battle.Change(user.side, user.combatant.name, f"lost-{move.type}"),)


@register("moves", "wakes-target")
class WakesTarget(Handler):
    """Smelling Salts and Wake-Up Slap double their power on a target with `args.status`, then cure it; Sparkling Aria
    (`args.power` 1) only cures a burn."""

    by_id = True

    def base_power(self, move, power, scene):
        return power * arg(move, "power", 2) if battle._status_of(scene.target) == arg(move, "status") else power

    def secondary(self, move, user, target, side, rng):
        if target.status != arg(move, "status"):
            return ()
        target.status, target.sleep_left = None, 0
        return (battle.Change(1 - side, target.combatant.name, "cure"),)


@register("moves", "false-swipe")
class FalseSwipe(Handler):
    by_id = True

    def spares(self, move):
        return True


@register("moves", "plasma-fists")
class PlasmaFists(Handler):
    """Normal moves turn Electric for the rest of the turn (Ion Deluge)."""

    by_id = True

    def after_move(self, move, user, target, dealt):
        if user.arena is not None:
            user.arena.rooms.setdefault("ion-deluge", 1)
        return ()


@register("moves", "grav-apple")
class GravApple(Handler):
    by_id = True

    def base_power(self, move, power, scene):
        arena = scene.user.arena
        return power * GRAV_APPLE_BOOST if arena is not None and arena.gravity else power


def log(fighter) -> list:
    return fighter.arena.log if fighter.arena is not None else []


def turn(fighter) -> int:
    return fighter.arena.turn if fighter.arena is not None else 0
