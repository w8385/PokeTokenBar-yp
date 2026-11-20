"""Berries beyond Sitrus, Lum and the resist berries: the ones eaten in a pinch, the ones that cure one status, and the
ones a hit sets off. Their numbers and per-berry arguments live in `ypoke.items`; `fighter` is the holder, a
`battle._Fighter`. `eaten` is the berry's effect whatever its trigger (Bug Bite, Teatime, Cud Chew)."""

from ypoke import battle, items
from ypoke.effects import Handler, hooks, register

LANSAT_STATE = "focus-energy"


class Berry(Handler):
    """Eaten after an action or at the end of a turn once `_due`, and between the hits of a multi-hit move."""

    def on_update(self, name, fighter, side, turn):
        return self.eaten(name, fighter, side, turn) if self._due(name, fighter) else None

    def between_hits(self, name, fighter):
        if self._due(name, fighter):
            battle._announce(fighter, self.eaten(name, fighter, fighter.side, _turn(fighter)))
        return False

    def craves(self, name, fighter):
        return self._due(name, fighter)

    def _due(self, name, fighter) -> bool:
        return False


class PinchBerry(Berry):
    """Eaten at a quarter of max HP or less (half with Gluttony)."""

    def _due(self, name, fighter):
        return pinched(fighter)


def pinched(fighter) -> bool:
    share = hooks.ability(fighter, "pinch_fraction", default=items.PINCH_FRACTION)
    return 0 < fighter.hp and fighter.hp * share <= fighter.max_hp


@register("items", "stat-berry")
class StatBerry(PinchBerry):
    def eaten(self, name, fighter, side, turn):
        change = battle.shift_stage(fighter, side, items.STAT_BERRIES[name], _ripened(fighter, 1))
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "eaten", tuple(filter(None, (change,))))


@register("items", "starf-berry")
class StarfBerry(PinchBerry):
    """Sharply raises one stat that can still rise, drawn at random."""

    def eaten(self, name, fighter, side, turn):
        open_stats = [key for key in battle.BATTLE_STATS if fighter.stages[key] < battle.MAX_STAGE]
        change = None
        if open_stats:
            key = _rng(fighter).choice(open_stats)
            change = battle.shift_stage(fighter, side, key, _ripened(fighter, items.STARF_STAGES))
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "eaten", tuple(filter(None, (change,))))


@register("items", "lansat-berry")
class LansatBerry(PinchBerry):
    def eaten(self, name, fighter, side, turn):
        fighter.volatiles.setdefault(LANSAT_STATE, True)
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "focus")


@register("items", "micle-berry")
class MicleBerry(PinchBerry):
    """The next move its eater uses gets more accurate."""

    def eaten(self, name, fighter, side, turn):
        fighter.primed = name
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "accuracy")

    def primed_accuracy(self, name):
        return items.MICLE_ACCURACY


@register("items", "custap-berry")
class CustapBerry(Handler):
    """Eaten as the turn starts in a pinch: its holder moves first in its priority bracket."""

    def moves_first(self, name, fighter, rng):
        if not pinched(fighter):
            return False
        battle.use_berry(fighter)
        return True

    def eaten(self, name, fighter, side, turn):
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "eaten")


@register("items", "flavor-berry")
class FlavorBerry(PinchBerry):
    """Heals a third of max HP; confuses a holder whose nature dislikes the flavor."""

    def eaten(self, name, fighter, side, turn):
        heal = max(1, fighter.max_hp // items.FLAVOR_HEAL_FRACTION) * _factor(fighter)
        fighter.hp = min(fighter.max_hp, fighter.hp + heal)
        battle.use_berry(fighter)
        healed = battle.ItemHeal(turn, side, fighter.combatant.name, name, fighter.hp_percent)
        if not _dislikes(fighter, name) or not battle._open_to("confusion", fighter):
            return healed
        battle._inflict("confusion", fighter, side, _rng(fighter))
        return healed, battle.ItemEffect(turn, side, fighter.combatant.name, name, "confusion")

    def craves(self, name, fighter):
        return (fighter.max_hp - fighter.hp) * items.FLAVOR_HEAL_FRACTION >= fighter.max_hp and not _dislikes(
            fighter, name)


def _dislikes(fighter, berry: str) -> bool:
    lowered = battle.NATURE_MODIFIERS.get(fighter.combatant.nature, (None, None))[1]
    return lowered == items.FLAVOR_BERRIES[berry]


@register("items", "oran-berry")
class OranBerry(Berry):
    def _due(self, name, fighter):
        return 0 < fighter.hp and fighter.hp * items.SITRUS_THRESHOLD_FRACTION <= fighter.max_hp

    def eaten(self, name, fighter, side, turn):
        fighter.hp = min(fighter.max_hp, fighter.hp + items.ORAN_HEAL * _factor(fighter))
        battle.use_berry(fighter)
        return battle.ItemHeal(turn, side, fighter.combatant.name, name, fighter.hp_percent)


@register("items", "leppa-berry")
class LeppaBerry(Berry):
    """Gives PP back to a move that ran out, or, eaten on a move's order, to the first move short of its full PP."""

    def _due(self, name, fighter):
        return 0 < fighter.hp and 0 in fighter.pp

    def eaten(self, name, fighter, side, turn):
        full = [move.pp for move in fighter.combatant.moves]
        short = [index for index, left in enumerate(fighter.pp) if left < full[index]]
        index = fighter.pp.index(0) if 0 in fighter.pp else next(iter(short), None)
        if index is not None:
            fighter.pp[index] = min(full[index], fighter.pp[index] + items.LEPPA_PP * _factor(fighter))
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "pp" if index is not None else "eaten")


@register("items", "cure-berry")
class CureBerry(Berry):
    """Cures one status (Cheri: paralysis), or confusion (Persim)."""

    def eaten(self, name, fighter, side, turn):
        cured = self._due(name, fighter)
        if cured and "confusion" in items.CURE_BERRIES[name]:
            fighter.confusion_left = 0
        elif cured:
            fighter.status, fighter.sleep_left, fighter.toxic_ticks = None, 0, 0
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "cure" if cured else "eaten")

    def _due(self, name, fighter):
        cures = items.CURE_BERRIES[name]
        return 0 < fighter.hp and (fighter.status in cures or "confusion" in cures and fighter.confusion_left > 0)


@register("items", "enigma-berry")
class EnigmaBerry(Handler):
    """Heals a quarter of max HP after a super-effective hit."""

    def after_move_as_target(self, name, fighter, attacker, move, multiplier, dealt):
        if not (multiplier > 1 and dealt > 0 and 0 < fighter.hp):
            return False
        heal = max(1, fighter.max_hp // items.ENIGMA_HEAL_FRACTION) * _factor(fighter)
        fighter.hp = min(fighter.max_hp, fighter.hp + heal)
        battle.use_berry(fighter)
        return True

    def eaten(self, name, fighter, side, turn):
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "eaten")


@register("items", "recoil-berry")
class RecoilBerry(Handler):
    """A hit of its move class costs the attacker an eighth of its max HP (Jaboca: physical), even when the hit
    knocks the holder out."""

    def after_move_as_target(self, name, fighter, attacker, move, multiplier, dealt):
        if (dealt <= 0 or move.physical != items.RECOIL_BERRIES[name] or attacker.hp == 0 or attacker is fighter
                or battle._chip_free(attacker)):
            return False
        attacker.hp = max(0, attacker.hp - max(1, attacker.max_hp // items.RECOIL_BERRY_FRACTION) * _factor(fighter))
        battle.use_berry(fighter)
        return True

    def eaten(self, name, fighter, side, turn):
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "eaten")


@register("items", "guard-berry")
class GuardBerry(Handler):
    """A hit of its move class raises the holder's matching defense (Kee: physical, Defense)."""

    def after_move_as_target(self, name, fighter, attacker, move, multiplier, dealt):
        if dealt <= 0 or move.physical != items.GUARD_BERRIES[name] or fighter.hp == 0:
            return False
        self.eaten(name, fighter, fighter.side, _turn(fighter))
        return True

    def eaten(self, name, fighter, side, turn):
        key = "defense" if items.GUARD_BERRIES[name] else "special_defense"
        change = battle.shift_stage(fighter, side, key, _ripened(fighter, 1))
        battle.use_berry(fighter)
        return battle.ItemEffect(turn, side, fighter.combatant.name, name, "eaten", tuple(filter(None, (change,))))


def _ripened(fighter, stages: int) -> int:
    return stages * _factor(fighter)


def _factor(fighter) -> int:
    return hooks.ability(fighter, "berry_factor", default=1)


def _rng(fighter):
    return fighter.arena.rng if fighter.arena is not None else battle._Arena().rng


def _turn(fighter) -> int:
    return fighter.arena.turn if fighter.arena is not None else 0
