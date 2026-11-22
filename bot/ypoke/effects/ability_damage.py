"""Abilities that change how hard a move hits: its type and power, the stats behind it, the damage dealt or taken,
how many times it hits and whether its added effects land. `user`, `target`, `holder` and `fighter` are
`battle._Fighter`s; the numbers live in `ypoke.abilities`."""

from ypoke import abilities, battle, battle_data
from ypoke.effects import Handler, hooks, register
from ypoke.effects.secondary import meta


@register("abilities", "flag-power")
class FlagPower(Handler):
    """Iron Fist, Strong Jaw, Mega Launcher, Sharpness, Tough Claws, Punk Rock: a move with `args.flag`, ×`args.power`."""

    def modify_power(self, name, move, power, user, target, weather):
        flag = abilities.POWER_FLAG[name]
        flagged = battle.makes_contact(user, move) if flag == "contact" else move.flagged(flag)
        return abilities.FLAG_POWER[name] if flagged else 1.0


@register("abilities", "type-power")
class TypePower(Handler):
    """Steelworker, Transistor, Dragon's Maw, Rocky Payload, Steely Spirit, Fire Mane, Water Bubble: a move of
    `args.type`, ×`args.power`."""

    def modify_power(self, name, move, power, user, target, weather):
        return abilities.TYPE_POWER[name] if move.type == abilities.POWER_TYPE[name] else 1.0


@register("abilities", "ate")
class Ate(Handler):
    """Aerilate, Pixilate, Refrigerate, Galvanize, Dragonize: a Normal move takes `args.type` and hits harder."""

    def retypes(self, name, move):
        return abilities.ATE_TYPE[name] if move.damaging and move.type == "normal" else None

    def modify_power(self, name, move, power, user, target, weather):
        converted = move.type == abilities.ATE_TYPE[name] and data_type(move) == "normal"
        return abilities.ATE_POWER if converted else 1.0


@register("abilities", "normalize")
class Normalize(Handler):
    def retypes(self, name, move):
        return "normal" if move.damaging and move.type is not None else None

    def modify_power(self, name, move, power, user, target, weather):
        return abilities.ATE_POWER if move.type == "normal" else 1.0


@register("abilities", "liquid-voice")
class LiquidVoice(Handler):
    def retypes(self, name, move):
        return "water" if move.flagged("sound") else None


@register("abilities", "reckless")
class Reckless(Handler):
    def modify_power(self, name, move, power, user, target, weather):
        recoils = move.drain < 0 or "crash" in battle_data.keys(battle_data.table("moves").get(str(move.id)) or {})
        return abilities.RECKLESS_POWER if recoils else 1.0


@register("abilities", "sheer-force")
class SheerForce(Handler):
    """A damaging move with an added effect on the target, or one that raises the user, hits harder and loses it."""

    def modify_power(self, name, move, power, user, target, weather):
        return abilities.SHEER_FORCE_POWER if sheer_forced(move) else 1.0

    def secondary_chance(self, name, move):
        return 0.0 if sheer_forced(move) else 1.0


@register("abilities", "serene-grace")
class SereneGrace(Handler):
    def secondary_chance(self, name, move):
        return 2.0


@register("abilities", "shield-dust")
class ShieldDust(Handler):
    def blocks_secondary(self, name):
        return True


@register("abilities", "analytic")
class Analytic(Handler):
    def modify_power(self, name, move, power, user, target, weather):
        return abilities.ANALYTIC_POWER if target is not user and target.acted else 1.0


@register("abilities", "stakeout")
class Stakeout(Handler):
    def modify_power(self, name, move, power, user, target, weather):
        fresh = user.arena is not None and target is not user and target.entered_turn == user.arena.turn > 0
        return 2.0 if fresh else 1.0


@register("abilities", "status-power")
class StatusPower(Handler):
    """Flare Boost and Toxic Boost: a move of the class in `args.physical` while the user has `args.statuses`."""

    def modify_power(self, name, move, power, user, target, weather):
        boosted = move.physical == abilities.STATUS_POWER_PHYSICAL[name] and user.status in abilities.POWER_STATUSES[name]
        return abilities.STATUS_POWER if boosted else 1.0


@register("abilities", "stat-boost")
class StatBoost(Handler):
    """Hustle, Gorilla Tactics, Fur Coat: `args.stat` ×`args.boost` always."""

    def modify_stat(self, name, stat, weather, fighter):
        return abilities.STAT_BOOST[name] if stat == abilities.BOOSTED_STAT[name] else 1.0


@register("abilities", "hustle")
class Hustle(Handler):
    def accuracy_as_user(self, name, move):
        return abilities.HUSTLE_ACCURACY if move.physical else 1.0


@register("abilities", "choice-lock")
class ChoiceLock(Handler):
    """Gorilla Tactics: the holder repeats its first move, as a Choice item does."""

    def locks_move(self, name):
        return True


@register("abilities", "status-stat")
class StatusStat(Handler):
    """Quick Feet and Marvel Scale: `args.stat` ×1.5 while the holder has a status; Quick Feet ignores paralysis."""

    def modify_stat(self, name, stat, weather, fighter):
        if stat != abilities.STATUS_STAT_KEY[name] or fighter.status is None:
            return 1.0
        return abilities.STATUS_STAT * (2.0 if stat == "speed" and fighter.status == "paralysis" else 1.0)


@register("abilities", "solar-power")
class SolarPower(Handler):
    def modify_stat(self, name, stat, weather, fighter):
        return abilities.SOLAR_POWER_BOOST if stat == "special_attack" and weather == "sun" else 1.0

    def end_of_turn(self, name, fighter, side, turn, rng):
        if battle._weather_of(fighter) != "sun" or battle._chip_free(fighter):
            return None
        fighter.hp = max(0, fighter.hp - max(1, fighter.max_hp // abilities.SOLAR_POWER_CHIP))
        return battle.AbilityAct(turn, side, fighter.combatant.name, name, hp=fighter.hp_percent,
                                 fainted=fighter.hp == 0)


@register("abilities", "defeatist")
class Defeatist(Handler):
    def modify_stat(self, name, stat, weather, fighter):
        weak = stat in ("attack", "special_attack") and fighter.hp * 2 <= fighter.max_hp
        return 0.5 if weak else 1.0


@register("abilities", "slow-start")
class SlowStart(Handler):
    def modify_stat(self, name, stat, weather, fighter):
        slow = (stat in ("attack", "speed") and fighter.arena is not None
                and fighter.arena.turn - fighter.entered_turn < abilities.SLOW_START_TURNS)
        return 0.5 if slow else 1.0


@register("abilities", "damage-dealt")
class DamageDealt(Handler):
    """Tinted Lens on a resisted hit, Neuroforce on a super-effective one, Sniper on a critical hit."""

    def modify_damage_dealt(self, name, move, multiplier, critical, user, target):
        applies = {"resisted": 0 < multiplier < 1, "super": multiplier > 1, "critical": critical}
        return abilities.DEALT_MULTIPLIER[name] if applies[abilities.DEALT_WHEN[name]] else 1.0


@register("abilities", "super-taken")
class SuperTaken(Handler):
    """Filter, Solid Rock, Prism Armor: a super-effective hit does 3/4."""

    def modify_damage_taken(self, name, move, multiplier, holder, user):
        return abilities.SUPER_TAKEN if multiplier > 1 else 1.0


@register("abilities", "full-hp-taken")
class FullHPTaken(Handler):
    """Multiscale, Shadow Shield: half damage at full HP."""

    def modify_damage_taken(self, name, move, multiplier, holder, user):
        return 0.5 if holder.hp == holder.max_hp else 1.0

    def lessens_hit(self, name, holder):
        return holder.hp == holder.max_hp


@register("abilities", "taken")
class Taken(Handler):
    """Fluffy, Ice Scales, Heatproof, Aura Guard, Purifying Salt, Water Bubble, Punk Rock: `args.taken` maps a move
    type, "special", "contact" or a move flag to the share of its damage the holder takes."""

    def modify_damage_taken(self, name, move, multiplier, holder, user):
        scale = 1.0
        for kind, factor in abilities.TAKEN[name].items():
            if kind == "contact":
                hit = battle.makes_contact(user, move)
            else:
                hit = move.type == kind or move.flagged(kind) or kind == "special" and not move.physical
            scale *= factor if hit else 1.0
        return scale


@register("abilities", "heatproof")
class Heatproof(Handler):
    def modify_status_damage(self, name, damage, status):
        return max(1, damage // 2) if status == "burn" else damage


@register("abilities", "aura")
class Aura(Handler):
    """Dark Aura and Fairy Aura: moves of `args.type` from either side hit harder, or softer under Aura Break. When
    both Pokémon share the aura the user's counts."""

    def modify_power(self, name, move, power, user, target, weather):
        return aura(name, move, user)

    def modify_foe_power(self, name, move, holder):
        foe = holder.arena.foe_of(holder) if holder.arena is not None else None
        if foe is not None and foe.ability == name:
            return 1.0
        return aura(name, move, holder)


@register("abilities", "aura-break")
class AuraBreak(Handler):
    def breaks_aura(self, name):
        return True


@register("abilities", "ruin")
class Ruin(Handler):
    """Beads, Sword, Tablets and Vessel of Ruin: the foe's `args.stat` ×3/4, unless it has the same ability."""

    def modify_foe_stat(self, name, stat, foe):
        return abilities.RUIN if stat == abilities.RUINED_STAT[name] and foe.ability != name else 1.0


@register("abilities", "parental-bond")
class ParentalBond(Handler):
    """A single-hit attack hits twice; the second hit has a quarter of the power."""

    def hit_count(self, name, move):
        return 2 if move.damaging and move.max_hits <= 1 else None

    def expected_hits(self, name, move):
        return 1 + abilities.PARENTAL_BOND_SECOND if move.damaging and move.max_hits <= 1 else move.expected_hits

    def extra_hit_power(self, name):
        return abilities.PARENTAL_BOND_SECOND


@register("abilities", "skill-link")
class SkillLink(Handler):
    """Every hit of a multi-hit move lands, and its later hits draw no accuracy (Triple Kick)."""

    def hit_count(self, name, move):
        return move.max_hits if move.max_hits > 1 else None

    def expected_hits(self, name, move):
        return move.max_hits

    def skips_hit_rolls(self, name):
        return True


@register("abilities", "weight")
class Weight(Handler):
    """Heavy Metal doubles the holder's weight, Light Metal halves it."""

    def modify_weight(self, name):
        return abilities.WEIGHT_MULTIPLIER[name]


@register("abilities", "rock-head")
class RockHead(Handler):
    def blocks_recoil(self, name):
        return True


@register("abilities", "guard-piercing")
class GuardPiercing(Handler):
    """Unseen Fist and Piercing Drill: a contact move passes the target's Protect."""

    def breaks_guard(self, name, move, user):
        return battle.makes_contact(user, move)


def aura(name: str, move, user) -> float:
    if move.type != abilities.AURA_TYPE[name]:
        return 1.0
    foe = user.arena.foe_of(user) if user.arena is not None else None
    broken = any(fighter is not None and fighter.hp > 0 and hooks.ability(fighter, "breaks_aura", default=False)
                 for fighter in (user, foe))
    return abilities.AURA_BROKEN if broken else abilities.AURA_POWER


def sheer_forced_by(user, move) -> bool:
    """The user's Sheer Force boosts the move, which also stops the user's answers to it (Showdown's
    AfterMoveSecondarySelf: Life Orb, Shell Bell, Throat Spray)."""
    return hooks.ability(user, "secondary_chance", move, default=1.0) == 0


def sheer_forced(move) -> bool:
    if not move.damaging:
        return False
    raises_user = move.stat_on_user and any(stages > 0 for _, stages in move.stat_changes)
    on_target = not move.stat_on_user and move.stat_chance > 0
    return move.ailment_chance > 0 or raises_user or on_target or meta(move, "flinch_chance") > 0


def data_type(move) -> str | None:
    entry = battle_data.table("moves").get(str(move.id))
    return entry.get("type") if entry else None
