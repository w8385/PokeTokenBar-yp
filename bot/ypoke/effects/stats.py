"""Status moves that change stat stages or swap stats. A move's `args` give its `changes` ([stage key, stages]), its
`target` ("user" or "foe") and `cost`, the share of its max HP the user pays (2: half). `user`, `foe` and `fighter`
are `battle._Fighter`s."""

from ypoke import battle, battle_data
from ypoke.battle import shift_stage as shift
from ypoke.effects import hooks, register
from ypoke.effects.moves import StatusMove

FOE_DROP_FLOOR = -2
SWAP_GAIN = 2
SWAP_WORTH = 1.2
SPEED_EDGE = 1.5
STOCKPILE_MAX = 3
ACUPRESSURE_STAGES = 2
CHARGE_POWER = 2.0
PLUS_MINUS = ("plus", "minus")
SUNS = ("sun",)
OFFENSES = ("attack", "special_attack")
DEFENSES = ("defense", "special_defense")


@register("moves", "stages")
class Stages(StatusMove):
    """Raises the user's stages or lowers the foe's. A self-boost is picked once per entry while the user is above
    its cost (or half HP) and a raised stat helps; a drop while the foe's stage is above -2 and the stat matters."""

    snatchable = True

    def targets_foe(self, move):
        return arg(move, "target", "user") == "foe"

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        if self.targets_foe(move):
            return self._ready(move, user, foe) and drop_wanted(arg(move, "changes"), user, foe, weather)
        cost = arg(move, "cost", 0)
        floor = user.max_hp // (cost or 2)
        return (not user.danced and user.hp > floor and self._ready(move, user, foe)
                and boost_wanted(self._changes(move, user, arena), user, foe, weather))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not self._ready(move, user, foe):
            return "", ()
        if self.targets_foe(move):
            guarded = battle._stats_guarded(foe, not battle._infiltrates(user))
            landed = shift_all(foe, 1 - side, arg(move, "changes"), guarded=guarded, by=user)
            return ("stages" if landed else ""), landed
        cost = arg(move, "cost", 0)
        if cost and user.hp <= user.max_hp // cost:
            return "", ()
        landed = shift_all(user, side, self._changes(move, user, arena))
        if not landed:
            return "", ()
        user.danced = True
        if cost:
            user.hp -= user.max_hp // cost
        return "stages", (*landed, *self._after(move, user, side))

    def _ready(self, move, user, foe) -> bool:
        return True

    def _changes(self, move, user, arena):
        return arg(move, "changes")

    def _after(self, move, user, side) -> tuple:
        return ()


def arg(move, field: str, default=None):
    entry = battle_data.table("moves").get(str(move.id)) or {}
    return entry.get("args", {}).get(field, default)


def drop_wanted(changes, user, foe, weather) -> bool:
    if guarded(user, foe):
        return False
    factor = hooks.ability(foe, "stage_factor", default=1)
    return any(stages * factor < 0 and foe.stages[key] > FOE_DROP_FLOOR and useful(foe, user, key, weather)
               for key, stages in changes)


def guarded(user, foe) -> bool:
    """A drop on the foe does nothing: Mist on its side."""
    return battle._stats_guarded(foe, not battle._infiltrates(user))


def useful(fighter, other, key: str, weather) -> bool:
    """Whether `fighter`'s `key` stage matters in this match-up."""
    if key in OFFENSES:
        return _attacks(fighter, physical=key == "attack")
    if key in DEFENSES:
        return _attacks(other, physical=key == "defense")
    if key == "speed":
        return other.stat("speed", weather) >= fighter.stat("speed", weather)
    if key == "accuracy":
        return any(move.damaging and (move.accuracy or 100) < 100 for move in fighter.combatant.moves)
    return True


def _attacks(fighter, physical: bool) -> bool:
    return any(move.damaging and move.physical == physical for move in fighter.combatant.moves)


def boost_wanted(changes, user, foe, weather) -> bool:
    factor = hooks.ability(user, "stage_factor", default=1)
    return any(stages * factor > 0 and user.stages[key] < battle.MAX_STAGE and useful(user, foe, key, weather)
               for key, stages in changes)


def shift_all(fighter, side: int, changes, *, guarded: bool = False, by=None) -> tuple:
    return tuple(change for key, stages in changes
                 if (change := shift(fighter, side, key, stages, guarded=guarded, by=by)) is not None)


@register("moves", "growth")
class Growth(Stages):
    """Twice the stages in sun."""

    def _changes(self, move, user, arena):
        doubled = arena.weather.kind in SUNS
        return [(key, stages * 2 if doubled else stages) for key, stages in arg(move, "changes")]


@register("moves", "stockpile")
class Stockpile(Stages):
    """Up to three times per entry; Swallow spends the count."""

    def _ready(self, move, user, foe):
        return user.memory.get("stockpile", 0) < STOCKPILE_MAX

    def _after(self, move, user, side):
        user.memory["stockpile"] = user.memory.get("stockpile", 0) + 1
        user.danced = user.memory["stockpile"] >= STOCKPILE_MAX
        return ()


@register("moves", "charge")
class Charge(Stages):
    """Also doubles the user's next Electric move: the charge ends once the user tries an Electric move, whether it
    worked or not."""

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return super().wanted(move, team, foes, side, arena, weather) and any(
            other.damaging and other.type == "electric" for other in user.combatant.moves)

    def _after(self, move, user, side):
        user.volatiles[self.key] = True
        return ()

    def field_power(self, name, move, user, target):
        return CHARGE_POWER if move.type == "electric" else None

    def after_own_move(self, name, fighter, move):
        if move.type == "electric" and move.effect != name:
            del fighter.volatiles[name]


@register("moves", "no-retreat")
class NoRetreat(Stages):
    """Once per entry; the trapping does nothing when switching happens only on a faint."""

    def _ready(self, move, user, foe):
        return not user.memory.get(self.key)

    def _after(self, move, user, side):
        user.memory[self.key] = True
        return ()


@register("moves", "take-heart")
class TakeHeart(Stages):
    """Also cures the user's status."""

    def _after(self, move, user, side):
        if user.status is None:
            return ()
        user.status, user.toxic_ticks, user.sleep_left = None, 0, 0
        return (battle.Change(side, user.combatant.name, "cure"),)


@register("moves", "plus-minus")
class PlusMinus(Stages):
    """Only a user with Plus or Minus: the singles side has no partner."""

    def _ready(self, move, user, foe):
        return user.combatant.ability in PLUS_MINUS


@register("moves", "grass-boost")
class GrassBoost(Stages):
    """Raises every Grass type on the field (Rototiller: only grounded ones), the foe's too; fails with none."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return (not user.danced and self._lifts(move, user) and not self._lifts(move, foe)
                and boost_wanted(arg(move, "changes"), user, foe, weather))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        landed = (*(shift_all(user, side, arg(move, "changes")) if self._lifts(move, user) else ()),
                  *(shift_all(foe, 1 - side, arg(move, "changes")) if self._lifts(move, foe) else ()))
        if not landed:
            return "", ()
        user.danced = True
        return "stages", landed

    @staticmethod
    def _lifts(move, fighter) -> bool:
        return "grass" in fighter.combatant.types and (not arg(move, "grounded") or battle._grounded(fighter))


@register("moves", "venom-drench")
class VenomDrench(Stages):
    """Only on a poisoned foe."""

    def _ready(self, move, user, foe):
        return foe.status in ("poison", "toxic")


@register("moves", "acupressure")
class Acupressure(Stages):
    """+2 to a random stage below +6, accuracy and evasion included."""

    def wanted(self, move, team, foes, side, arena, weather):
        user = team.active
        return not user.danced and user.hp * 2 > user.max_hp and any(
            stage < battle.MAX_STAGE for stage in user.stages.values())

    def _apply(self, move, user, foe, side, turn, arena, rng):
        open_keys = self._changes(move, user, arena)
        if not open_keys:
            return "", ()
        user.danced = True
        return "stages", (shift(user, side, *rng.choice(open_keys)),)

    def _changes(self, move, user, arena):
        return [(key, ACUPRESSURE_STAGES) for key in battle.STAGES if user.stages[key] < battle.MAX_STAGE]


@register("moves", "psych-up")
class PsychUp(StatusMove):
    """Copies the foe's stages, accuracy and evasion included."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return sum(foe.stages.values()) - sum(user.stages.values()) >= SWAP_GAIN

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if user.stages == foe.stages:
            return "", ()
        user.stages = dict(foe.stages)
        return self.key, ()


@register("moves", "topsy-turvy")
class TopsyTurvy(StatusMove):
    """Inverts the foe's stages."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        return sum(foes.active.stages.values()) >= SWAP_GAIN

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if not any(foe.stages.values()):
            return "", ()
        foe.stages = {key: -stage for key, stage in foe.stages.items()}
        return self.key, ()


@register("moves", "stage-swap")
class StageSwap(StatusMove):
    """Swaps the `stats` stages (all of them for Heart Swap) between the user and the foe."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        keys = arg(move, "stats", battle.STAGES)
        return sum(foe.stages[key] - user.stages[key] for key in keys) >= SWAP_GAIN

    def _apply(self, move, user, foe, side, turn, arena, rng):
        keys = arg(move, "stats", battle.STAGES)
        if all(user.stages[key] == foe.stages[key] for key in keys):
            return "", ()
        for key in keys:
            user.stages[key], foe.stages[key] = foe.stages[key], user.stages[key]
        return self.key, ()


@register("moves", "stat-swap")
class StatSwap(StatusMove):
    """Changes raw stats until the Pokémon leaves: `mode` "swap" trades the user's and the foe's `stats` (Speed
    Swap), "split" sets both to their average (Power Split, Guard Split), "trick" swaps the user's own pair (Power
    Trick, Power Shift)."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        after = self._result(move, user, foe)
        return after is not None and _offense(user, *after) > _offense(user, user.stats, foe.stats) * SWAP_WORTH

    def _apply(self, move, user, foe, side, turn, arena, rng):
        result = self._result(move, user, foe)
        if result is None:
            return "", ()
        for fighter, stats in zip((user, foe), result):
            if fighter.entered_stats is None:
                fighter.entered_stats = dict(fighter.stats)
            fighter.stats = stats
        return self.key, ()

    @staticmethod
    def _result(move, user, foe):
        mode, keys = arg(move, "mode"), arg(move, "stats")
        mine, theirs = dict(user.stats), dict(foe.stats)
        if mode == "trick":
            mine[keys[0]], mine[keys[1]] = user.stats[keys[1]], user.stats[keys[0]]
        for key in keys if mode != "trick" else ():
            if mode == "swap":
                mine[key], theirs[key] = foe.stats[key], user.stats[key]
            else:
                mine[key] = theirs[key] = (user.stats[key] + foe.stats[key]) // 2
        return None if (mine, theirs) == (user.stats, foe.stats) else (mine, theirs)


def _offense(user, mine: dict, theirs: dict) -> float:
    """A rough worth of raw stats in the match-up: the user's better attack over the foe's matching defense, over
    the foe's attack against the user's defense, with a speed edge."""
    dealt = max((mine[attack] / theirs[defense] for attack, defense in zip(OFFENSES, DEFENSES)
                 if _attacks(user, physical=attack == "attack")), default=0)
    taken = max(theirs[attack] / mine[defense] for attack, defense in zip(OFFENSES, DEFENSES))
    return dealt / taken * (SPEED_EDGE if mine["speed"] > theirs["speed"] else 1)
