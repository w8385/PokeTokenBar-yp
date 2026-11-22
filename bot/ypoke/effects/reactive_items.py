"""One-use held items that answer something done to or by their holder: a hit, a miss, a sound move, Intimidate, Trick
Room, a foe's stat raise, a move-limiting state or a charge turn. Their numbers and per-item arguments live in
`ypoke.items`; `fighter` is the holder, a `battle._Fighter`."""

from ypoke import battle, items
from ypoke.effects import Handler, register
from ypoke.effects.ability_damage import sheer_forced_by

MENTAL_STATES = ("taunt", "encore", "torment", "disable", "heal-block")


@register("items", "air-balloon")
class AirBalloon(Handler):
    """Floats over Ground moves and the ground until a damaging hit pops it."""

    def floats(self, name):
        return True

    def after_move_as_target(self, name, fighter, attacker, move, multiplier, dealt):
        if dealt > 0:
            fighter.item = None
            battle._announce(fighter, _event(fighter, name, "popped"))
        return False


@register("items", "hit-stat-item")
class HitStatItem(Handler):
    """A damaging hit of its type raises one of its holder's stats (Absorb Bulb: Water, Special Attack)."""

    def after_move_as_target(self, name, fighter, attacker, move, multiplier, dealt):
        kind, stat = items.HIT_STAT_ITEMS[name]
        if dealt > 0 and move.type == kind and fighter.hp > 0:
            battle._announce(fighter, _spend(fighter, name, (stat, 1)))
        return False


@register("items", "blunder-policy")
class BlunderPolicy(Handler):
    def on_miss(self, name, fighter):
        return _spend(fighter, name, ("speed", items.BLUNDER_POLICY_STAGES))


@register("items", "throat-spray")
class ThroatSpray(Handler):
    def after_use(self, name, fighter, move, worked):
        if not worked or not move.flagged("sound") or fighter.hp == 0 or sheer_forced_by(fighter, move):
            return None
        return _spend(fighter, name, ("special_attack", 1))


@register("items", "adrenaline-orb")
class AdrenalineOrb(Handler):
    def after_intimidate(self, name, fighter):
        return _spend(fighter, name, ("speed", 1))


@register("items", "room-service")
class RoomService(Handler):
    def on_update(self, name, fighter, side, turn):
        if fighter.arena is None or fighter.arena.trick_room == 0:
            return None
        return _spend(fighter, name, ("speed", -1))


@register("items", "mirror-herb")
class MirrorHerb(Handler):
    """Copies the stat raises the foe's move or ability just gave it, once that action is over."""

    def on_foe_raised(self, name, fighter, key, stages):
        fighter.memory.setdefault(name, []).append((key, stages))

    def on_update(self, name, fighter, side, turn):
        raised = fighter.memory.pop(name, [])
        return _spend(fighter, name, *raised, copied=True) if raised else None


@register("items", "mental-herb")
class MentalHerb(Handler):
    """Ends Taunt, Encore, Torment, Disable and Heal Block on its holder."""

    def on_update(self, name, fighter, side, turn):
        ended = [state for state in MENTAL_STATES if state in fighter.volatiles]
        if not ended:
            return None
        for state in ended:
            del fighter.volatiles[state]
            fighter.memory.pop(state, None)
        fighter.item = None
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "cure")


@register("items", "power-herb")
class PowerHerb(Handler):
    """Its holder's two-turn move hits at once; the move uses the herb up (`two_turn`)."""

    def skips_charge(self, name):
        return True


@register("items", "terrain-seed")
class TerrainSeed(Handler):
    """Raises a stat of its holder once its terrain is up (Electric Seed: Electric Terrain, Defense)."""

    def on_update(self, name, fighter, side, turn):
        terrain, stat = items.TERRAIN_SEEDS[name]
        if fighter.arena is None or fighter.arena.terrain != terrain:
            return None
        return _spend(fighter, name, (stat, 1))


@register("items", "booster-energy")
class BoosterEnergy(Handler):
    """Sets off Protosynthesis or Quark Drive without its field; the ability uses it up (`ability_weather`)."""

    def energizes(self, name):
        return True


@register("items", "utility-umbrella")
class UtilityUmbrella(Handler):
    """Keeps sun and rain off its holder: off its ability and stats, its charge moves, and the moves that hit it."""

    def shelters(self, name):
        return True


@register("items", "safety-goggles")
class SafetyGoggles(Handler):
    """Keeps powder moves, Effect Spore and the sandstorm's and hail's chip off its holder."""

    def powder_proof(self, name):
        return True

    def blocks_weather_chip(self, name):
        return True


@register("items", "covert-cloak")
class CovertCloak(Handler):
    """Keeps the added effects of the foe's moves off its holder (a flinch, a burn, a stat drop)."""

    def blocks_secondary(self, name):
        return True


@register("items", "clear-amulet")
class ClearAmulet(Handler):
    def keeps_stats(self, name):
        return True


@register("items", "ability-shield")
class AbilityShield(Handler):
    """Its holder's ability cannot be changed, lost, suppressed or ignored (`battle._Fighter.ability`, `changers`)."""

    def shields_ability(self, name):
        return True


def _spend(fighter, name, *shifts, copied=False):
    """Uses the item up for the stage changes it makes and returns its event; None, leaving the item, when none can
    land."""
    changes = tuple(filter(None, (battle.shift_stage(fighter, fighter.side, key, stages, copied=copied)
                                  for key, stages in shifts)))
    if not changes:
        return None
    fighter.item = None
    return _event(fighter, name, "used", changes)


def _event(fighter, name, effect, changes=()):
    turn = fighter.arena.turn if fighter.arena is not None else 0
    return battle.ItemEffect(turn, fighter.side, fighter.combatant.name, name, effect, changes)
