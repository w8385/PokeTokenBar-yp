"""Abilities that raise or lower stat stages, or keep and reshape stage changes. `holder` and `fighter` are
`battle._Fighter`s; a `hit` is a `battle.Hit`. The stages each one moves (`args.raises`) live in `ypoke.abilities`."""

from ypoke import abilities, battle
from ypoke.effects import Handler, register


@register("abilities", "ko-boost")
class KoBoost(Handler):
    """Moxie, Chilling Neigh, Grim Neigh: knocking a foe out with a move raises `args.raises`."""

    def source_after_faint(self, name, hit):
        if hit.target.hp > 0 or hit.user.hp == 0:
            return None
        return _raised(name, hit.user, abilities.KO_RAISES[name])


@register("abilities", "battle-bond")
class BattleBond(Handler):
    """The first foe the holder knocks out with a move raises `args.raises`, once a battle."""

    def source_after_faint(self, name, hit):
        user = hit.user
        if hit.target.hp > 0 or user.hp == 0 or name in user.once:
            return None
        user.once.add(name)
        return _raised(name, user, abilities.ONCE_KO_RAISES[name])


@register("abilities", "beast-boost")
class BeastBoost(Handler):
    """Knocking a foe out with a move raises the holder's highest stat, before stages; the first in a tie."""

    def source_after_faint(self, name, hit):
        user = hit.user
        if hit.target.hp > 0 or user.hp == 0:
            return None
        return _raised(name, user, ((max(battle.BATTLE_STATS, key=user.stats.__getitem__), 1),))


@register("abilities", "soul-heart")
class SoulHeart(Handler):
    def on_foe_fainted(self, name, holder):
        return _raised(name, holder, abilities.SOUL_HEART_RAISES)


@register("abilities", "stat-answer")
class StatAnswer(Handler):
    """Defiant, Competitive: a foe lowering any of the holder's stats raises `args.raises`."""

    def on_stat_lowered(self, name, fighter, side):
        return _raised(name, fighter, abilities.ANSWER_RAISES[name])


@register("abilities", "entry-boost")
class EntryBoost(Handler):
    """Intrepid Sword, Dauntless Shield: the first entry of a battle raises `args.raises`."""

    def on_entry(self, name, fighter, foe, side, weather):
        if name in fighter.once:
            return None
        fighter.once.add(name)
        changes = _shifted(fighter, abilities.ENTRY_RAISES[name])
        return battle.AbilityEntry(side, fighter.combatant.name, name, changes=changes) if changes else None


@register("abilities", "supersweet-syrup")
class SupersweetSyrup(Handler):
    """The first entry of a battle lowers the foe's evasion."""

    def on_entry(self, name, fighter, foe, side, weather):
        if name in fighter.once or foe.hp == 0:
            return None
        fighter.once.add(name)
        change = battle.shift_stage(foe, 1 - side, "evasion", -1, guarded=battle._stats_guarded(foe), by=fighter)
        return battle.AbilityTrigger(side, fighter.combatant.name, name, change=change)


@register("abilities", "download")
class Download(Handler):
    """Raises Special Attack when the foe's staged Defense is at least its Special Defense, else Attack."""

    def on_entry(self, name, fighter, foe, side, weather):
        if foe.hp == 0:
            return None
        stat = "special_attack" if staged(foe, "defense") >= staged(foe, "special_defense") else "attack"
        changes = _shifted(fighter, ((stat, 1),))
        return battle.AbilityEntry(side, fighter.combatant.name, name, changes=changes) if changes else None


@register("abilities", "hit-boost")
class HitBoost(Handler):
    """Stamina, Weak Armor, Justified: each hit of a damaging move (of `args.types`, any when empty; physical only
    with `args.physical`) moves `args.raises`."""

    def damaging_hit(self, name, hit):
        types, physical = abilities.HIT_TYPES[name], abilities.HIT_PHYSICAL[name]
        if (_unanswered(hit) or types and hit.move.type not in types or physical and not hit.move.physical):
            return None
        return _raised(name, hit.target, abilities.HIT_RAISES[name])


@register("abilities", "rattled")
class Rattled(Handler):
    """Intimidate also raises its `args.raises`."""

    def after_intimidate(self, name, holder, side):
        return _raised(name, holder, abilities.HIT_RAISES[name])


@register("abilities", "half-hp-boost")
class HalfHpBoost(Handler):
    """Berserk, Anger Shell: a hit that takes the holder from above half its HP to half or below moves
    `args.raises`."""

    def after_move_secondary(self, name, hit):
        holder = hit.target
        if _unanswered(hit) or not holder.hp * 2 <= holder.max_hp < (holder.hp + hit.result.total_damage) * 2:
            return None
        return _raised(name, holder, abilities.HALF_HP_RAISES[name])


@register("abilities", "anger-point")
class AngerPoint(Handler):
    """A critical hit maxes the holder's Attack."""

    def damaging_hit(self, name, hit):
        if _unanswered(hit) or not hit.critical:
            return None
        return _raised(name, hit.target, (("attack", 2 * battle.MAX_STAGE),))


@register("abilities", "charge-on-hit")
class ChargeOnHit(Handler):
    """Electromorphosis, Wind Power: a hit by a damaging move (one flagged `args.flag`, any when empty) charges the
    holder like the move Charge."""

    def damaging_hit(self, name, hit):
        flag = abilities.CHARGE_FLAG[name]
        if _unanswered(hit) or flag and not hit.move.flagged(flag):
            return None
        return _charged(name, hit.target)


@register("abilities", "tailwind-charge")
class TailwindCharge(Handler):
    """Wind Power: Tailwind on the holder's side charges it."""

    def on_side_state(self, name, state, holder):
        return _charged(name, holder) if state == abilities.TAILWIND else None


@register("abilities", "tailwind-boost")
class TailwindBoost(Handler):
    """Wind Rider: Tailwind on the holder's side raises its `args.raises`."""

    def on_side_state(self, name, state, holder):
        return _raised(name, holder, abilities.TAILWIND_RAISES[name]) if state == abilities.TAILWIND else None


@register("abilities", "cotton-down")
class CottonDown(Handler):
    """Each hit of a damaging move lowers its user's Speed."""

    def damaging_hit(self, name, hit):
        user, holder = hit.user, hit.target
        if hit.on_substitute or user.hp == 0:
            return None
        change = battle.shift_stage(user, hit.side, "speed", -1, guarded=battle._stats_guarded(user),
                                    by=holder)
        return _act(name, holder, (change,) if change else ())


@register("abilities", "contact-slow")
class ContactSlow(CottonDown):
    """Gooey, Tangling Hair: Cotton Down for contact moves only."""

    def damaging_hit(self, name, hit):
        return super().damaging_hit(name, hit) if hit.contact else None


@register("abilities", "speed-boost")
class SpeedBoost(Handler):
    """Raises Speed at the end of each turn the holder did not enter in."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        return None if fighter.entered_turn == turn else _raised(name, fighter, (("speed", 1),))


@register("abilities", "moody")
class Moody(Handler):
    """At the end of each turn, one stat below +6 rises two stages and another above -6 drops one."""

    def end_of_turn(self, name, fighter, side, turn, rng):
        rising = [stat for stat in battle.BATTLE_STATS if fighter.stages[stat] < battle.MAX_STAGE]
        up = rng.choice(rising) if rising else None
        falling = [stat for stat in battle.BATTLE_STATS if stat != up and fighter.stages[stat] > -battle.MAX_STAGE]
        down = rng.choice(falling) if falling else None
        return _raised(name, fighter, tuple((stat, stages) for stat, stages in ((up, 2), (down, -1)) if stat))


@register("abilities", "contrary")
class Contrary(Handler):
    def stage_factor(self, name):
        return -1


@register("abilities", "simple")
class Simple(Handler):
    def stage_factor(self, name):
        return 2


@register("abilities", "mirror-armor")
class MirrorArmor(Handler):
    def reflects_drop(self, name):
        return True


@register("abilities", "guard-dog")
class GuardDog(Handler):
    """Intimidate raises the holder's Attack instead."""

    def answers_intimidate(self, name, holder, side):
        return _raised(name, holder, (("attack", 1),)) or _act(name, holder, ())


@register("abilities", "opportunist")
class Opportunist(Handler):
    """Copies each stage raise that lands on the foe; a copy is not copied back."""

    def on_foe_raised(self, name, holder, key, stages):
        change = battle.shift_stage(holder, holder.side, key, stages, copied=True)
        return _act(name, holder, (change,) if change else ())


@register("abilities", "steadfast")
class Steadfast(Handler):
    def after_banned(self, name, ban, holder):
        return _raised(name, holder, (("speed", 1),)) if ban == abilities.STEADFAST_BAN else None


def _unanswered(hit) -> bool:
    """A Substitute took the hit or it knocked the holder out."""
    return hit.on_substitute or hit.target.hp == 0


def _raised(name, holder, raises):
    """Moves the holder's own stages by `raises` ([stat, stages]); the `AbilityAct` when any moved."""
    changes = _shifted(holder, raises)
    return _act(name, holder, changes) if changes else None


def _shifted(holder, raises) -> tuple:
    return tuple(filter(None, (battle.shift_stage(holder, holder.side, stat, stages) for stat, stages in raises)))


def _charged(name, holder):
    holder.volatiles[abilities.CHARGE_STATE] = True
    return _act(name, holder, (), effect="charge")


def _act(name, holder, changes, **details):
    turn = holder.arena.turn if holder.arena is not None else 0
    return battle.AbilityAct(turn, holder.side, holder.combatant.name, name, changes=tuple(changes), **details)


def staged(fighter, stat) -> float:
    """The stat with its stages and no other modifier (Download, Protosynthesis)."""
    stage = fighter.stages[stat]
    return fighter.stats[stat] * ((2 + stage) / 2 if stage >= 0 else 2 / (2 - stage))
