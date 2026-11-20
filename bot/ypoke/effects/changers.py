"""Status moves that change a Pokémon's type or ability until it switches out (`battle._Fighter.leave` brings back
what it came in with). `user` and `foe` are `battle._Fighter`s."""

from dataclasses import replace

from ypoke import battle_data
from ypoke import field_states as fs
from ypoke.effects import hooks, loaded, register
from ypoke.effects.conditions import reaches
from ypoke.effects.moves import StatusMove
from ypoke.effects.protection import last_move
from ypoke.move_effects import POWDER_MOVES
from ypoke.type_chart import TYPE_NAMES_KO, effectiveness

ADDED_TYPE = "added-type"
# Abilities no move copies, swaps, replaces or suppresses: form changers and ones that copy or hide themselves.
FIXED_ABILITIES = frozenset({
    "as-one-glastrier", "as-one-spectrier", "battle-bond", "comatose", "commander", "disguise", "flower-gift",
    "forecast", "gulp-missile", "hunger-switch", "ice-face", "illusion", "imposter", "multitype", "neutralizing-gas",
    "poison-puppeteer", "power-construct", "power-of-alchemy", "protosynthesis", "quark-drive", "receiver",
    "rks-system", "schooling", "shields-down", "stance-change", "tera-shell", "tera-shift", "teraform-zero", "trace",
    "wonder-guard", "zen-mode", "zero-to-hero",
})


@register("moves", "conversion", "conversion-2", "camouflage", "reflect-type")
class OwnType(StatusMove):
    """The user's type becomes that of its first move (Conversion), the type that best resists the foe's last move
    (Conversion 2), the terrain's or Normal (Camouflage), or the foe's (Reflect Type). Picked when the foe's attacks
    would hit the new type less hard."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        types = self._types(user, foe, arena)
        return types is not None and exposure(types, foe) < exposure(user.combatant.types, foe)

    def _apply(self, move, user, foe, side, turn, arena, rng):
        types = self._types(user, foe, arena)
        if types is None:
            return "", ()
        reshape(user, types=types)
        return self.key, ()

    def _types(self, user, foe, arena) -> tuple[str, ...] | None:
        """The user's new types, None when the move fails."""
        if user.combatant.tera:
            return None
        if self.key == "conversion":
            kind = user.combatant.moves[0].type
            types = (kind,) if kind else None
        elif self.key == "conversion-2":
            types = resisting(last_move(foe), user, foe)
        elif self.key == "camouflage":
            types = (fs.TERRAIN_TYPES.get(arena.terrain, "normal"),)
        else:
            types = foe.combatant.types
        return None if types == user.combatant.types else types


def resisting(last, user, foe) -> tuple[str, ...] | None:
    if last is None or not last.type:
        return None
    kinds = [kind for kind in TYPE_NAMES_KO if effectiveness(last.type, (kind,)) < 1]
    return min(((kind,) for kind in kinds), key=lambda types: (exposure(types, foe), types), default=None)


def exposure(types: tuple[str, ...], foe) -> float:
    """How hard the foe's best-typed attack hits `types`."""
    return max((effectiveness(known.type, types) for known, pp in zip(foe.combatant.moves, foe.pp)
                if known.damaging and known.type and pp > 0), default=1.0)


def reshape(fighter, **fields) -> None:
    fighter.entered_as = fighter.entered_as or fighter.combatant
    fighter.combatant = replace(fighter.combatant, **fields)


@register("moves", "soak", "magic-powder", "trick-or-treat", "forests-curse")
class FoeType(StatusMove):
    """The foe becomes pure Water (Soak) or Psychic (Magic Powder, a powder Grass types ignore), or gains Ghost
    (Trick-or-Treat) or Grass (Forest's Curse) in place of a type one of those added before. Picked when the user's
    attacks would hit the new type harder."""

    hits_foe = True
    BECOMES = {"soak": "water", "magic-powder": "psychic"}
    ADDS = {"trick-or-treat": "ghost", "forests-curse": "grass"}

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        types = self._types(move, foe)
        return (types is not None and reaches(move, user, foe)
                and offense(user, types) > offense(user, foe.combatant.types))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        types = self._types(move, foe)
        if types is None:
            return "", ()
        reshape(foe, types=types)
        if self.key in self.ADDS:
            foe.memory[ADDED_TYPE] = self.ADDS[self.key]
        return self.key, ()

    def _types(self, move, foe) -> tuple[str, ...] | None:
        types = foe.combatant.types
        if foe.combatant.tera or move.id in POWDER_MOVES and "grass" in types:
            return None
        if self.key in self.BECOMES:
            changed = (self.BECOMES[self.key],)
        else:
            added = self.ADDS[self.key]
            changed = (*(kind for kind in types if kind != foe.memory.get(ADDED_TYPE)), added)
            changed = types if added in types else changed
        return None if changed == types else changed


def offense(user, types: tuple[str, ...]) -> float:
    """How hard the user's best-typed attack hits `types`."""
    return max((effectiveness(known.type, types) for known, pp in zip(user.combatant.moves, user.pp)
                if known.damaging and known.type and pp > 0), default=1.0)


@register("moves", "role-play", "doodle", "skill-swap", "entrainment", "simple-beam", "worry-seed", "gastro-acid")
class Ability(StatusMove):
    """The user copies the foe's ability (Role Play, Doodle), the two swap (Skill Swap), the foe gets the user's
    (Entrainment), Simple (Simple Beam) or Insomnia, which wakes it (Worry Seed), or loses its own (Gastro Acid).
    None of them moves a `FIXED_ABILITIES` one. Picked when the foe's ability does something in battle; a move that
    hands the user the foe's or the foe the user's only when the user's own does nothing."""

    GIVES = {"simple-beam": "simple", "worry-seed": "insomnia", "gastro-acid": None}

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        if self._after(user, foe) is None or self.targets_foe(move) and not reaches(move, user, foe):
            return False
        if self.key == "worry-seed" and foe.status == "sleep":
            return False
        return works(foe.ability) and (self.key in self.GIVES or not works(user.ability))

    def targets_foe(self, move):
        return self.key not in ("role-play", "doodle")

    def _apply(self, move, user, foe, side, turn, arena, rng):
        after = self._after(user, foe)
        if after is None:
            return "", ()
        mine, theirs = after
        if mine != user.ability:
            reshape(user, ability=mine)
        if theirs != foe.ability:
            reshape(foe, ability=theirs)
        if theirs == "insomnia" and foe.status == "sleep":
            foe.status, foe.sleep_left = None, 0
        return self.key, ()

    def _after(self, user, foe) -> tuple[str | None, str | None] | None:
        """The user's and the foe's abilities after the move, None when it fails."""
        if foe.ability in FIXED_ABILITIES or shielded(foe) and self.targets_foe(None):
            return None
        if self.key in self.GIVES:
            given = self.GIVES[self.key]
            return None if foe.ability == given else (user.ability, given)
        if user.ability in FIXED_ABILITIES or user.ability == foe.ability:
            return None
        if shielded(user) and self.key != "entrainment":
            return None
        if self.key == "skill-swap":
            return foe.ability, user.ability
        if self.key == "entrainment":
            return (user.ability, user.ability) if user.ability else None
        return (foe.ability, foe.ability) if foe.ability else None


def works(ability: str | None) -> bool:
    """Whether the battle runs the ability: an ability it leaves `todo` or inert does nothing."""
    entry = battle_data.table("abilities").get(ability) if ability else None
    return entry is not None and any(key in loaded()["abilities"] for key in battle_data.keys(entry))


def shielded(fighter) -> bool:
    """Whether the fighter's item keeps its ability from being changed or lost (Ability Shield)."""
    return bool(hooks.item(fighter, "shields_ability", default=False))
