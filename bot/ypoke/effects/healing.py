"""Status moves that restore HP or cure a status. A move's `args` give its `share` of the user's max HP (2: half) and
whether it also cures the user (`cure`). `user`, `foe` and `fighter` are `battle._Fighter`s. A healing move is
picked at half HP or below when it heals more than the foe's best hit takes away."""

from dataclasses import replace

from ypoke import battle, move_power
from ypoke.effects import register
from ypoke.effects.moves import StatusMove
from ypoke.effects.stats import Stages, arg, shift

LOW_HP = 2
LAST_RESORT = 4
TWO_THIRDS = (2, 3)
WEATHER_WEAK = 4
RING_SHARE = 16
SWALLOW_SHARES = {1: 4, 2: 2, 3: 1}
REST_TURNS = 2
WISH_TURNS = 2
REFRESHED = ("burn", "poison", "toxic", "paralysis")


class Heal(StatusMove):
    """Restores `_amount` HP; fails at full HP unless it cured a status."""

    snatchable = True

    def heals(self, move):
        return True

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return worth_healing(user, foes.active, self._amount(move, user, foes.active, arena), weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        cured = cure(user, side) if arg(move, "cure") else ()
        if user.hp == user.max_hp and not cured:
            return "", ()
        restore(user, self._amount(move, user, foe, arena))
        return "heal", cured

    def _amount(self, move, user, foe, arena) -> int:
        return user.max_hp // arg(move, "share", LOW_HP)


def worth_healing(user, foe, amount: int, weather) -> bool:
    return user.hp * LOW_HP <= user.max_hp and min(amount, user.max_hp - user.hp) > foe_hit(user, foe, weather)


def foe_hit(user, foe, weather) -> float:
    """The foe's best mean hit on `user`."""
    return max((battle._unrolled_damage(foe, user, typed, battle._multiplier(typed, user, weather), weather)
                for move in foe.combatant.moves if move.damaging
                for typed in (move_power.typed(move, weather, foe),)), default=0)


def cure(fighter, side: int) -> tuple:
    if fighter.status is None:
        return ()
    fighter.status, fighter.toxic_ticks, fighter.sleep_left = None, 0, 0
    return (battle.Change(side, fighter.combatant.name, "cure"),)


def restore(fighter, amount: int) -> None:
    fighter.hp = min(fighter.max_hp, fighter.hp + max(1, amount))


register("moves", "heal")(Heal)


@register("moves", "weather-heal")
class WeatherHeal(Heal):
    """Half, two thirds in its `strong` weather, a quarter in any other weather unless `weak` is false."""

    def _amount(self, move, user, foe, arena):
        kind = arena.weather.kind
        if kind == arg(move, "strong"):
            return user.max_hp * TWO_THIRDS[0] // TWO_THIRDS[1]
        if kind and kind != battle.STRONG_WINDS and arg(move, "weak", True):
            return user.max_hp // WEATHER_WEAK
        return user.max_hp // LOW_HP


@register("moves", "roost")
class Roost(Heal):
    """Also lands the user: it loses its Flying type until the end of the turn."""

    def _apply(self, move, user, foe, side, turn, arena, rng):
        effect, changes = super()._apply(move, user, foe, side, turn, arena, rng)
        types = user.combatant.types
        if effect and "flying" in types:
            user.entered_as = user.entered_as or user.combatant
            user.combatant = replace(user.combatant, types=tuple(kind for kind in types if kind != "flying")
                                     or ("normal",))
            user.volatiles[self.key] = types
        return effect, changes

    def volatile_end(self, name, fighter, side, turn, rng):
        fighter.combatant = replace(fighter.combatant, types=fighter.volatiles.pop(name))
        return None


@register("moves", "swallow")
class Swallow(Heal):
    """Spends the Stockpile count: a quarter, half or all of the HP, and the Defense and Sp. Def it raised."""

    def wanted(self, move, team, foes, side, arena, weather):
        return team.active.memory.get("stockpile", 0) > 0 and super().wanted(move, team, foes, side, arena, weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        count = user.memory.get("stockpile", 0)
        if not count or user.hp == user.max_hp:
            return "", ()
        restore(user, self._amount(move, user, foe, arena))
        del user.memory["stockpile"]
        return "heal", tuple(change for key in ("defense", "special_defense")
                             if (change := shift(user, side, key, -count)) is not None)

    def _amount(self, move, user, foe, arena):
        count = user.memory.get("stockpile", 0)
        return user.max_hp // SWALLOW_SHARES[count] if count else 0


@register("moves", "wish")
class Wish(Heal):
    """Heals half of the user's max HP at the end of the next turn, if it is still in."""

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return (self.key not in user.volatiles and user.hp * LOW_HP <= user.max_hp
                and foe_hit(user, foes.active, weather) < user.hp)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if self.key in user.volatiles:
            return "", ()
        user.volatiles[self.key] = [WISH_TURNS, user.max_hp // LOW_HP]
        return self.key, ()

    def volatile_end(self, name, fighter, side, turn, rng):
        wish = fighter.volatiles[name]
        wish[0] -= 1
        if wish[0] > 0:
            return None
        del fighter.volatiles[name]
        if fighter.hp == fighter.max_hp:
            return None
        restore(fighter, wish[1])
        return battle.VolatileTick(turn, side, fighter.combatant.name, name, fighter.hp_percent)


@register("moves", "heal-foe")
class HealFoe(Heal):
    """Heals the foe by half, or two thirds in its `terrain` (Heal Pulse, Floral Healing). Never picked."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        return False

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if foe.hp == foe.max_hp:
            return "", ()
        share = TWO_THIRDS if arena.terrain and arena.terrain == arg(move, "terrain") else (1, LOW_HP)
        restore(foe, foe.max_hp * share[0] // share[1])
        return "heal-foe", ()


@register("moves", "purify")
class Purify(Heal):
    """Cures the foe's status and heals the user by half; fails on a foe with no status."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        return foes.active.status is not None and super().wanted(move, team, foes, side, arena, weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        cured = cure(foe, 1 - side)
        if not cured:
            return "", ()
        restore(user, user.max_hp // LOW_HP)
        return "heal", cured


@register("moves", "strength-sap")
class StrengthSap(Heal):
    """Heals by the foe's Attack (with its stage) and lowers it; fails at -6."""

    hits_foe = True

    def _apply(self, move, user, foe, side, turn, arena, rng):
        amount = self._amount(move, user, foe, arena)
        dropped = shift(foe, 1 - side, "attack", -1)
        if dropped is None:
            return "", ()
        restore(user, amount)
        return "heal", (dropped,)

    def _amount(self, move, user, foe, arena):
        return int(foe.stat("attack", arena.weather.kind))


@register("moves", "pain-split")
class PainSplit(Heal):
    """Both Pokémon take the average of their HP."""

    hits_foe = True

    def _apply(self, move, user, foe, side, turn, arena, rng):
        average = (user.hp + foe.hp) // 2
        user.hp, foe.hp = min(user.max_hp, average), min(foe.max_hp, average)
        return "pain-split", ()

    def _amount(self, move, user, foe, arena):
        return (user.hp + foe.hp) // 2 - user.hp


@register("moves", "rest")
class Rest(Heal):
    """Fully heals and sleeps two turns; fails at full HP or when the user cannot fall asleep."""

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return (user.hp * LAST_RESORT <= user.max_hp and sleepable(user)
                and user.max_hp - user.hp > foe_hit(user, foes.active, weather))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if user.hp == user.max_hp or user.status == "sleep" or not sleepable(user):
            return "", ()
        user.hp = user.max_hp
        user.status, user.toxic_ticks, user.sleep_left = "sleep", 0, REST_TURNS
        return "rest", (battle.Change(side, user.combatant.name, "sleep"),)


def sleepable(fighter) -> bool:
    return (not any(battle._field(fighter, "guards_ailment", "sleep", fighter, False))
            and not battle._blocks_ailment(fighter, "sleep"))


@register("moves", "aqua-ring", "ingrain")
class Ring(StatusMove):
    """Heals 1/16 at the end of each turn while the user stays in; Ingrain also roots it to the ground."""

    snatchable = True

    def heals(self, move):
        return True

    def wanted(self, move, team, foes, side, arena, weather):
        return self.key not in team.active.volatiles and team.active.hp * LOW_HP > team.active.max_hp

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if self.key in user.volatiles:
            return "", ()
        user.volatiles[self.key] = True
        return self.key, ()

    def volatile_end(self, name, fighter, side, turn, rng):
        if fighter.hp == fighter.max_hp:
            return None
        restore(fighter, fighter.max_hp // RING_SHARE)
        return battle.VolatileTick(turn, side, fighter.combatant.name, name, fighter.hp_percent)

    def grounds(self, name):
        return name == "ingrain"


@register("moves", "heal-bell")
class HealBell(StatusMove):
    """Cures the status of every member of the user's team, in the field or still to come (Heal Bell,
    Aromatherapy)."""

    snatchable = True

    def wanted(self, move, team, foes, side, arena, weather):
        return team.active.status is not None or sum(status is not None for status in statuses(team)) > 1

    def _apply(self, move, user, foe, side, turn, arena, rng):
        team = arena.teams[side] if arena.teams else None
        if team is None:
            cured = cure(user, side)
            return ("heal-bell" if cured else ""), cured
        if not any(status is not None for status in statuses(team)):
            return "", ()
        cured = cure(user, side)
        for fighter in team.fighters.values():
            if fighter.hp > 0:
                cure(fighter, side)
        team.carried = tuple(carry and replace(carry, status=None) for carry in team.carried)
        return "heal-bell", cured


def statuses(team) -> list:
    """The statuses of the members not fainted: entered ones, then those still to come."""
    return [*(fighter.status for fighter in team.fighters.values() if fighter.hp > 0),
            *(carry.status for index, carry in enumerate(team.carried)
              if carry is not None and index not in team.fighters)]


@register("moves", "refresh")
class Refresh(StatusMove):
    snatchable = True

    def wanted(self, move, team, foes, side, arena, weather):
        return team.active.status in REFRESHED

    def _apply(self, move, user, foe, side, turn, arena, rng):
        return ("heal", cure(user, side)) if user.status in REFRESHED else ("", ())


@register("moves", "healing-wish")
class HealingWish(StatusMove):
    """The user faints and the next member to come in is fully healed and cured (Healing Wish, Lunar Dance); fails
    with no member to come. It waits on the side as a hazard that goes once it acts."""

    def wanted(self, move, team, foes, side, arena, weather):
        return team.has_next and last_stand(team.active, foes.active, weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        team = arena.teams[side] if arena.teams else None
        if team is None or not team.has_next:
            return "", ()
        user.hp = 0
        arena.hazards[side][self.key] = 1
        return self.key, ()

    def hazard(self, name, layers, fighter, side, turn, rng):
        del fighter.arena.hazards[side][name]
        fighter.hp, fighter.status, fighter.toxic_ticks, fighter.sleep_left = fighter.max_hp, None, 0, 0
        return battle.VolatileTick(turn, side, fighter.combatant.name, name, fighter.hp_percent)


def last_stand(user, foe, weather) -> bool:
    """At a quarter HP or below and the foe's best hit would knock the user out."""
    return user.hp * LAST_RESORT <= user.max_hp and foe_hit(user, foe, weather) >= user.hp


@register("moves", "revival-blessing")
class RevivalBlessing(StatusMove):
    """Revives the first fainted member at half HP and sends it to the back of the queue."""

    def wanted(self, move, team, foes, side, arena, weather):
        return any(fighter.hp == 0 for fighter in team.fighters.values())

    def _apply(self, move, user, foe, side, turn, arena, rng):
        team = arena.teams[side] if arena.teams else None
        fallen = next((index for index, fighter in (team.fighters.items() if team else ()) if fighter.hp == 0), None)
        if fallen is None:
            return "", ()
        fighter = team.fighters[fallen]
        fighter.hp, fighter.status = fighter.max_hp // LOW_HP, None
        team.queue.append(fallen)
        return "revival-blessing", (battle.Change(side, fighter.combatant.name, "revive"),)


@register("moves", "memento")
class Memento(Stages):
    """Lowers the foe's Attack and Sp. Atk, and the user faints, even when the drop did not land."""

    snatchable = False

    def wanted(self, move, team, foes, side, arena, weather):
        return team.has_next and last_stand(team.active, foes.active, weather)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        _, landed = super()._apply(move, user, foe, side, turn, arena, rng)
        user.hp = 0
        return "memento", landed
