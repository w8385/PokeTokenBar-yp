"""Attacks whose power PokéAPI leaves blank or the battle sets: by weight, HP, Speed, PP or stages, by a draw, by a
streak of uses, or by the team. A power rule's `scene` is a `move_power.Scene` (`hit` None when the AI scores the
move, which then gets the mean power); `user` and `target` are `battle._Fighter`s. Weights are in hectograms."""

from dataclasses import replace

from ypoke import battle
from ypoke.effects import Handler, register
from ypoke.effects.healing import restore
from ypoke.effects.stats import arg, shift

TARGET_WEIGHT_POWER = ((100, 20), (250, 40), (500, 60), (1000, 80), (2000, 100))
HEAVIEST_TARGET_POWER = 120
WEIGHT_RATIO_POWER = ((5, 120), (4, 100), (3, 80), (2, 60))
HEAVIER_TARGET_POWER = 40
FLAIL_SCALE = 48
FLAIL_POWER = ((1, 200), (4, 150), (9, 100), (16, 80), (32, 40))
FLAIL_HEALTHY_POWER = 20
SPEED_RATIO_POWER = ((4, 150), (3, 120), (2, 80), (1, 60))
FASTER_TARGET_POWER = 40
GYRO_BALL_FACTOR = 25
GYRO_BALL_MAX = 150
TRUMP_CARD_POWER = {0: 200, 1: 80, 2: 60, 3: 50}
TRUMP_CARD_FULL_POWER = 40
PUNISHMENT_BASE = 60
PUNISHMENT_STEP = 20
PUNISHMENT_MAX = 200
STOCKPILE_POWER = 100
HIDDEN_POWER_TYPES = ("fighting", "flying", "poison", "ground", "rock", "bug", "ghost", "steel", "fire", "water",
                      "grass", "electric", "psychic", "ice", "dragon", "dark")
HIDDEN_POWER_STATS = ("hp", "attack", "defense", "speed", "special_attack", "special_defense")
HIDDEN_POWER_BITS = 2 ** len(HIDDEN_POWER_STATS) - 1
MAGNITUDE_ODDS = {10: 5, 30: 10, 50: 20, 70: 30, 90: 20, 110: 10, 150: 5}
PRESENT_ODDS = {40: 40, 80: 30, 120: 10, 0: 20}
PRESENT_HEAL_SHARE = 4
FICKLE_BEAM_CHANCE = 0.3
FURY_CUTTER_MAX = 160
ECHOED_VOICE_MAX = 200
BEAT_UP_BASE = 5
BEAT_UP_DIVISOR = 10


@register("moves", "power-by-target-weight")
class TargetWeight(Handler):
    """Low Kick and Grass Knot: the heavier the target, the stronger."""

    by_id = True

    def base_power(self, move, power, scene):
        weight = battle._weight(scene.target)
        return next((stepped for limit, stepped in TARGET_WEIGHT_POWER if weight < limit), HEAVIEST_TARGET_POWER)


@register("moves", "power-by-weight-ratio")
class WeightRatio(Handler):
    """Heavy Slam and Heat Crash: the more times heavier the user is than the target, the stronger."""

    by_id = True

    def base_power(self, move, power, scene):
        ratio = battle._weight(scene.user) / max(1, battle._weight(scene.target))
        return next((stepped for least, stepped in WEIGHT_RATIO_POWER if ratio >= least), HEAVIER_TARGET_POWER)


@register("moves", "power-by-low-hp")
class LowHP(Handler):
    """Flail and Reversal: the less HP the user has left, the stronger."""

    by_id = True

    def base_power(self, move, power, scene):
        share = FLAIL_SCALE * scene.user.hp // scene.user.max_hp
        return next((stepped for most, stepped in FLAIL_POWER if share <= most), FLAIL_HEALTHY_POWER)


@register("moves", "power-by-target-hp")
class TargetHP(Handler):
    """Wring Out, Crush Grip and Hard Press: `args.power` at the target's full HP, down in step with its HP."""

    by_id = True

    def base_power(self, move, power, scene):
        return max(1, arg(move, "power") * scene.target.hp // scene.target.max_hp)


@register("moves", "power-friendship")
class Friendship(Handler):
    """Return and Frustration: `args.power`, their power at the highest friendship every battling Pokémon has."""

    by_id = True

    def base_power(self, move, power, scene):
        return arg(move, "power")


@register("moves", "power-by-speed-ratio")
class SpeedRatio(Handler):
    """Electro Ball: the more times faster the user is than the target, the stronger."""

    by_id = True

    def base_power(self, move, power, scene):
        ratio = _speed(scene.user, scene) / max(1, _speed(scene.target, scene))
        return next((stepped for least, stepped in SPEED_RATIO_POWER if ratio >= least), FASTER_TARGET_POWER)


@register("moves", "gyro-ball")
class GyroBall(Handler):
    """The slower the user is than the target, the stronger."""

    by_id = True

    def base_power(self, move, power, scene):
        ratio = _speed(scene.target, scene) / max(1, _speed(scene.user, scene))
        return min(GYRO_BALL_MAX, int(GYRO_BALL_FACTOR * ratio) + 1)


@register("moves", "trump-card")
class TrumpCard(Handler):
    """The less PP it has left after this use, the stronger."""

    by_id = True

    def base_power(self, move, power, scene):
        left = _pp_left(move, scene.user)
        if left is not None and scene.hit is None:
            left -= 1
        return TRUMP_CARD_POWER.get(left, TRUMP_CARD_FULL_POWER)


@register("moves", "punishment")
class Punishment(Handler):
    """Its power rises with each stage the target has raised."""

    by_id = True

    def base_power(self, move, power, scene):
        raised = sum(max(0, stage) for stage in scene.target.stages.values())
        return min(PUNISHMENT_MAX, PUNISHMENT_BASE + PUNISHMENT_STEP * raised)


@register("moves", "spit-up")
class SpitUp(Handler):
    """Spends the Stockpile count like Swallow: its power per count, and the Defense and Sp. Def it raised. Fails
    with no count."""

    by_id = True

    def fails(self, move, user, target):
        return not user.memory.get("stockpile", 0)

    def base_power(self, move, power, scene):
        return STOCKPILE_POWER * scene.user.memory.get("stockpile", 0)

    def after_move(self, move, user, target, result):
        count = user.memory.pop("stockpile", 0)
        return tuple(change for key in ("defense", "special_defense")
                     if (change := shift(user, user.side, key, -count)) is not None)


@register("moves", "hidden-power")
class HiddenPower(Handler):
    """Its type comes from the user's IVs."""

    by_id = True

    def modify_type(self, move, weather, user):
        if user is None:
            return move
        ivs = user.combatant.ivs
        bits = sum((getattr(ivs, stat) & 1) << place for place, stat in enumerate(HIDDEN_POWER_STATS))
        return replace(move, type=HIDDEN_POWER_TYPES[bits * (len(HIDDEN_POWER_TYPES) - 1) // HIDDEN_POWER_BITS])


class Drawn(Handler):
    """A power drawn once per use (`draws`), kept in the user's memory for its hits; the mean when the AI scores it."""

    by_id = True
    odds: dict[int, int] = {}

    def draws(self, move, user, rng):
        user.memory[self.key] = rng.choices(list(self.odds), weights=list(self.odds.values()))[0]

    def base_power(self, move, power, scene):
        if scene.hit is None:
            return sum(drawn * weight for drawn, weight in self.odds.items()) / sum(self.odds.values())
        return scene.user.memory[self.key]


@register("moves", "magnitude")
class Magnitude(Drawn):
    odds = MAGNITUDE_ODDS


@register("moves", "present")
class Present(Drawn):
    """A drawn 0 heals the target a quarter of its max HP instead of hurting it; nothing on a target at full HP."""

    odds = PRESENT_ODDS

    def fixed_damage(self, move, user, target, rng):
        return 0 if rng is not None and user.memory.get(self.key) == 0 else None

    def after_move(self, move, user, target, result):
        if user.memory.get(self.key) != 0 or target.hp in (0, target.max_hp):
            return ()
        restore(target, target.max_hp // PRESENT_HEAL_SHARE)
        return (battle.Change(target.side, target.combatant.name, "healed"),)


@register("moves", "fickle-beam")
class FickleBeam(Handler):
    """Doubles its power on a draw."""

    by_id = True

    def draws(self, move, user, rng):
        user.memory[self.key] = rng.random() < FICKLE_BEAM_CHANCE

    def base_power(self, move, power, scene):
        if scene.hit is None:
            return power * (1 + FICKLE_BEAM_CHANCE)
        return power * 2 if scene.user.memory[self.key] else power


class Streak(Handler):
    """Grows with each turn in a row the user hit with it; a miss, another move or a turn off breaks the streak."""

    by_id = True

    def base_power(self, move, power, scene):
        return self._grown(power, _streak(self.key, scene.user))

    def after_move(self, move, user, target, result):
        user.memory[self.key] = (_turn(user), _streak(self.key, user) + 1)
        return ()

    def _grown(self, power, streak):
        raise NotImplementedError


@register("moves", "fury-cutter")
class FuryCutter(Streak):
    def _grown(self, power, streak):
        return min(FURY_CUTTER_MAX, power * 2 ** streak)


@register("moves", "echoed-voice")
class EchoedVoice(Streak):
    def _grown(self, power, streak):
        return min(ECHOED_VOICE_MAX, power * (streak + 1))


@register("moves", "assurance")
class Assurance(Handler):
    """Doubles on a target already hurt by a move this turn."""

    by_id = True

    def base_power(self, move, power, scene):
        return power * 2 if scene.target.hurt is not None else power


@register("moves", "fusion")
class Fusion(Handler):
    """Fusion Flare and Fusion Bolt double right after the other (`args.partner`) was used in the same turn."""

    by_id = True

    def base_power(self, move, power, scene):
        arena = scene.user.arena
        follows = (arena is not None and arena.last_move is not None and arena.last_move.id == arg(move, "partner")
                   and arena.last_move_turn == arena.turn)
        return power * 2 if follows else power


@register("moves", "beat-up")
class BeatUp(Handler):
    """One hit per member of the user's team that can fight and has no status, the user first; each hit's power is
    5 + that member's base Attack / 10. Fails when no member qualifies."""

    by_id = True

    def fails(self, move, user, target):
        return not strikers(user)

    def hit_count(self, move, user):
        return len(strikers(user)) or 1

    def base_power(self, move, power, scene):
        members = strikers(scene.user)
        if not members:
            return power
        if scene.hit is None:
            return sum(beat(member) for member in members) / len(members)
        return beat(members[min(scene.hit, len(members) - 1)])


def strikers(user) -> list:
    """The combatants that strike: the active user first, then the rest of its team in roster order."""
    team = user.arena.teams[user.side] if user.arena is not None and user.arena.teams else None
    if team is None:
        return [user.combatant] if user.hp > 0 and user.status is None else []
    members = []
    for index, member in enumerate(team.roster):
        fighter = team.fighters.get(index)
        carry = team.carried[index]
        if fighter is not None:
            ready = fighter.hp > 0 and fighter.status is None
            member = fighter.combatant
        else:
            ready = carry is None or carry.hp > 0 and carry.status is None
        if ready:
            members.append(member)
    active = user.combatant
    return sorted(members, key=lambda member: member is not active)


def beat(member) -> int:
    return BEAT_UP_BASE + member.base.attack // BEAT_UP_DIVISOR


def _speed(fighter, scene) -> float:
    return fighter.stat("speed", scene.weather)


def _pp_left(move, user) -> int | None:
    """None for a move the user does not know (called by another move)."""
    index = next((index for index, known in enumerate(user.combatant.moves) if known.id == move.id), None)
    return None if index is None else user.pp[index]


def _streak(key: str, user) -> int:
    turn, count = user.memory.get(key, (None, 0))
    return count if turn is not None and turn == _turn(user) - 1 else 0


def _turn(user) -> int:
    return user.arena.turn if user.arena is not None else 0
