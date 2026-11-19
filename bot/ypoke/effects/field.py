"""Field and side state handlers (`ypoke.field_states`), with the moves, abilities and items that set, use or clear
them. A state's key is the key of the move that sets it: while it lasts, `battle._field` runs that key's state hooks
for the Pokémon it covers. `user`, `foe`, `fighter` and `target` are `battle._Fighter`s; a fighter's `arena` is None
outside a battle, where no state acts."""

from dataclasses import replace

from ypoke import abilities, battle, items
from ypoke import field_states as fs
from ypoke.effects import Handler, hooks, register, stats
from ypoke.effects.item_moves import burdens
from ypoke.effects.moves import StatusMove
from ypoke.type_chart import effectiveness


class Terrain(StatusMove):
    """Picked when it swings the exchange as much as a weather must (`battle.WEATHER_SWING_MIN`)."""

    def wanted(self, move, team, foes, side, arena, weather):
        return (arena.terrain != self.key
                and _terrain_swing(team.active, foes.active, arena, weather, self.key) >= battle.WEATHER_SWING_MIN)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        return (self.key, ()) if _set_terrain(arena, self.key, user) else ("", ())


@register("moves", "electric-terrain")
class ElectricTerrain(Terrain):
    def field_power(self, name, move, user, target):
        return _terrain_boost(move, user, "electric")

    def guards_ailment(self, name, ailment, fighter, by_foe):
        return ailment == "sleep" and battle._grounded(fighter)


@register("moves", "grassy-terrain")
class GrassyTerrain(Terrain):
    def field_power(self, name, move, user, target):
        if move.id in fs.GRASSY_HALVED_MOVES and battle._grounded(target):
            return fs.TERRAIN_HALVED
        return _terrain_boost(move, user, "grass")

    def end_of_turn(self, name, fighter, side, turn, rng):
        if fighter.hp == fighter.max_hp or not battle._grounded(fighter):
            return None
        fighter.hp = min(fighter.max_hp, fighter.hp + max(1, fighter.max_hp // fs.GRASSY_HEAL_FRACTION))
        return battle.TerrainHeal(turn, side, fighter.combatant.name, fighter.hp_percent)


@register("moves", "psychic-terrain")
class PsychicTerrain(Terrain):
    def field_power(self, name, move, user, target):
        return _terrain_boost(move, user, "psychic")

    def stops_move(self, name, move, priority, target):
        attacking = move.effect not in battle.STATUS_EFFECTS and not move.weather
        return self.key if attacking and priority > 0 and battle._grounded(target) else None


@register("moves", "misty-terrain")
class MistyTerrain(Terrain):
    def field_power(self, name, move, user, target):
        return fs.TERRAIN_HALVED if move.type == "dragon" and battle._grounded(target) else None

    def guards_ailment(self, name, ailment, fighter, by_foe):
        return battle._grounded(fighter)


class SideState(StatusMove):
    """A state on the user's side for `turns` turns (the turn it is set counts), set once per team."""

    turns = fs.STATE_TURNS

    def remember(self, name, team):
        team.used.add(name)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if self.key in arena.sides[side]:
            return "", ()
        arena.sides[side][self.key] = _state_turns(user, self.key, self.turns)
        battle._announce(user, hooks.ability(user, "on_side_state", self.key, user))
        return self.key, ()

    def _new(self, team, side, arena):
        return self.key not in team.used and self.key not in arena.sides[side]


class Screen(SideState):
    """Set as its user enters, against the class of the foe's best move."""

    def wanted(self, move, team, foes, side, arena, weather):
        return team.active.fresh and self._new(team, side, arena) and self._covers(
            _best_attack(foes.active, team.active, weather))

    def screen(self, name, move):
        return fs.SCREEN_MULTIPLIER if self._covers(move) else None

    def _covers(self, move):
        raise NotImplementedError


@register("moves", "reflect")
class Reflect(Screen):
    def _covers(self, move):
        return move.physical


@register("moves", "light-screen")
class LightScreen(Screen):
    def _covers(self, move):
        return not move.physical


@register("moves", "aurora-veil")
class AuroraVeil(Screen):
    def use(self, move, user, foe, side, turn, weather, arena, rng):
        if weather.kind not in fs.VEIL_WEATHERS:
            return {"failed": True}
        return super().use(move, user, foe, side, turn, weather, arena, rng)

    def wanted(self, move, team, foes, side, arena, weather):
        return weather in fs.VEIL_WEATHERS and super().wanted(move, team, foes, side, arena, weather)

    def _covers(self, move):
        return True


@register("moves", "tailwind")
class Tailwind(SideState):
    turns = fs.TAILWIND_TURNS

    def wanted(self, move, team, foes, side, arena, weather):
        return (self._new(team, side, arena) and not arena.trick_room
                and foes.active.stat("speed", weather) > team.active.stat("speed", weather))

    def side_stat(self, name, key):
        return fs.TAILWIND_SPEED if key == "speed" else None


@register("moves", "safeguard")
class Safeguard(SideState):
    def wanted(self, move, team, foes, side, arena, weather):
        return self._new(team, side, arena) and any(_inflicts(foe_move) for foe_move in foes.active.combatant.moves)

    def guards_ailment(self, name, ailment, fighter, by_foe):
        return by_foe


@register("moves", "mist")
class Mist(SideState):
    def wanted(self, move, team, foes, side, arena, weather):
        return self._new(team, side, arena) and any(_lowers(foe_move) for foe_move in foes.active.combatant.moves)

    def guards_stats(self, name):
        return True


@register("moves", "lucky-chant")
class LuckyChant(SideState):
    def wanted(self, move, team, foes, side, arena, weather):
        return self._new(team, side, arena) and any(
            hooks.move(foe_move, "crit_stage", default=foe_move.crit_stage) > 0
            for foe_move in foes.active.combatant.moves)

    def guards_crit(self, name):
        return True


@register("moves", "gravity")
class Gravity(StatusMove):
    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return not arena.gravity and not battle._grounded(foes.active) and any(
            known.type == "ground" and known.damaging and user.pp[index] > 0
            for index, known in enumerate(user.combatant.moves))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if arena.gravity:
            return "", ()
        arena.gravity = fs.GRAVITY_TURNS
        return self.key, ()

    def grounds(self, name):
        return True

    def modify_accuracy(self, name):
        return fs.GRAVITY_ACCURACY

    def bans_move(self, name, move, fighter):
        return self.key if move.id in fs.GRAVITY_MOVES else None


@register("moves", "magic-room", "wonder-room")
class Room(StatusMove):
    """For five turns held items do nothing (Magic Room), or each Pokémon's raw Defense and Special Defense trade
    places, stages staying put (Wonder Room); using it again ends it early. Magic Room is picked while the foe's item
    helps it and the user's does not; Wonder Room when the swap guards the user against the foe's attacks more than it
    guards the foe."""

    SWAPPED = {"defense": "special_defense", "special_defense": "defense"}

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        if self.key in arena.rooms:
            return False
        if self.key == "magic-room":
            return (foe.item is not None and not burdens(foe.item, foe)
                    and (user.item is None or burdens(user.item, user)))
        gain = self._guard(user, foe)
        return gain >= stats.SWAP_WORTH and gain > self._guard(foe, user)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if self.key in arena.rooms:
            del arena.rooms[self.key]
            return f"{self.key}-off", ()
        arena.rooms[self.key] = fs.ROOM_TURNS
        return self.key, ()

    def _guard(self, defender, attacker) -> float:
        """How much the swap raises the defense the attacker's damaging moves hit, 1.0 when they hit both."""
        kinds = {known.physical for known in attacker.combatant.moves if known.damaging}
        if len(kinds) != 1:
            return 1.0
        key = "defense" if kinds.pop() else "special_defense"
        return defender.stats[self.SWAPPED[key]] / defender.stats[key]

    def suppresses_items(self, name):
        return True if name == "magic-room" else None

    def swaps_stat(self, name, key):
        return self.SWAPPED.get(key) if name == "wonder-room" else None


@register("moves", "haze")
class Haze(StatusMove):
    def wanted(self, move, team, foes, side, arena, weather):
        raised = sum(max(0, stage) for stage in foes.active.stages.values())
        lowered = sum(min(0, stage) for stage in team.active.stages.values())
        return raised >= fs.AI_HAZE_STAGES or lowered <= -fs.AI_HAZE_STAGES

    def _apply(self, move, user, foe, side, turn, arena, rng):
        for fighter in (user, foe):
            fighter.stages = dict.fromkeys(battle.STAGES, 0)
        return self.key, ()


class Hazard(StatusMove):
    """Laid on the foe's side once per team, while the foe has members to come."""

    def wanted(self, move, team, foes, side, arena, weather):
        return (self.key not in team.used and arena.hazards[1 - side].get(self.key, 0) < fs.MAX_LAYERS[self.key]
                and foes.has_next)

    def remember(self, name, team):
        team.used.add(name)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        return (self.key, ()) if _lay(arena, 1 - side, self.key) else ("", ())


@register("moves", "stealth-rock")
class StealthRock(Hazard):
    def hazard(self, name, layers, fighter, side, turn, rng):
        ratio = effectiveness("rock", fighter.combatant.types)
        if ratio <= 0 or _booted(fighter) or battle._chip_free(fighter):
            return None
        fighter.hp = max(0, fighter.hp - max(1, int(fighter.max_hp * ratio / battle.STEALTH_ROCK_FRACTION)))
        return battle.HazardDamage(turn, side, fighter.combatant.name, fighter.hp_percent, fighter.hp == 0)


@register("moves", "spikes")
class Spikes(Hazard):
    def hazard(self, name, layers, fighter, side, turn, rng):
        if not battle._grounded(fighter) or _booted(fighter) or battle._chip_free(fighter):
            return None
        damage = fighter.max_hp * fs.SPIKES_DAMAGE[layers] // fs.SPIKES_DENOMINATOR
        fighter.hp = max(0, fighter.hp - max(1, damage))
        return battle.HazardHit(turn, side, fighter.combatant.name, name, fighter.hp_percent, fighter.hp == 0)


@register("moves", "toxic-spikes")
class ToxicSpikes(Hazard):
    """A grounded Poison type takes them away, Heavy-Duty Boots or not."""

    def hazard(self, name, layers, fighter, side, turn, rng):
        if not battle._grounded(fighter):
            return None
        if "poison" in fighter.combatant.types:
            del fighter.arena.hazards[side][name]
            return battle.HazardHit(turn, side, fighter.combatant.name, name, fighter.hp_percent, cleared=True)
        ailment = "toxic" if layers >= fs.TOXIC_SPIKES_TOXIC_LAYERS else "poison"
        if (_booted(fighter) or not battle._open_to(ailment, fighter, True)
                or battle._blocks_ailment(fighter, ailment)):
            return None
        change = battle._inflict(ailment, fighter, side, rng)
        return battle.HazardHit(turn, side, fighter.combatant.name, name, fighter.hp_percent, change=change)


@register("moves", "sticky-web")
class StickyWeb(Hazard):
    def hazard(self, name, layers, fighter, side, turn, rng):
        if not battle._grounded(fighter) or _booted(fighter):
            return None
        foe = fighter.arena.foe_of(fighter) if fighter.arena is not None else None
        change = battle.shift_stage(fighter, side, "speed", -1, guarded=battle._stats_guarded(fighter), by=foe)
        if change is None:
            return None
        return battle.HazardHit(turn, side, fighter.combatant.name, name, fighter.hp_percent, change=change)


@register("moves", "defog")
class Defog(StatusMove):
    """Lowers the foe's evasion (not through Mist or a Substitute), then clears the foe's screens, Safeguard and
    Mist, the hazards on both sides and the terrain. Fails when it did none of it."""

    def wanted(self, move, team, foes, side, arena, weather):
        return team.has_next and _layers(arena, side) > _layers(arena, 1 - side)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        dropped = None
        if not any(battle._field(foe, "shields", move, user)):
            dropped = stats.shift(foe, 1 - side, "evasion", fs.DEFOG_EVASION, guarded=stats.guarded(user, foe), by=user)
        gone = [*_cleared(arena, 1 - side, fs.DEFOGGED, move.name, "sides"),
                *_cleared(arena, 1 - side, fs.HAZARDS, move.name, "hazards"),
                *_cleared(arena, side, fs.HAZARDS, move.name, "hazards")]
        terrain = _clear_terrain(arena, move.name)
        return (self.key if gone or terrain or dropped else ""), tuple(filter(None, (dropped,)))


@register("moves", "court-change")
class CourtChange(StatusMove):
    def wanted(self, move, team, foes, side, arena, weather):
        mine = _layers(arena, side) + len(arena.sides[1 - side])
        theirs = _layers(arena, 1 - side) + len(arena.sides[side])
        return (team.has_next or foes.has_next) and mine > theirs

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not any(arena.sides) and not any(arena.hazards):
            return "", ()
        arena.sides.reverse()
        arena.hazards.reverse()
        return self.key, ()


@register("moves", "tidy-up")
class TidyUp(StatusMove):
    """Picked to clear the hazards on its side, or once per entry above half HP like Swords Dance."""

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return (team.has_next and bool(arena.hazards[side])) or (
            not user.danced and user.hp * 2 > user.max_hp and user.stages["attack"] < battle.MAX_STAGE)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        user.danced = True
        gone = [*_cleared(arena, side, fs.HAZARDS, move.name, "hazards"),
                *_cleared(arena, 1 - side, fs.HAZARDS, move.name, "hazards")]
        changes = stats.shift_all(user, side, (("attack", 1), ("speed", 1)))
        return (self.key if gone or changes else ""), changes


@register("moves", "rapid-spin")
class RapidSpin(Handler):
    """Picked while hazards lie on its side and a member is still to come; its Speed raise is PokéAPI's."""

    def wanted(self, move, team, foes, side, arena, weather):
        return team.has_next and bool(arena.hazards[side]) and battle._multiplier(move, foes.active, weather) > 0

    def after_move(self, move, user, target, dealt):
        if dealt > 0 and user.hp > 0:
            _spun_free(user, move)


@register("moves", "mortal-spin")
class MortalSpin(RapidSpin):
    """Its poison is not in PokéAPI's data, so it lands here, after the hit."""

    def after_move(self, move, user, target, dealt):
        if dealt <= 0:
            return None
        _spun_free(user, move)
        if (target.hp == 0 or not battle._open_to("poison", target, not battle._infiltrates(user), user)
                or battle._blocks_ailment(target, "poison")):
            return None
        return (battle._inflict("poison", target, target.side, None, user),)


class FieldMove(Handler):
    by_id = True


@register("moves", "rising-voltage", "expanding-force", "misty-explosion", "psyblade")
class TerrainPower(FieldMove):
    def base_power(self, move, power, scene):
        terrain, grounded, multiplier = fs.TERRAIN_POWER[self.key]
        now = _terrain(scene.user)
        if now is None or terrain not in (None, now):
            return power
        if grounded is not None and not battle._grounded(scene.user if grounded == "user" else scene.target):
            return power
        return power * multiplier


@register("moves", "terrain-pulse")
class TerrainPulse(TerrainPower):
    def modify_type(self, move, weather, user):
        terrain = None if user is None else _terrain(user)
        if terrain is None or not battle._grounded(user):
            return move
        return replace(move, type=fs.TERRAIN_TYPES[terrain])


@register("moves", "grassy-glide")
class GrassyGlide(FieldMove):
    def modify_priority(self, move, fighter):
        return int(_terrain(fighter) == "grassy-terrain" and battle._grounded(fighter))


@register("moves", "steel-roller")
class SteelRoller(FieldMove):
    """Fails with no terrain, so it scores nothing then."""

    def use(self, move, user, foe, side, turn, weather, arena, rng):
        return None if arena.terrain else {"failed": True}

    def base_power(self, move, power, scene):
        return power if _terrain(scene.user) else 0

    def after_move(self, move, user, target, dealt):
        if dealt > 0 and user.arena is not None:
            _clear_terrain(user.arena, move.name)


@register("moves", "ice-spinner")
class IceSpinner(FieldMove):
    def after_move(self, move, user, target, dealt):
        if dealt > 0 and user.hp > 0 and user.arena is not None:
            _clear_terrain(user.arena, move.name)


@register("moves", *fs.HAZARD_ON_HIT)
class HazardOnHit(FieldMove):
    def after_move(self, move, user, target, dealt):
        arena, hazard = user.arena, fs.HAZARD_ON_HIT[self.key]
        if dealt > 0 and user.hp > 0 and arena is not None and _lay(arena, target.side, hazard):
            arena.log.append(battle.FieldStart(arena.turn, target.side, hazard))


@register("moves", "screen-breaker")
class ScreenBreaker(FieldMove):
    """Breaks the screens even when it then misses, but not on a target its type cannot touch."""

    def before_hit(self, move, user, target):
        if target.arena is not None and effectiveness(move.type, target.combatant.types) > 0:
            _cleared(target.arena, target.side, fs.SCREENS, move.name, "sides")


@register("abilities", "terrain-on-entry")
class TerrainOnEntry(Handler):
    def on_entry(self, name, fighter, foe, side, weather):
        terrain = abilities.TERRAIN_ON_ENTRY[name]
        if fighter.arena is None or not _set_terrain(fighter.arena, terrain, fighter):
            return None
        return battle.AbilityField(side, fighter.combatant.name, name, terrain=terrain)


@register("abilities", "terrain-on-hit")
class TerrainOnHit(Handler):
    """Seed Sower: a damaging move that hits the holder sets `args.terrain`."""

    def after_hit(self, name, hit):
        holder, terrain = hit.target, abilities.TERRAIN_ON_HIT[name]
        if hit.shielded or holder.arena is None or not _set_terrain(holder.arena, terrain, holder):
            return None
        return battle.AbilityAct(hit.turn, holder.side, holder.combatant.name, name, effect="terrain", detail=terrain)


@register("abilities", "hazard-on-hit")
class HazardOnFoeHit(Handler):
    """Toxic Debris: a physical move that hits the holder lays `args.hazard` on the user's side."""

    def after_hit(self, name, hit):
        holder, hazard = hit.target, abilities.HAZARD_ON_HIT[name]
        if hit.shielded or not hit.move.physical or holder.arena is None or not _lay(holder.arena, hit.side, hazard):
            return None
        return battle.AbilityAct(hit.turn, holder.side, holder.combatant.name, name, effect="hazard", detail=hazard)


@register("abilities", "field-stat")
class FieldStat(Handler):
    def field_stat(self, name, stat, weather, terrain):
        state = abilities.FIELD_STAT_STATE[name]
        if stat != abilities.FIELD_STAT_STAT[name] or state not in (weather, terrain):
            return 1.0
        return abilities.FIELD_STAT_MULTIPLIER[name]


@register("abilities", "screen-cleaner")
class ScreenCleaner(Handler):
    def on_entry(self, name, fighter, foe, side, weather):
        arena = fighter.arena
        if arena is None:
            return None
        gone = tuple(key for states in arena.sides for key in fs.SCREENS if states.pop(key, None) is not None)
        return battle.AbilityField(side, fighter.combatant.name, name, cleared=gone) if gone else None


@register("abilities", "infiltrator")
class Infiltrator(Handler):
    def infiltrates(self, name):
        return True


@register("abilities", "airborne")
class Airborne(Handler):
    def airborne(self, name):
        return True


@register("items", "state-extender")
class StateExtender(Handler):
    def state_turns(self, name, state, turns):
        return fs.EXTENDED_TURNS if state in items.EXTENDED_STATES[name] else turns


@register("items", "hazard-boots")
class HazardBoots(Handler):
    def ignores_hazards(self, name):
        return True


def _terrain(fighter):
    return None if fighter.arena is None else fighter.arena.terrain


def _terrain_boost(move, user, kind):
    return fs.TERRAIN_BOOST if move.type == kind and battle._grounded(user) else None


def _set_terrain(arena, terrain, setter):
    if arena.terrain == terrain:
        return False
    arena.terrain, arena.terrain_turns = terrain, _state_turns(setter, terrain, fs.STATE_TURNS)
    return True


def _clear_terrain(arena, by):
    if arena.terrain is None:
        return False
    arena.log.append(battle.FieldEnd(arena.turn, arena.terrain, -1, by))
    arena.terrain, arena.terrain_turns = None, 0
    return True


def _state_turns(user, state, turns):
    return hooks.item(user, "state_turns", state, turns, default=turns)


def _lay(arena, side, hazard):
    layers = arena.hazards[side].get(hazard, 0)
    if layers >= fs.MAX_LAYERS[hazard]:
        return False
    arena.hazards[side][hazard] = layers + 1
    return True


def _layers(arena, side):
    return sum(arena.hazards[side].values())


def _spun_free(user, move):
    """Rapid Spin and Mortal Spin clear the hazards on the user's side and free it from a bind."""
    user.volatiles.pop("binding", None)
    if user.arena is not None:
        _cleared(user.arena, user.side, fs.HAZARDS, move.name, "hazards")


def _cleared(arena, side, keys, by, where):
    """Takes `keys` off `side`'s timed states (`where` "sides") or hazards ("hazards") and logs each one taken."""
    states = getattr(arena, where)[side]
    gone = [key for key in keys if states.pop(key, None) is not None]
    arena.log.extend(battle.FieldEnd(arena.turn, key, side, by) for key in gone)
    return gone


def _booted(fighter):
    return hooks.item(fighter, "ignores_hazards", default=False)


def _best_attack(fighter, foe, weather):
    index = battle._best_move(fighter, foe, weather)
    return battle.STRUGGLE if index is None else fighter.combatant.moves[index]


def _terrain_swing(user, foe, arena, weather, terrain):
    """How much better the exchange gets for `user` under `terrain`, like `battle._weather_swing` without the chip."""
    now = arena.terrain
    mine, theirs = battle._best_score(user, foe, weather), battle._best_score(foe, user, weather)
    arena.terrain = terrain
    new_mine, new_theirs = battle._best_score(user, foe, weather), battle._best_score(foe, user, weather)
    arena.terrain = now
    return new_mine / max(1.0, mine) * max(1.0, theirs) / max(1.0, new_theirs)


def _inflicts(move):
    """A foe move worth a Safeguard: a status move that inflicts, or an attack with a high ailment chance."""
    if move.effect in ("yawn", "toxic-spikes"):
        return True
    return move.ailment is not None and (
        move.effect in battle.STATUS_EFFECTS or move.ailment_chance >= fs.AI_AILMENT_CHANCE)


def _lowers(move):
    return (not move.stat_on_user and move.stat_chance >= fs.AI_DROP_CHANCE
            and any(stages < 0 for _, stages in move.stat_changes))
