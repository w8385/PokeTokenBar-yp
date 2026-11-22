"""Attacks whose damage is set rather than rolled from power: a fixed HP amount, the user's level, a share of a Pokémon's
HP, or the damage the user just took. `fixed_damage` gets `rng` None when the AI scores the move, and then gives the
mean. `user` and `target` are `battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import Handler, hooks, register
from ypoke.effects.stats import arg

PSYWAVE_RANGE = (50, 150)
RETALIATION_SHARE = 100
OHKO_ACCURACY = 30
OHKO_OFF_TYPE_ACCURACY = 20


@register("moves", "fixed-hp")
class FixedHP(Handler):
    """Sonic Boom and Dragon Rage: `args.hp`."""

    by_id = True

    def fixed_damage(self, move, user, target, rng):
        return arg(move, "hp")


@register("moves", "level-damage")
class LevelDamage(Handler):
    """Seismic Toss and Night Shade: the user's level."""

    by_id = True

    def fixed_damage(self, move, user, target, rng):
        return user.combatant.level


@register("moves", "psywave")
class Psywave(Handler):
    """Psywave: the user's level times 0.5 to 1.5."""

    by_id = True

    def fixed_damage(self, move, user, target, rng):
        level = user.combatant.level
        return level if rng is None else max(1, level * rng.randint(*PSYWAVE_RANGE) // 100)


@register("moves", "half-hp")
class HalfHP(Handler):
    """Super Fang, Nature's Madness and Ruination: half the target's HP."""

    by_id = True

    def fixed_damage(self, move, user, target, rng):
        return max(1, target.hp // 2)


@register("moves", "endeavor")
class Endeavor(Handler):
    """Endeavor: brings the target's HP down to the user's; fails when the target has no more HP than the user."""

    by_id = True

    def fails(self, move, user, target):
        return target.hp <= user.hp

    def fixed_damage(self, move, user, target, rng):
        return max(0, target.hp - user.hp)


@register("moves", "final-gambit")
class FinalGambit(Handler):
    """Final Gambit: the user's HP, and the user faints once it hits."""

    by_id = True

    def fixed_damage(self, move, user, target, rng):
        return user.hp

    def after_move(self, move, user, target, result):
        user.hp = 0
        return ()


@register("moves", "retaliate")
class Retaliate(Handler):
    """Counter, Mirror Coat, Metal Burst and Comeuppance: `args.share` percent of the damage the user took from the
    foe's last attack this turn, of `args.category` (physical, special, or either when absent). Fails without one."""

    by_id = True

    def fails(self, move, user, target):
        return _taken(move, user) is None

    def fixed_damage(self, move, user, target, rng):
        taken = _taken(move, user)
        return None if taken is None else max(1, taken * arg(move, "share", RETALIATION_SHARE) // 100)


@register("moves", "ohko")
class OHKO(Handler):
    """Guillotine, Horn Drill, Fissure and Sheer Cold: the target's HP, hitting 30% of the time plus the level gap and
    failing on a higher-level target or a Sturdy one. Sheer Cold (`args.type` ice) hits 20% of the time from a user
    without that type and fails on a target with it."""

    by_id = True

    def fails(self, move, user, target):
        kind = arg(move, "type")
        return (target.combatant.level > user.combatant.level or kind in target.combatant.types
                or hooks.ability(target, "blocks_ohko", default=False))

    def own_accuracy(self, move, user, target):
        kind = arg(move, "type")
        base = OHKO_ACCURACY if kind is None or kind in user.combatant.types else OHKO_OFF_TYPE_ACCURACY
        return base + user.combatant.level - target.combatant.level

    def fixed_damage(self, move, user, target, rng):
        return target.hp

    def after_move(self, move, user, target, result):
        return (battle.Change(target.side, target.combatant.name, "ohko"),) if target.hp == 0 else ()


def _taken(move, user) -> int | None:
    if user.hurt is None:
        return None
    category = arg(move, "category")
    return user.hurt.dealt if category is None or (category == "physical") == user.hurt.physical else None
