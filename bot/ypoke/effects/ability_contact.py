"""Abilities that answer a hit: ones that hurt, slow, afflict or curse the foe that hit their holder (most only on
contact), take its item or swap abilities with it, and ones that add an effect to their holder's own hits. `holder`
and `user` are `battle._Fighter`s; a `hit` is a `battle.Hit`."""

from ypoke import abilities, battle
from ypoke.effects import Handler, hooks, register
from ypoke.effects.changers import FIXED_ABILITIES, reshape, shielded
from ypoke.effects.item_moves import hold, yields
from ypoke.effects.secondary import meta
from ypoke.effects.volatiles import PERISH_COUNT, Disable
from ypoke.move_power import holds_item

PERISH = "perish-song"


@register("abilities", "effect-spore")
class EffectSpore(Handler):
    """A contact move may put its user to sleep, paralyze or poison it; Grass types and powder-proof users are safe."""

    def on_contact(self, name, side, move, user, holder, rng):
        if not battle.makes_contact(user, move) or "grass" in user.combatant.types or _blocks(user, abilities.POWDER_FLAG):
            return None
        if hooks.item(user, "powder_proof", default=False):
            return None
        draw = rng.random()
        ailment = next((ailment for ailment, bound in abilities.EFFECT_SPORE if draw < bound), None)
        return _afflicted(ailment, user, side, rng, holder) if ailment else None


@register("abilities", "contact-chip")
class ContactChip(Handler):
    """Rough Skin, Iron Barbs: each contact hit takes 1/`args.share` of its user's max HP."""

    def on_contact_hit(self, name, user):
        return max(1, user.max_hp // abilities.CONTACT_CHIP_SHARE[name])


@register("abilities", "aftermath")
class Aftermath(Handler):
    """A contact move that knocks the holder out takes 1/`args.share` of its user's max HP, unless Damp is out."""

    def on_fainted_by(self, name, holder, user, move, lost):
        if user.hp == 0 or not battle.makes_contact(user, move) or battle._chip_free(user) or _damped(holder, user):
            return None
        return _hurt(name, holder, user, max(1, user.max_hp // abilities.AFTERMATH_SHARE[name]))


@register("abilities", "innards-out")
class InnardsOut(Handler):
    """A move that knocks the holder out takes the HP the holder had left from its user."""

    def on_fainted_by(self, name, holder, user, move, lost):
        return None if user.hp == 0 or battle._chip_free(user) else _hurt(name, holder, user, lost)


@register("abilities", "cursed-body")
class CursedBody(Handler):
    """A damaging move that hits the holder may be disabled for its user, as the move Disable does."""

    def after_hit(self, name, hit):
        user, holder = hit.user, hit.target
        index = next((i for i, known in enumerate(user.combatant.moves) if known.name == hit.move.name), None)
        if (hit.shielded or user.hp == 0 or index is None or "disable" in user.volatiles
                or hit.rng.random() >= abilities.CURSED_BODY_CHANCE or _blocks(user, "disable")):
            return None
        user.volatiles["disable"], user.memory["disable"] = Disable.turns, index
        return _act(name, holder, effect="disable", detail=hit.move.name, foe=user.combatant.name)


@register("abilities", "perish-body")
class PerishBody(Handler):
    """A contact move starts Perish Song's count on its user and the holder, unless its user has one already."""

    def after_hit(self, name, hit):
        user, holder = hit.user, hit.target
        if hit.shielded or not hit.contact or user.hp == 0 or PERISH in user.volatiles:
            return None
        for fighter in (user, holder):
            if fighter.hp > 0:
                fighter.volatiles.setdefault(PERISH, PERISH_COUNT)
        return _act(name, holder, effect="perish", foe=user.combatant.name)


@register("abilities", "ability-spread")
class AbilitySpread(Handler):
    """Mummy, Lingering Aroma: a contact move's user gets the holder's ability."""

    def after_hit(self, name, hit):
        user = hit.user
        if (hit.shielded or not hit.contact or user.hp == 0 or user.combatant.ability == name
                or user.combatant.ability in FIXED_ABILITIES or shielded(user)):
            return None
        reshape(user, ability=name)
        return _act(name, hit.target, effect="spread", foe=user.combatant.name)


@register("abilities", "wandering-spirit")
class WanderingSpirit(Handler):
    """A contact move's user swaps abilities with the holder."""

    def after_hit(self, name, hit):
        user, holder = hit.user, hit.target
        theirs = user.combatant.ability
        if hit.shielded or not hit.contact or 0 in (user.hp, holder.hp) or theirs == name or theirs in FIXED_ABILITIES:
            return None
        if shielded(user) or shielded(holder):
            return None
        reshape(user, ability=name)
        reshape(holder, ability=theirs)
        return _act(name, holder, effect="swap", foe=user.combatant.name)


@register("abilities", "pickpocket")
class Pickpocket(Handler):
    """An empty-handed holder takes the held item of a contact move's user."""

    def after_hit(self, name, hit):
        if hit.shielded or not hit.contact:
            return None
        return _stolen(name, hit.target, hit.user)


@register("abilities", "magician")
class Magician(Handler):
    """An empty-handed holder takes the held item of the foe its damaging move hit."""

    def after_hit_as_user(self, name, hit):
        return None if hit.shielded else _stolen(name, hit.user, hit.target)


@register("abilities", "hit-ailment")
class HitAilment(Handler):
    """Poison Touch, Toxic Chain: the holder's damaging move (only a contact one with `args.contact`) may give its
    target `args.ailment`."""

    def after_hit_as_user(self, name, hit):
        user, target = hit.user, hit.target
        if (hit.shielded or target.hp == 0 or abilities.HIT_AILMENT_CONTACT[name] and not hit.contact
                or hooks.ability(target, "blocks_secondary", default=False)
                or hit.rng.random() >= abilities.CONTACT_CHANCE):
            return None
        change = _afflicted(abilities.HIT_AILMENT[name], target, target.side, hit.rng, user)
        return _act(name, user, changes=(change,)) if change else None


@register("abilities", "stench")
class Stench(Handler):
    """Each hit of the holder's damaging move that cannot flinch on its own may flinch a target that has not moved."""

    def after_hit_as_user(self, name, hit):
        target, move = hit.target, hit.move
        if hit.shielded or target.hp == 0 or target.acted or meta(move, "flinch_chance") > 0:
            return
        chance = abilities.STENCH_CHANCE * battle._chance_scale(move, hit.user, target)
        if any(hit.rng.random() < chance for _ in range(hit.hits)) and not battle._blocks_ailment(target, "flinch"):
            target.volatiles["flinch"] = True


@register("abilities", "poison-puppeteer")
class PoisonPuppeteer(Handler):
    """A foe the holder poisons gets confused too."""

    def after_inflicting(self, name, ailment, holder, target, side, rng):
        if ailment not in abilities.POISONS or target.hp == 0 or target is holder:
            return None
        change = _afflicted("confusion", target, side, rng)
        return _act(name, holder, changes=(change,)) if change else None


@register("abilities", "spicy-spray")
class SpicySpray(Handler):
    """A damaging move that hits the holder burns its user."""

    def after_hit(self, name, hit):
        user, holder = hit.user, hit.target
        if hit.shielded or user.hp == 0:
            return None
        change = _afflicted("burn", user, hit.side, hit.rng, holder)
        return _act(name, holder, changes=(change,)) if change else None


def _afflicted(ailment: str, fighter, side: int, rng, by=None):
    """Gives `fighter` the ailment from a foe's ability when it can take it; the change, or None."""
    if not battle._open_to(ailment, fighter, True, by) or battle._blocks_ailment(fighter, ailment):
        return None
    return battle._inflict(ailment, fighter, side, rng, by)


def _blocks(fighter, kind: str) -> bool:
    """The fighter's ability keeps moves of `kind` (a flag or an effect key) off it (Overcoat, Aroma Veil)."""
    return kind in abilities.BLOCKED_MOVES.get(fighter.ability, ())


def _damped(*fighters) -> bool:
    return any(hooks.ability(fighter, "damps", default=False) for fighter in fighters)


def _hurt(name, holder, user, damage: int):
    user.hp = max(0, user.hp - damage)
    return _act(name, holder, foe=user.combatant.name, foe_hp=user.hp_percent)


def _stolen(name, taker, giver):
    """The taker, holding nothing, takes the giver's item; the `AbilityAct`, or None when it cannot."""
    item = giver.item
    if taker.hp == 0 or holds_item(taker) or item is None or not yields(giver):
        return None
    hold(giver, None)
    hold(taker, item)
    return _act(name, taker, effect="stole", detail=item, foe=giver.combatant.name)


def _act(name, holder, changes=(), **details):
    turn = holder.arena.turn if holder.arena is not None else 0
    return battle.AbilityAct(turn, holder.side, holder.combatant.name, name, changes=tuple(changes), **details)
