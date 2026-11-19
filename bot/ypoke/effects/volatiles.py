"""Status moves that leave a state on one Pokémon (`fighter.volatiles[key]`, gone when it switches out) or, for the
Sports and Ion Deluge, on the whole field (`arena.rooms`). A timed state holds its turns left and wears off at the
end of the turn it reaches 0; a move it tracks sits in `fighter.memory[key]`. `user`, `foe` and `fighter` are
`battle._Fighter`s."""

from ypoke import battle
from ypoke.effects import hooks, register
from ypoke.effects.conditions import reaches
from ypoke.effects.healing import foe_hit
from ypoke.effects.moves import StatusMove
from ypoke.effects.protection import aimed, attacking, last_move
from ypoke.effects.stats import Stages, guarded, shift_all
from ypoke.move_effects import POWDER_MOVES
from ypoke.type_chart import effectiveness

LEECH_SHARE = 8
DAMAGE_SHARE = 4
PERISH_COUNT = 4
SPITE_PP = 4
FOCUS_STAGES = 2
LOW_ACCURACY = 70
SPORT_POWER = 1 / 3
TAR_WEAKNESS = 2.0
OCTOLOCK_DROP = (("defense", -1), ("special_defense", -1))
TAR_DROP = (("speed", -1),)


class State(StatusMove):
    """Puts `key` on the foe (`hits_foe`) or the user for `turns` (None: until it switches out); fails while it is
    there or `_ready` says no. `_worth` is the chooser's rule on top of that."""

    turns: int | None = None
    hits_foe = True
    shown_end = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        target = foe if self.hits_foe else user
        return (self.key not in target.volatiles and (not self.hits_foe or reaches(move, user, foe))
                and self._ready(move, user, foe, arena) and self._worth(move, user, foe, team, foes, weather))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        target = foe if self.hits_foe else user
        if self.key in target.volatiles or not self._ready(move, user, foe, arena):
            return "", ()
        target.volatiles[self.key] = self._turns(user, foe)
        return self.key, self._start(move, user, foe, side, turn)

    def _ready(self, move, user, foe, arena) -> bool:
        return True

    def _worth(self, move, user, foe, team, foes, weather) -> bool:
        return True

    def _turns(self, user, foe):
        return True if self.turns is None else self.turns

    def _start(self, move, user, foe, side, turn) -> tuple:
        return ()

    def volatile_end(self, name, fighter, side, turn, rng):
        if fighter.volatiles[name] is True:
            return self._tick(name, fighter, side, turn)
        fighter.volatiles[name] -= 1
        if fighter.volatiles[name] > 0:
            return self._tick(name, fighter, side, turn)
        del fighter.volatiles[name]
        fighter.memory.pop(name, None)
        return battle.VolatileEnd(turn, side, fighter.combatant.name, name) if self.shown_end else None

    def _tick(self, name, fighter, side, turn):
        return None


def faster(user, foe, weather) -> bool:
    return user.stat("speed", weather) > foe.stat("speed", weather)


def hurt(fighter, share: int) -> int:
    lost = min(fighter.hp, due(fighter, share))
    fighter.hp -= lost
    return lost


def due(fighter, share: int) -> int:
    return 0 if battle._chip_free(fighter) else max(1, fighter.max_hp // share)


def ticked(fighter, side: int, turn: int, kind: str, **fields):
    return battle.VolatileTick(turn, side, fighter.combatant.name, kind, fighter.hp_percent, fighter.hp == 0, **fields)


@register("moves", "leech-seed")
class LeechSeed(State):
    """The foe loses 1/8 of its max HP at the end of each turn and the Pokémon facing it gets that back; Grass types
    are immune. Picked on a foe above half HP."""

    def _ready(self, move, user, foe, arena):
        return "grass" not in foe.combatant.types

    def _worth(self, move, user, foe, team, foes, weather):
        return foe.hp * 2 > foe.max_hp

    def tick_due(self, name, fighter):
        return due(fighter, LEECH_SHARE)

    def _tick(self, name, fighter, side, turn):
        drained = hurt(fighter, LEECH_SHARE)
        seeded = ticked(fighter, side, turn, name)
        healer = fighter.arena.foe_of(fighter) if fighter.arena is not None else None
        if healer is not None and healer.hp > 0 and drained and hooks.ability(fighter, "inverts_drain", default=False):
            healer.hp = max(0, healer.hp - (0 if battle._chip_free(healer) else drained))
            return seeded, battle.AbilityAct(turn, side, fighter.combatant.name, fighter.ability,
                                             foe=healer.combatant.name, foe_hp=healer.hp_percent,
                                             foe_fainted=healer.hp == 0)
        if healer is None or healer.hp == 0 or healer.hp == healer.max_hp:
            return seeded
        healer.hp = min(healer.max_hp, healer.hp + drained)
        return seeded, ticked(healer, 1 - side, turn, "leech-seed-heal")


@register("moves", "nightmare")
class Nightmare(State):
    """A sleeping foe loses 1/4 of its max HP at the end of each turn until it wakes. Picked on a foe that sleeps
    on past this turn."""

    def _ready(self, move, user, foe, arena):
        return battle._status_of(foe) == "sleep"

    def _worth(self, move, user, foe, team, foes, weather):
        return foe.sleep_left > 0 or foe.status is None

    def _tick(self, name, fighter, side, turn):
        if battle._status_of(fighter) != "sleep":
            del fighter.volatiles[name]
            return None
        hurt(fighter, DAMAGE_SHARE)
        return ticked(fighter, side, turn, name)


@register("moves", "curse")
class Curse(Stages):
    """A Ghost type pays half its max HP and the foe loses 1/4 of its max HP at the end of each turn; any other type
    trades a Speed stage for Attack and Defense. A Ghost curses a foe above half HP while it has more than 3/4 of
    its own HP."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        if "ghost" not in user.combatant.types:
            return super().wanted(move, team, foes, side, arena, weather)
        return self.key not in foe.volatiles and user.hp * 4 > user.max_hp * 3 and foe.hp * 2 > foe.max_hp

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if "ghost" not in user.combatant.types:
            return super()._apply(move, user, foe, side, turn, arena, rng)
        if self.key in foe.volatiles:
            return "", ()
        user.hp = max(0, user.hp - user.max_hp // 2)
        foe.volatiles[self.key] = True
        return self.key, ()

    def volatile_end(self, name, fighter, side, turn, rng):
        hurt(fighter, DAMAGE_SHARE)
        return ticked(fighter, side, turn, name)


@register("moves", "destiny-bond", "grudge")
class Bond(State):
    """Until the user's next move, a foe's move that knocks it out costs that foe too: it faints (Destiny Bond) or
    the move loses all its PP (Grudge). It fails right after it worked. Picked by a faster user the foe's best hit
    would knock out."""

    hits_foe = False

    def _ready(self, move, user, foe, arena):
        return user.memory.get(self.key) != arena.turn - 1

    def _worth(self, move, user, foe, team, foes, weather):
        return faster(user, foe, weather) and foe_hit(user, foe, weather) >= user.hp

    def _turns(self, user, foe):
        return 1 if foe.acted else 2

    def _start(self, move, user, foe, side, turn):
        user.memory[self.key] = turn
        return ()

    def volatile_end(self, name, fighter, side, turn, rng):
        fighter.volatiles[name] -= 1
        if fighter.volatiles[name] == 0:
            del fighter.volatiles[name]
        return None

    def on_knocked_out(self, name, attacker, move, turn, side):
        if name == "destiny-bond":
            attacker.hp = 0
        else:
            attacker.pp = [0 if known.name == move.name else pp for known, pp in zip(attacker.combatant.moves, attacker.pp)]
        holder = attacker.arena.foe_of(attacker) if attacker.arena is not None else None
        if holder is not None:
            attacker.arena.log.append(battle.VolatileEnd(turn, 1 - side, holder.combatant.name, name))


@register("moves", "perish-song")
class PerishSong(StatusMove):
    """Every Pokémon out that has no count yet faints at the end of the third turn after this one. Picked when the
    user's team has more members standing than the foe's."""

    def wanted(self, move, team, foes, side, arena, weather):
        return self.key not in foes.active.volatiles and team.standing()[0] > foes.standing()[0]

    def _apply(self, move, user, foe, side, turn, arena, rng):
        counted = [fighter for fighter in (user, foe) if self.key not in fighter.volatiles]
        for fighter in counted:
            fighter.volatiles[self.key] = PERISH_COUNT
        return (self.key if counted else ""), ()

    def volatile_end(self, name, fighter, side, turn, rng):
        fighter.volatiles[name] -= 1
        if fighter.volatiles[name] == 0:
            fighter.hp = 0
        return ticked(fighter, side, turn, name, count=fighter.volatiles[name])


@register("moves", "taunt")
class Taunt(State):
    """For three turns (four when the foe has moved this turn) the foe cannot use status moves. Picked on a foe with
    a status move left to use."""

    turns = 3

    def _worth(self, move, user, foe, team, foes, weather):
        return any(not attacking(known) and pp > 0 for known, pp in zip(foe.combatant.moves, foe.pp))

    def _turns(self, user, foe):
        return self.turns + foe.acted

    def bans_move(self, name, move, fighter):
        return name if not attacking(move) else None


@register("moves", "encore")
class Encore(State):
    """For three turns the foe repeats the move it used last; fails when it used none or that move has no PP left.
    Picked when that move is a status move or a weak hit on the user."""

    turns = 3

    def _ready(self, move, user, foe, arena):
        return foe.last_used is not None and foe.pp[foe.last_used] > 0

    def _worth(self, move, user, foe, team, foes, weather):
        last = last_move(foe)
        return not attacking(last) or effectiveness(last.type, user.combatant.types) < 1

    def _start(self, move, user, foe, side, turn):
        foe.memory[self.key] = foe.last_used
        return ()

    def forces_move(self, name, attacker):
        index = attacker.memory.get(name)
        return index if index is not None and attacker.pp[index] > 0 else None


@register("moves", "disable")
class Disable(State):
    """For four turns the foe cannot use the move it used last. Picked when that move hits the user super
    effectively."""

    turns = 4

    def _ready(self, move, user, foe, arena):
        return foe.last_used is not None

    def _worth(self, move, user, foe, team, foes, weather):
        last = last_move(foe)
        return attacking(last) and effectiveness(last.type, user.combatant.types) > 1

    def _start(self, move, user, foe, side, turn):
        foe.memory[self.key] = foe.last_used
        return ()

    def bans_move(self, name, move, fighter):
        index = fighter.memory.get(name)
        return name if index is not None and fighter.combatant.moves[index].name == move.name else None


@register("moves", "torment")
class Torment(State):
    """The foe cannot use the same move twice in a row. Picked on a foe with one attack left to use."""

    def _worth(self, move, user, foe, team, foes, weather):
        return sum(attacking(known) and pp > 0 for known, pp in zip(foe.combatant.moves, foe.pp)) == 1

    def bans_move(self, name, move, fighter):
        last = last_move(fighter)
        return name if last is not None and last.name == move.name else None


@register("moves", "spite")
class Spite(StatusMove):
    """The foe's last move loses 4 PP; fails when it has none left. Picked when that empties it."""

    hits_foe = True

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return reaches(move, user, foe) and foe.last_used is not None and 0 < foe.pp[foe.last_used] <= SPITE_PP

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if foe.last_used is None or foe.pp[foe.last_used] == 0:
            return "", ()
        foe.pp[foe.last_used] = max(0, foe.pp[foe.last_used] - SPITE_PP)
        return self.key, ()


@register("moves", "heal-block")
class HealBlock(State):
    """For five turns the foe cannot use healing moves. Picked on a foe that has one."""

    turns = 5

    def _worth(self, move, user, foe, team, foes, weather):
        return any(hooks.move(known, "heals", default=False) for known in foe.combatant.moves)

    def bans_move(self, name, move, fighter):
        return name if hooks.move(move, "heals", default=False) else None


@register("moves", "embargo")
class Embargo(State):
    """For five turns the foe's held item does nothing. Picked on a foe that holds one."""

    turns = 5

    def _worth(self, move, user, foe, team, foes, weather):
        return foe.item is not None

    def suppresses_items(self, name):
        return True


@register("moves", "foresight", "miracle-eye")
class Foresight(State):
    """Until the foe switches out, its raised evasion stops counting and Normal and Fighting moves hit a Ghost type
    (Foresight, Odor Sleuth) or Psychic moves a Dark type (Miracle Eye). Picked when the user has such a move for a
    foe of that type, or the foe has raised its evasion."""

    EXPOSED = {"foresight": ("ghost", ("normal", "fighting")), "miracle-eye": ("dark", ("psychic",))}

    def _worth(self, move, user, foe, team, foes, weather):
        kind, types = self.EXPOSED[self.key]
        return foe.stages["evasion"] > 0 or kind in foe.combatant.types and any(
            known.damaging and known.type in types for known in user.combatant.moves)

    def exposes(self, name, move_type):
        kind, types = self.EXPOSED[name]
        return kind if move_type is None or move_type in types else None


@register("moves", "lock-on", "telekinesis")
class LockOn(State):
    """The user's moves hit the foe without an accuracy draw until the end of the next turn (Lock-On, Mind Reader),
    or for three turns while the foe floats over Ground moves (Telekinesis). Picked when the user has an attack of
    70% accuracy or less (and, for Telekinesis, no Ground attack)."""

    TURNS = {"lock-on": 2, "telekinesis": 3}

    def _ready(self, move, user, foe, arena):
        return self.key == "lock-on" or not any(battle._field(foe, "grounds"))

    def _worth(self, move, user, foe, team, foes, weather):
        shaky = any(known.damaging and known.accuracy is not None and known.accuracy <= LOW_ACCURACY
                    for known in user.combatant.moves)
        return shaky and (self.key == "lock-on" or not any(known.damaging and known.type == "ground"
                                                           for known in user.combatant.moves))

    def _turns(self, user, foe):
        return self.TURNS[self.key]

    def sure_hit(self, name, attacker):
        return True

    def lifts(self, name):
        return True if name == "telekinesis" else None


@register("moves", "magnet-rise")
class MagnetRise(State):
    """For five turns the user floats over Ground moves; fails while a state grounds it. Picked when the foe has a
    Ground attack that would hit the user."""

    turns = 5
    hits_foe = False

    def _ready(self, move, user, foe, arena):
        return not any(battle._field(user, "grounds"))

    def _worth(self, move, user, foe, team, foes, weather):
        return battle._grounded(user) and any(known.damaging and known.type == "ground"
                                              and effectiveness("ground", user.combatant.types) > 0
                                              for known in foe.combatant.moves)

    def lifts(self, name):
        return True


@register("moves", "imprison")
class Imprison(State):
    """Until the user switches out, the foe cannot use a move the user also knows. Picked when they share one."""

    hits_foe = False

    def _worth(self, move, user, foe, team, foes, weather):
        return bool({known.name for known in user.combatant.moves} & {known.name for known in foe.combatant.moves})

    def bans_foe_move(self, name, move, fighter):
        holder = fighter.arena.foe_of(fighter) if fighter.arena is not None else None
        return name if holder is not None and any(known.name == move.name for known in holder.combatant.moves) else None


@register("moves", "electrify", "powder")
class TurnState(State):
    """For the rest of the turn the foe's move turns Electric (Electrify), or a Fire move it uses explodes and costs
    it 1/4 of its max HP (Powder; Grass types are immune). Fails once the foe has moved. Picked by a faster user
    when the foe's last move was an attack that Electric would serve the user better against, or a Fire attack."""

    turns = 1
    shown_end = False

    def _ready(self, move, user, foe, arena):
        return not foe.acted and not (move.id in POWDER_MOVES and "grass" in foe.combatant.types)

    def _worth(self, move, user, foe, team, foes, weather):
        last = last_move(foe)
        if not faster(user, foe, weather) or last is None or not attacking(last):
            return False
        if self.key == "powder":
            return last.type == "fire"
        return effectiveness("electric", user.combatant.types) < effectiveness(last.type, user.combatant.types)

    def retypes_move(self, name, move):
        return "electric" if name == "electrify" else None

    def backfires(self, name, move, attacker):
        if name != "powder" or move.type != "fire":
            return None
        hurt(attacker, DAMAGE_SHARE)
        return name


@register("moves", "magic-coat", "snatch")
class Bounce(State):
    """For the rest of the turn the foe's status move aimed at the user bounces back (Magic Coat), or its status
    move on itself works for the user instead (Snatch). Picked when the foe's last move was such a move, the foe has
    used it since the user last waited for it, and the foe is awake."""

    turns = 1
    hits_foe = False

    def _worth(self, move, user, foe, team, foes, weather):
        last = last_move(foe)
        if (last is None or attacking(last) or foe.status in ("sleep", "freeze")
                or user.memory.get(self.key) == self._last_use(foe)):
            return False
        return aimed(last) if self.key == "magic-coat" else not aimed(last) and not last.weather

    def _start(self, move, user, foe, side, turn):
        if foe.last_used is not None:
            user.memory[self.key] = self._last_use(foe)
        return ()

    @staticmethod
    def _last_use(foe):
        return foe.last_used, foe.pp[foe.last_used]

    def volatile_end(self, name, fighter, side, turn, rng):
        del fighter.volatiles[name]
        return None

    def reflects(self, name, move):
        return name if name == "magic-coat" else None

    def snatches(self, name, move):
        return name if name == "snatch" else None


@register("moves", "octolock")
class Octolock(State):
    """The foe loses a Defense and a Special Defense stage at the end of each turn. Picked on a foe above half HP."""

    def _worth(self, move, user, foe, team, foes, weather):
        return foe.hp * 2 > foe.max_hp

    def _tick(self, name, fighter, side, turn):
        if not shift_all(fighter, side, OCTOLOCK_DROP):
            return None
        return ticked(fighter, side, turn, name)


@register("moves", "tar-shot")
class TarShot(State):
    """Lowers the foe's Speed and makes Fire moves hit it twice as hard; works when either lands. Picked when the
    user has a Fire attack."""

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        return (self.key not in foe.volatiles and reaches(move, user, foe)
                and any(known.damaging and known.type == "fire" for known in user.combatant.moves))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        slowed = shift_all(foe, 1 - side, TAR_DROP, guarded=guarded(user, foe), by=user)
        tarred = self.key not in foe.volatiles
        foe.volatiles[self.key] = True
        return (self.key if slowed or tarred else ""), slowed

    def weakens(self, name, move_type):
        return TAR_WEAKNESS if move_type == "fire" else None


@register("moves", "mud-sport", "water-sport", "ion-deluge")
class Sport(StatusMove):
    """A whole-field state: for five turns Electric (Mud Sport) or Fire (Water Sport) moves have 1/3 power; for the
    rest of the turn Normal moves turn Electric (Ion Deluge). Picked when the foe has such an attack and the user
    has none (Ion Deluge: by a faster user the foe's Normal attack would hit harder than an Electric one)."""

    TURNS = {"mud-sport": 5, "water-sport": 5, "ion-deluge": 1}
    WEAKENED = {"mud-sport": "electric", "water-sport": "fire"}

    def wanted(self, move, team, foes, side, arena, weather):
        user, foe = team.active, foes.active
        if self.key in arena.rooms:
            return False
        if self.key == "ion-deluge":
            last = last_move(foe)
            return (faster(user, foe, weather) and last is not None and attacking(last) and last.type == "normal"
                    and effectiveness("electric", user.combatant.types) < effectiveness("normal", user.combatant.types))
        kind = self.WEAKENED[self.key]
        return (any(known.damaging and known.type == kind for known in foe.combatant.moves)
                and not any(known.damaging and known.type == kind for known in user.combatant.moves))

    def _apply(self, move, user, foe, side, turn, arena, rng):
        if self.key in arena.rooms:
            return "", ()
        arena.rooms[self.key] = self.TURNS[self.key]
        return self.key, ()

    def field_power(self, name, move, attacker, defender):
        return SPORT_POWER if move.type == self.WEAKENED.get(name) else None

    def retypes_move(self, name, move):
        return "electric" if name == "ion-deluge" and move.type == "normal" else None


@register("moves", "focus-energy", "laser-focus")
class FocusEnergy(State):
    """The user's critical-hit stage rises by 2 until it switches out (Focus Energy), or its moves land critical hits
    until the end of the next turn (Laser Focus). Focus Energy is picked above half HP with an attack to use; Laser
    Focus when the foe has raised a defense."""

    hits_foe = False
    shown_end = False

    def _worth(self, move, user, foe, team, foes, weather):
        if self.key == "laser-focus":
            return foe.stages["defense"] > 0 or foe.stages["special_defense"] > 0
        return user.hp * 2 > user.max_hp and any(known.damaging for known in user.combatant.moves)

    def _turns(self, user, foe):
        return 2 if self.key == "laser-focus" else True

    def crit_stage(self, name):
        return len(battle.CRITICAL_CHANCES) - 1 if name == "laser-focus" else FOCUS_STAGES
