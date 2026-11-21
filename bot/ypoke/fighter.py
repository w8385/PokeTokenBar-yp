"""What one Pokémon brings into a battle and the state it keeps while fighting: its stats, HP, status, stages, held
item and its own states, with the team it fights in order and the field it stands on."""

import math
import random
from collections.abc import Sequence
from dataclasses import dataclass, field, replace
from typing import NamedTuple

from ypoke import abilities, items
from ypoke.battle_events import Event, FormShift
from ypoke.effects import hooks
from ypoke.move_effects import FLAGS, POWERLESS_ATTACKS, STATUS_MOVES

BURN_DAMAGE_FRACTION = 16
POISON_DAMAGE_FRACTION = 8
TOXIC_DAMAGE_FRACTION = 16
BATTLE_STATS = ("attack", "defense", "special_attack", "special_defense", "speed")
STAGES = (*BATTLE_STATS, "accuracy", "evasion")
STRONG_WINDS = "strong-winds"
WEATHER_MOVE_BOOST = {
    "sun": {"fire": 1.5, "water": 0.5},
    "rain": {"water": 1.5, "fire": 0.5},
}
SLEEP_TURNS = (1, 3)
MULTI_HIT_ODDS = {2: 35, 3: 35, 4: 15, 5: 15}
RESIDUAL_FRACTIONS = {"burn": BURN_DAMAGE_FRACTION, "poison": POISON_DAMAGE_FRACTION}
STATUS_EFFECTS = tuple(dict.fromkeys(STATUS_MOVES.values()))
_NATURE_ORDER = ("attack", "defense", "speed", "special_attack", "special_defense")
_NATURE_NAMES = (
    "hardy lonely brave adamant naughty bold docile relaxed impish lax timid hasty serious jolly naive "
    "modest mild quiet bashful rash calm gentle sassy careful quirky"
).split()
NATURE_MODIFIERS = {
    name: (_NATURE_ORDER[index // 5], _NATURE_ORDER[index % 5]) for index, name in enumerate(_NATURE_NAMES)
    if index // 5 != index % 5
}


@dataclass(frozen=True)
class BaseStats:
    hp: int
    attack: int
    defense: int
    special_attack: int
    special_defense: int
    speed: int


@dataclass(frozen=True)
class Move:
    name: str
    type: str | None
    power: int
    physical: bool
    accuracy: int | None = None
    pp: int = 20
    crit_stage: int = 0
    ailment: str | None = None
    ailment_chance: int = 0
    stat_changes: tuple[tuple[str, int], ...] = ()
    stat_on_user: bool = False
    stat_chance: int = 0
    priority: int = 0
    weather: str | None = None
    always_hits_in: tuple[str, ...] = ()
    drain: int = 0
    min_hits: int = 1
    max_hits: int = 1
    effect: str | None = None
    id: int = 0

    @property
    def expected_hits(self) -> float:
        if (self.min_hits, self.max_hits) == (2, 5):
            return sum(hits * odds for hits, odds in MULTI_HIT_ODDS.items()) / 100
        return (self.min_hits + self.max_hits) / 2

    @property
    def damaging(self) -> bool:
        """An attack, counting one whose effect sets its power or damage (Low Kick, Seismic Toss)."""
        return (bool(self.power or self.id in POWERLESS_ATTACKS) and not self.weather
                and self.effect not in STATUS_EFFECTS)

    def flagged(self, flag: str) -> bool:
        """A `data/battle/moves.json` flag of the move ("contact", "sound", "punch")."""
        return flag in FLAGS.get(self.id, ())


@dataclass(frozen=True)
class MegaForm:
    """What a Mega Evolution or an ability's form change (`Combatant.forms`, by `kind`) swaps in. `ability` is the
    narrated name, `ability_id` the PokéAPI slug that replaces the Pokémon's ability (one the battle does not know does
    nothing; None keeps the old one)."""

    types: tuple[str, ...]
    base: BaseStats
    ability: str | None = None
    ability_id: str | None = None
    form_id: int | None = None
    kind: str = "mega"


@dataclass(frozen=True)
class Combatant:
    name: str
    level: int
    types: tuple[str, ...]
    base: BaseStats
    ivs: BaseStats
    shiny: bool = False
    moves: tuple[Move, ...] = ()
    rental: bool = False
    nature: str | None = None
    ability: str | None = None
    item: str | None = None
    mega: MegaForm | None = None
    pokemon_id: int | None = None
    can_evolve: bool = False
    tera: bool = False
    weight: int = field(default=0, repr=False)
    forms: tuple[MegaForm, ...] = field(default=(), repr=False)

    @property
    def label(self) -> str:
        return f"{self.name}{'✨' if self.shiny else ''} Lv{self.level}"


@dataclass(frozen=True)
class Carry:
    """What a Pokémon brings into a battle from the previous one of a run: its HP share (1..100) and its status."""

    hp: int
    status: str | None = None


CARRIED_STATUSES = ("burn", "poison", "toxic", "paralysis", "sleep", "freeze")


class _Weather:
    """`kind` is the weather that acts: None while an ability that clears it is out (Air Lock); `current` is the one
    set, which keeps counting down. `lasting` weather (Desolate Land's) has no countdown and no other weather replaces
    it; it ends when no Pokémon holding it up is out."""

    def __init__(self, kind: str | None = None, turns_left: int = 0):
        self.current, self.turns_left = kind, turns_left
        self.lasting = False
        self.teams: tuple | None = None

    @property
    def kind(self) -> str | None:
        if self.current is not None and self.cleared_by:
            return None
        return self.current

    @property
    def cleared_by(self) -> str:
        """The ability of the Pokémon out that keeps any weather from acting (Air Lock), or ""."""
        for team in self.teams or ():
            if team.active.hp > 0 and hooks.ability(team.active, "clears_weather", default=False):
                return team.active.ability
        return ""

    @kind.setter
    def kind(self, value: str | None) -> None:
        self.current = value

    @property
    def held(self) -> bool:
        """Strong winds and lasting weather have no countdown, and no weather move or common ability replaces them."""
        return self.current == STRONG_WINDS or self.lasting


@dataclass
class _Arena:
    """The field. `trick_room`, `gravity` and `terrain_turns` are the turns left; `sides[side]` maps each timed side
    state (a screen, Tailwind, Safeguard, Mist, Lucky Chant) to its turns left and `hazards[side]` each hazard to
    its layers, in the order they were set, and `pending[side]` each delayed attack aimed at it (Future Sight) to its
    turns left, user and move. `rooms` maps each other whole-field state (Magic Room, Wonder Room, Mud
    Sport) to its turns left. `log` collects the events a move's handlers make mid-action. `teams` are the two sides
    of a `simulate` run (None outside one); `last_move` is the last move anyone used, in `last_move_turn`."""

    trick_room: int = 0
    gravity: int = 0
    terrain: str | None = None
    terrain_turns: int = 0
    sides: list[dict[str, int]] = field(default_factory=lambda: [{}, {}])
    hazards: list[dict[str, int]] = field(default_factory=lambda: [{}, {}])
    pending: list[dict[str, tuple]] = field(default_factory=lambda: [{}, {}])
    turn: int = 0
    log: list = field(default_factory=list)
    rooms: dict[str, int] = field(default_factory=dict)
    teams: tuple | None = None
    last_move: Move | None = None
    last_move_turn: int = -1
    weather: _Weather = field(default_factory=_Weather)
    rng: random.Random = field(default_factory=lambda: random.Random(0), repr=False, compare=False)

    def states(self, side: int) -> tuple[str, ...]:
        """The effect keys of the states that act on `side`: the terrain, Gravity, the rooms, then that side's timed
        states, then the delayed attacks aimed at it."""
        return (*((self.terrain,) if self.terrain else ()), *(("gravity",) if self.gravity else ()), *self.rooms,
                *self.sides[side], *self.pending[side])

    def foe_of(self, fighter: "_Fighter") -> "_Fighter | None":
        return self.teams[1 - fighter.side].active if self.teams else None


class _Team:
    """A roster fought in order: `active` is the member in the field, entered fresh when its turn comes.
    `queue` holds the members still to come in, in order; a pivoting member goes back to the end of its group
    (the members before `finale`, or the finale). The member at `finale` gets its own Mega Evolution slot, whether
    or not one before it used the team's."""

    def __init__(self, roster: tuple[Combatant, ...], carried: Sequence[Carry | None] = (), finale: int | None = None,
                 unlimited_megas: bool = False, arena: _Arena | None = None, side: int = 0):
        self.roster = roster
        self.carried = tuple(carried) + (None,) * (len(roster) - len(carried))
        self.arena, self.side = arena, side
        self.fighters: dict[int, _Fighter] = {}
        self.place(0, _Fighter.enter(roster[0], self.carried[0]))
        self.current = 0
        self.queue = list(range(1, len(roster)))
        self.mega_used = False
        self.unlimited_megas = unlimited_megas
        self.finale = finale
        self.used: set[str] = set()
        self.fallen_before = 0

    @property
    def active(self) -> "_Fighter":
        return self.fighters[self.current]

    def place(self, index: int, fighter: "_Fighter") -> None:
        """Puts `fighter` in roster slot `index`, under this side's field states."""
        fighter.arena, fighter.side = self.arena, self.side
        self.fighters[index] = fighter

    def start_turn(self) -> None:
        """Clears the active member's this-turn state and tells it how many teammates have fainted so far and
        whether one fainted during the last turn."""
        fallen = sum(fighter.hp == 0 for fighter in self.fighters.values())
        fighter = self.active
        fighter.acted = fighter.hit_by_foe = fighter.lowered = False
        fighter.hurt = None
        fighter.turn_stages = dict(fighter.stages)
        fighter.flopped_last, fighter.flopped = fighter.flopped, False
        fighter.fallen_allies = fallen
        fighter.ally_fell_last_turn = fallen > self.fallen_before
        self.fallen_before = fallen

    @property
    def has_next(self) -> bool:
        return bool(self.queue)

    def send_next(self, member: int | None = None) -> bool:
        """Brings in `member` (default: the next in the queue). True when it had been out before."""
        index = self.queue[0] if member is None else member
        self.queue.remove(index)
        self.current = index
        if index in self.fighters:
            return True
        if index == self.finale:
            self.mega_used = False
        self.place(index, _Fighter.enter(self.roster[index], self.carried[index]))
        return False

    def pivot_target(self) -> int | None:
        return next((index for index in self.queue if self._group(index) == self._group(self.current)), None)

    def bench_active(self) -> None:
        """The active member leaves the field healthy: back of its group's queue, volatile state cleared, after its
        ability acts on the way out (Regenerator)."""
        _announce(self.active, hooks.ability(self.active, "on_switch_out", self.active, self.side))
        self.active.leave()
        group = self._group(self.current)
        at = next((position for position, index in enumerate(self.queue) if self._group(index) > group), len(self.queue))
        self.queue.insert(at, self.current)

    def _group(self, index: int) -> int:
        return int(self.finale is not None and index >= self.finale)

    def shares(self) -> tuple[int | None, ...]:
        return tuple(self.fighters[index].hp_percent if index in self.fighters else None
                     for index in range(len(self.roster)))

    def statuses(self) -> tuple[str | None, ...]:
        return tuple(self.fighters[index].status if index in self.fighters else None
                     for index in range(len(self.roster)))

    def standing(self) -> tuple[int, float]:
        """Members not yet fainted, then the sum of their HP shares; an unentered member counts at its carried HP."""
        waiting = [carry.hp / 100 if carry else 1.0
                   for index, carry in enumerate(self.carried) if index not in self.fighters]
        alive = [fighter for fighter in self.fighters.values() if fighter.hp > 0]
        return len(waiting) + len(alive), sum(waiting) + sum(fighter.hp / fighter.max_hp for fighter in alive)


class Hurt(NamedTuple):
    """The foe's hits that struck a Pokémon this turn: their category, damage and whether they made contact."""

    physical: bool
    dealt: int
    contact: bool


@dataclass
class _Fighter:
    combatant: Combatant
    max_hp: int
    hp: int
    stats: dict[str, int]
    pp: list[int]
    stages: dict[str, int] = field(default_factory=lambda: dict.fromkeys(STAGES, 0))
    status: str | None = None
    sleep_left: int = 0
    toxic_ticks: int = 0
    confusion_left: int = 0
    item: str | None = None
    locked: int | None = None
    drowsy_at: int = 0
    fresh: bool = True
    danced: bool = False
    acted: bool = False
    hit_by_foe: bool = False
    hurt: Hurt | None = None
    lowered: bool = False
    turn_stages: dict[str, int] | None = None
    flopped: bool = False
    flopped_last: bool = False
    times_hit: int = 0
    fallen_allies: int = 0
    ally_fell_last_turn: bool = False
    item_lost: bool = False
    ate_berry: bool = False
    ability_ignored: bool = False
    volatiles: dict[str, object] = field(default_factory=dict)
    memory: dict[str, object] = field(default_factory=dict)
    entered_as: Combatant | None = None
    entered_stats: dict[str, int] | None = None
    entered_pp: list[int] | None = None
    form_id: int | None = None
    last_used: int | None = None
    choice: int | None = None
    entered_turn: int = 0
    berry: str | None = None
    primed: str | None = None
    once: set[str] = field(default_factory=set)
    arena: _Arena | None = field(default=None, repr=False, compare=False)
    side: int = field(default=0, repr=False, compare=False)

    def leave(self) -> None:
        """Switching out clears stat stages, the Choice lock, confusion, the toxic count, drowsiness, its own states
        (`volatiles`, `memory`), a changed type, ability, stat or moveset and what this and the last turn did to it;
        the times it was hit stay."""
        self.stages = dict.fromkeys(STAGES, 0)
        self.volatiles, self.memory, self.last_used, self.primed = {}, {}, None, None
        if self.entered_as is not None:
            self.combatant, self.entered_as = self.entered_as, None
        if self.entered_stats is not None:
            self.stats, self.entered_stats = self.entered_stats, None
        if self.entered_pp is not None:
            self.pp, self.entered_pp = self.entered_pp, None
        self.locked = None
        self.confusion_left = self.toxic_ticks = self.drowsy_at = 0
        self.fresh = True
        self.danced = False
        self.acted = self.hit_by_foe = self.lowered = self.flopped = self.flopped_last = False

    @classmethod
    def enter(cls, combatant: Combatant, carry: Carry | None = None) -> "_Fighter":
        max_hp, stats = _stats_of(combatant)
        fighter = cls(combatant, max_hp, max_hp, stats, [move.pp for move in combatant.moves], item=items.known(combatant.item))
        if carry is not None:
            fighter.hp = max(1, min(max_hp, round(max_hp * carry.hp / 100)))
            fighter.status = carry.status
            fighter.sleep_left = SLEEP_TURNS[0] if carry.status == "sleep" else 0
        return fighter

    @property
    def hp_percent(self) -> int:
        return 0 if self.hp <= 0 else max(1, round(self.hp * 100 / self.max_hp))

    @property
    def ability(self) -> str | None:
        """None while a move ignores its breakable ability (Mold Breaker) or the foe's Neutralizing Gas is out, unless
        its item shields the ability (Ability Shield)."""
        ability = self.combatant.ability
        if hooks.call("items", self.item, "shields_ability", default=False):
            return ability
        if self.ability_ignored and ability in abilities.BREAKABLE:
            return None
        foe = self.arena.foe_of(self) if self.arena is not None else None
        if foe is not None and foe is not self and foe.hp > 0 and ability not in abilities.UNSUPPRESSED and hooks.call(
                "abilities", foe.combatant.ability, "suppresses_abilities", default=False):
            return None
        return ability

    def residual_damage(self) -> int:
        due = self.residual_due()
        if self.status == "toxic":
            self.toxic_ticks += 1
        return due

    def residual_due(self) -> int:
        """The HP its burn or poison takes at the next end of turn; 0 without one."""
        if self.status == "toxic":
            return max(1, self.max_hp * (self.toxic_ticks + 1) // TOXIC_DAMAGE_FRACTION)
        return max(1, self.max_hp // RESIDUAL_FRACTIONS[self.status]) if self.status in RESIDUAL_FRACTIONS else 0

    def stat(self, key: str, weather: str | None = None, staged: bool = True) -> float:
        weather = _sheltered(self, weather)
        stage = self.stages[key] if staged else 0
        context = (key, weather, self.status is not None, self.combatant.can_evolve, self)
        multiplier = hooks.item(self, "modify_stat", *context, default=1.0)
        raw = self.stats[next(iter(_field(self, "swaps_stat", key)), key)]
        value = raw * ((2 + stage) / 2 if stage >= 0 else 2 / (2 - stage)) * multiplier
        if key == "speed" and self.status == "paralysis":
            value /= 2
        terrain = self.arena.terrain if self.arena is not None else None
        foe = self.arena.foe_of(self) if self.arena is not None else None
        ruined = foe is not None and foe is not self and foe.hp > 0
        return (value * hooks.ability(self, "modify_stat", key, weather, self, default=1.0)
                * hooks.ability(self, "field_stat", key, weather, terrain, default=1.0)
                * math.prod(_field(self, "side_stat", key))
                * (hooks.ability(foe, "modify_foe_stat", key, self, default=1.0) if ruined else 1.0))


def _take_form(fighter: _Fighter, form: MegaForm | None, lasting: bool = False) -> FormShift:
    """The fighter takes the form's types and base stats, or (None) the ones it entered with. A `lasting` form stays
    once it leaves (Power Construct); any other ends then. A higher max HP raises its HP by the difference."""
    entered = fighter.entered_as or fighter.combatant
    if form is None:
        form = MegaForm(entered.types, entered.base, form_id=entered.pokemon_id, kind="base")
    if lasting:
        fighter.combatant = replace(fighter.combatant, types=form.types, base=form.base)
        if fighter.entered_as is not None:
            fighter.entered_as = replace(fighter.entered_as, types=form.types, base=form.base)
    else:
        fighter.entered_as = entered
        fighter.combatant = replace(fighter.combatant, types=form.types, base=form.base)
        fighter.entered_stats = fighter.entered_stats or dict(fighter.stats)
    max_hp, fighter.stats = _stats_of(fighter.combatant)
    if lasting and fighter.entered_stats is not None:
        fighter.entered_stats = dict(fighter.stats)
    fighter.hp, fighter.max_hp = fighter.hp + max(0, max_hp - fighter.max_hp), max_hp
    turn = fighter.arena.turn if fighter.arena is not None else 0
    return FormShift(turn, fighter.side, fighter.combatant.name, form.kind, form.form_id)


def _stats_of(combatant: Combatant) -> tuple[int, dict[str, int]]:
    """The max HP and the other stats before stages."""
    base, ivs, level = combatant.base, combatant.ivs, combatant.level
    max_hp = 1 if base.hp == 1 else (2 * base.hp + ivs.hp) * level // 100 + level + 10
    stats = {key: _other_stat(getattr(base, key), getattr(ivs, key), level) for key in BATTLE_STATS}
    if combatant.nature in NATURE_MODIFIERS:
        up, down = NATURE_MODIFIERS[combatant.nature]
        stats[up] = stats[up] * 110 // 100
        stats[down] = stats[down] * 90 // 100
    return max_hp, stats


def _carry_of(fighter: _Fighter) -> Carry | None:
    """None for a fighter at full health with no status, so an ordinary entry stays exact."""
    if fighter.hp == fighter.max_hp and fighter.status is None:
        return None
    return Carry(fighter.hp_percent, fighter.status)


def _announce(fighter: "_Fighter", event) -> None:
    """Logs what an ability did mid-action, shown after the action."""
    if event is not None and fighter.arena is not None:
        _append(fighter.arena.log, event)


def _append(events: list[Event], event: Event | tuple[Event, ...] | None) -> None:
    if isinstance(event, tuple):
        events.extend(event)
    elif event is not None:
        events.append(event)


def _field(fighter: _Fighter, hook: str, *args) -> list:
    """The answers of the field and side states acting on `fighter`'s side, then of its own states (`volatiles`),
    that run `hook`, None left out."""
    arena = fighter.arena
    states = (*(arena.states(fighter.side) if arena is not None else ()), *fighter.volatiles)
    return [answer for state in states if (answer := hooks.key("moves", state, hook, *args)) is not None]


def _sheltered(fighter: "_Fighter", weather: str | None) -> str | None:
    """The weather as it acts on `fighter`: its item may keep sun and rain off it (Utility Umbrella)."""
    return None if weather in WEATHER_MOVE_BOOST and hooks.item(fighter, "shelters", default=False) else weather


def _other_stat(base: int, iv: int, level: int) -> int:
    return (2 * base + iv) * level // 100 + 5
