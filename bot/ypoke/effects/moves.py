"""Move handlers by effect key (`data/battle/moves.json`). `move` is a `battle.Move`; its numbers and ids live in
`ypoke.move_power` and `ypoke.move_effects`. A power rule's `scene` is a `move_power.Scene`."""

from dataclasses import replace

from ypoke import battle, battle_data, move_power
from ypoke.effects import Handler, elsewhere, hooks, register


class StatusMove(Handler):
    """A status move draws for accuracy, then acts; `_apply` returns what it did ("" when it failed) and the changes.
    One aimed at the foe (`hits_foe`) meets the foe's Substitute and Magic Coat; one aimed at its user can be taken by
    the foe's Snatch (`snatchable`)."""

    hits_foe = False
    snatchable = False

    def use(self, move, user, foe, side, turn, weather, arena, rng):
        if (move.accuracy is not None and not battle._sure_hit(user, foe) and not self.never_misses(move, user)
                and rng.random() * 100 >= move.accuracy * battle._accuracy_stages(user, foe)):
            return {"missed": True}
        attacker = user
        taken = ""
        if self.targets_foe(move):
            shield = next(iter(battle._field(foe, "shields", move, user)), "")
            if shield:
                return {"failed": True, "blocked": shield}
            taken = next(iter(battle._field(foe, "reflects", move)), "")
        elif self.snatchable:
            taken = next(iter(battle._field(foe, "snatches", move)), "")
        if taken:
            arena.log.append(battle.VolatileEnd(turn, 1 - side, foe.combatant.name, taken))
            user, foe, side = foe, user, 1 - side
        effect, changes = self._apply(move, user, foe, side, turn, arena, rng)
        return {"failed": not effect, "effect": effect, "changes": changes, "attacker_fainted": attacker.hp == 0}

    def targets_foe(self, move):
        return self.hits_foe

    def never_misses(self, move, user):
        return False

    def _apply(self, move, user, foe, side, turn, arena, rng):
        raise NotImplementedError


LEAD_WEIGHT = 2


@register("moves", "trick-room")
class TrickRoom(StatusMove):
    def wanted(self, move, team, foes, side, arena, weather):
        """Never while it is up (using it again would end it). Otherwise when more of the team, the user and the
        next member counting double, is slower than the foe in the field than faster."""
        if arena.trick_room:
            return False
        foe_speed = foes.active.stat("speed", weather)
        members = [(team.active, LEAD_WEIGHT)] + [
            (team.fighters.get(index) or battle._Fighter.enter(team.roster[index], team.carried[index]),
             LEAD_WEIGHT if position == 0 else 1)
            for position, index in enumerate(team.queue)]
        speeds = [(fighter.stat("speed", weather), weight) for fighter, weight in members if fighter.hp > 0]
        return sum(weight * ((speed < foe_speed) - (speed > foe_speed)) for speed, weight in speeds) > 0

    def _apply(self, move, user, foe, side, turn, arena, rng):
        arena.trick_room = 0 if arena.trick_room else battle.TRICK_ROOM_TURNS
        return ("trick-room" if arena.trick_room else "trick-room-off"), ()


@register("moves", "swords-dance")
class SwordsDance(StatusMove):
    snatchable = True

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return (not user.danced and user.hp * 2 > user.max_hp and user.stages["attack"] < battle.MAX_STAGE
                and hooks.ability(user, "stage_factor", default=1) > 0)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        user.danced = True
        change = battle.shift_stage(user, side, "attack", battle.SWORDS_DANCE_STAGES)
        return ("", ()) if change is None else ("swords-dance", (change,))


@register("moves", "yawn")
class Yawn(StatusMove):
    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        return battle._yawnable(foes.active)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not battle._yawnable(foe, not battle._infiltrates(user)):
            return "", ()
        foe.drowsy_at = turn + 1
        return "yawn", ()


@register("moves", "thunder-wave")
class ThunderWave(StatusMove):
    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return foe.stat("speed", weather) > user.stat("speed", weather) and battle._paralyzable(move, foe)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not battle._paralyzable(move, foe, not battle._infiltrates(user)):
            return "", ()
        return "thunder-wave", (battle._inflict("paralysis", foe, 1 - side, rng),)


@register("moves", "weather")
class WeatherMove(Handler):
    def use(self, move, user, foe, side, turn, weather, arena, rng):
        if weather.kind in (move.weather, battle.STRONG_WINDS):
            return {"failed": True, "weather": battle.STRONG_WINDS if weather.kind == battle.STRONG_WINDS else None}
        turns = hooks.item(user, "weather_turns", move.weather, battle.WEATHER_TURNS, default=battle.WEATHER_TURNS)
        weather.kind, weather.turns_left = move.weather, turns
        return {"weather": move.weather}


@register("moves", "always-hits-in")
class AlwaysHitsIn(Handler):
    """Never misses in its weathers; `args.accuracy_in` sets its accuracy in others (Thunder's 50 in sun)."""

    def skips_accuracy(self, move, weather):
        return weather in move.always_hits_in

    def modify_type(self, move, weather, user):
        args = battle_data.table("moves").get(str(move.id), {}).get("args", {})
        accuracy = args.get("accuracy_in", {}).get(weather)
        return move if accuracy is None else replace(move, accuracy=accuracy)


@register("moves", "always-crit")
class AlwaysCrit(Handler):
    """PokéAPI gives some always-crit moves no crit rate."""

    by_id = True

    def crit_stage(self, move):
        return len(battle.CRITICAL_CHANCES) - 1


@register("moves", "never-miss")
class NeverMiss(Handler):
    """PokéAPI gives some never-miss moves an accuracy of 0."""

    by_id = True

    def skips_accuracy(self, move, weather):
        return True


@register("moves", "pivot")
class Pivot(Handler):
    def switches_user_out(self, move):
        return True


@register("moves", "self-ko")
class SelfKO(Handler):
    def faints_user(self, move):
        return True


class PowerRule(Handler):
    by_id = True

    def base_power(self, move, power, scene):
        return POWER_RULES[self.key](power, scene)


@register("moves", "facade")
class Facade(PowerRule):
    def ignores_burn(self, move):
        return True


@register("moves", "weather-ball")
class WeatherBall(PowerRule):
    def modify_type(self, move, weather, user):
        kind = move_power.WEATHER_BALL_TYPES.get(weather)
        return move if kind is None else replace(move, type=kind)


@register("moves", "knock-off")
class KnockOff(PowerRule):
    def after_move(self, move, user, target, dealt):
        if dealt > 0 and user.hp > 0 and move_power.holds_removable_item(target):
            target.item, target.item_lost, target.locked = None, True, None


@register("moves", "hydro-steam")
class HydroSteam(Handler):
    by_id = True

    def modify_weather_boost(self, move, weather, boost):
        return move_power.HYDRO_STEAM_SUN_BOOST if weather == "sun" else boost


def _doubled(base: int, condition: bool) -> int:
    return base * 2 if condition else base


def _by_hp(base: int, scene) -> int:
    return max(1, base * scene.user.hp // scene.user.max_hp)


def _by_boosts(base: int, scene) -> int:
    return base + move_power.STAT_BOOST_POWER * sum(max(0, stage) for stage in scene.user.stages.values())


def _by_hit(base: int, scene) -> float:
    if scene.hit is None:
        return base * (scene.max_hits + 1) / 2
    return base * (scene.hit + 1)


def _knocked_off(base: int, scene) -> float:
    return base * move_power.KNOCK_OFF_BOOST if move_power.holds_removable_item(scene.target) else base


POWER_RULES = {
    "power-last-respects": lambda base, scene: base + base * scene.user.fallen_allies,
    "power-by-user-hp": _by_hp,
    "power-hex": lambda base, scene: _doubled(base, scene.target.status is not None),
    "facade": lambda base, scene: _doubled(base, scene.user.status in move_power.FACADE_STATUSES),
    "power-brine": lambda base, scene: _doubled(base, scene.target.hp * 2 <= scene.target.max_hp),
    "power-vs-poisoned": lambda base, scene: _doubled(base, scene.target.status in move_power.POISONED),
    "power-acrobatics": lambda base, scene: _doubled(base, not move_power.holds_item(scene.user)),
    "weather-ball": lambda base, scene: _doubled(base, scene.weather in move_power.WEATHER_BALL_TYPES),
    "power-stored": _by_boosts,
    "power-rage-fist": lambda base, scene: min(move_power.RAGE_FIST_MAX_POWER, base + base * scene.user.times_hit),
    "power-revenge": lambda base, scene: _doubled(base, scene.user.hit_by_foe),
    "power-payback": lambda base, scene: _doubled(base, scene.target.acted),
    "power-moves-first": lambda base, scene: _doubled(base, not scene.target.acted),
    "power-retaliate": lambda base, scene: _doubled(base, scene.user.ally_fell_last_turn),
    "power-after-fail": lambda base, scene: _doubled(base, scene.user.flopped_last),
    "power-lash-out": lambda base, scene: _doubled(base, scene.user.lowered),
    "knock-off": _knocked_off,
    "power-super-effective": lambda base, scene: (
        base * move_power.SUPER_EFFECTIVE_BOOST if scene.multiplier > 1 else base),
    "power-solar": lambda base, scene: base / 2 if scene.weather in move_power.SOLAR_WEAK_WEATHERS else base,
    "power-by-hit": _by_hit,
}
register("moves", *(key for key in POWER_RULES if key not in ("facade", "weather-ball", "knock-off")))(PowerRule)

elsewhere("moves", "battle: a move with no other key only deals its damage", "damage")
elsewhere("moves", "battle.STRUGGLE: the typeless move a Pokémon out of PP uses, with its own recoil", "struggle")
elsewhere("moves", "pokeapi.move_from: the move's poison is toxic", "badly-poisons")
elsewhere("moves", "combatants: the move takes the type of the user's plate", "judgment")
elsewhere("moves", "combatants: the move takes the type of Ogerpon's mask", "ivy-cudgel")
elsewhere("moves", "mega_stones: Rayquaza knowing it Mega Evolves", "dragon-ascent")
