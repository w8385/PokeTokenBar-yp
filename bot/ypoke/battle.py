"""Automatic battle between rosters of up to three Pokémon, fought one at a time in order: base stats, level
(capped at 50), IVs, natures, type effectiveness and level-up moves with PP, priority, critical-hit stages,
multi-hit, drain and recoil, the major statuses (burn, paralysis, poison, toxic, sleep, freeze), confusion, stat
stages, five-turn weather, about twenty abilities and one held item per Pokémon, and the effect moves (Trick Room,
Yawn, Thunder Wave, the pivot moves) with the field and side states: terrains, Gravity, screens, Tailwind, Safeguard,
Mist, Lucky Chant and the entry hazards. Abilities, items, move effects and active states act through their handlers
in `ypoke.effects`, which this turn loop calls at the hook points of `effects.hooks.HOOKS`.
The next member comes in when one faints; the only other switch is a pivot move's. The first member of a side
holding its Mega Stone Mega Evolves at the start of its first turn, after its entry ability has acted; a Primal orb
reverts its holder as it enters."""

import math
import random
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass, field, replace
from typing import NamedTuple

from ypoke import abilities, items, move_power, tera_forms
from ypoke.effects import hooks
from ypoke.move_effects import CHOSEN_DAMAGE_EFFECTS, FLAGS, POWERLESS_ATTACKS, PUNCH_MOVES, STATUS_MOVES
from ypoke.type_chart import effectiveness

STAB_MULTIPLIER = 1.5
CRITICAL_MULTIPLIER = 1.5
DAMAGE_DIVISOR = 50
LOWEST_ROLL = 0.85
CRITICAL_CHANCES = (1 / 24, 1 / 8, 1 / 2, 1.0)
BURN_DAMAGE_FRACTION = 16
POISON_DAMAGE_FRACTION = 8
TOXIC_DAMAGE_FRACTION = 16
FULL_PARALYSIS_CHANCE = 0.25
STRUGGLE_RECOIL_FRACTION = 4
MAX_STAGE = 6
TURN_LIMIT = 300
BATTLE_LEVEL = 50
BATTLE_STATS = ("attack", "defense", "special_attack", "special_defense", "speed")
STAGES = (*BATTLE_STATS, "accuracy", "evasion")
WEATHER_TURNS = 5
STRONG_WINDS = "strong-winds"
# Under Desolate Land's sun or Primordial Sea's rain, damaging moves of this type fail.
PRIMAL_DOUSED = {"sun": "water", "rain": "fire"}
WEATHER_CHIP_FRACTION = 16
WEATHER_MOVE_BOOST = {
    "sun": {"fire": 1.5, "water": 0.5},
    "rain": {"water": 1.5, "fire": 0.5},
}
WEATHER_CHIP_IMMUNE_TYPES = {"sandstorm": {"rock", "ground", "steel"}, "hail": {"ice"}}
SPECIAL_DEFENSE_BOOSTED_TYPE = {"sandstorm": "rock"}
DEFENSE_BOOSTED_TYPE = {"snow": "ice"}
STAT_PAIRS = {True: ("attack", "defense"), False: ("special_attack", "special_defense")}
WEATHER_SWING_MIN = 1.3
WEATHER_CHIP_SWING = 1.5
FREEZE_THAW_CHANCE = 0.2
CONFUSION_SELF_HIT_CHANCE = 1 / 3
CONFUSION_SELF_HIT_POWER = 40
SLEEP_TURNS = (1, 3)
CONFUSION_TURNS = (2, 5)
MULTI_HIT_ODDS = {2: 35, 3: 35, 4: 15, 5: 15}
AILMENT_IMMUNE_TYPES = {
    "burn": ("fire",), "paralysis": ("electric",), "poison": ("poison", "steel"), "toxic": ("poison", "steel"),
    "freeze": ("ice",), "sleep": (), "confusion": (),
}
RESIDUAL_FRACTIONS = {"burn": BURN_DAMAGE_FRACTION, "poison": POISON_DAMAGE_FRACTION}
TRICK_ROOM_TURNS = 5
STEALTH_ROCK_FRACTION = 8
STATUS_EFFECTS = tuple(dict.fromkeys(STATUS_MOVES.values()))
SWORDS_DANCE_STAGES = 2
END_OF_TURN = ("cures", "status", "weather", "terrain", "items", "abilities", "volatiles", "yawn", "sides", "trick-room",
               "rooms", "field", "winds", "replace")
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


STRUGGLE = Move("발버둥", None, 50, physical=True, id=165)
CONFUSION_HIT = Move("혼란", None, CONFUSION_SELF_HIT_POWER, physical=True)


@dataclass(frozen=True)
class MegaForm:
    """What a Mega Evolution swaps in. `ability` is the narrated name, `ability_id` the PokéAPI slug that replaces
    the Pokémon's ability (one the battle does not know does nothing; None keeps the old one)."""

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

    @property
    def label(self) -> str:
        return f"{self.name}{'✨' if self.shiny else ''} Lv{self.level}"


@dataclass(frozen=True)
class Change:
    """An effect that landed: a status (`AILMENT_IMMUNE_TYPES` key), "thaw", or a `BATTLE_STATS` key with `stages`."""

    side: int
    pokemon: str
    kind: str
    stages: int = 0


@dataclass(frozen=True)
class Action:
    """One Pokémon's turn. `move` is "" when it could not act; `blocked` says why ("paralysis", "sleep", "freeze",
    "gravity" or "confusion", the last one meaning it hurt itself). A used move a state stopped keeps its `move`,
    with `failed` and the state in `blocked` ("psychic-terrain"). `attacker_hp` / `defender_hp` are HP shares after it.
    `recovered` lists what ended before it acted ("sleep", "freeze", "confusion"). `hits` counts a multi-hit
    move's hits; `drained` means the user healed from the damage. `attacker_item` / `defender_item` name the
    held item that triggered on that side during this action (Life Orb recoil, Focus Sash). `effect` is what an
    effect move did (its effect key, or "trick-room-off"); `pivoted` means the user switched out. `via` names the
    move that called `move` (Metronome), and `move_id` is always the slot the user picked."""

    turn: int
    side: int
    attacker: str
    defender: str
    move: str
    missed: bool = False
    multiplier: float = 1.0
    critical: bool = False
    changes: tuple[Change, ...] = ()
    recoil: bool = False
    defender_hp: int = 100
    knockout: bool = False
    attacker_fainted: bool = False
    weather: str | None = None
    failed: bool = False
    blocked: str = ""
    recovered: tuple[str, ...] = ()
    hits: int = 1
    drained: bool = False
    attacker_hp: int = 100
    ability: str | None = None
    attacker_item: str = ""
    defender_item: str = ""
    effect: str = ""
    pivoted: bool = False
    move_id: int = 0
    via: str = ""


@dataclass(frozen=True)
class AbilityTrigger:
    """An ability that took effect as the Pokémon entered: it lowered the foe's stat (`change`) or started `weather`."""

    side: int
    pokemon: str
    ability: str
    change: Change | None = None
    weather: str | None = None


@dataclass(frozen=True)
class AbilityField(AbilityTrigger):
    """An entry ability that started a `terrain` or `cleared` field and side states (Screen Cleaner)."""

    terrain: str | None = None
    cleared: tuple[str, ...] = ()


@dataclass(frozen=True)
class AbilityTransform(AbilityTrigger):
    """Imposter: the Pokémon became the foe `into`. `form_id` is the `/pokemon` id of the form it now shows,
    `own_form_id` the one it shows again once it leaves."""

    into: str = ""
    form_id: int | None = None
    own_form_id: int | None = None


@dataclass(frozen=True)
class AbilityRetype(AbilityTrigger):
    """Protean, Libero: the Pokémon became the type `into` as it used a move; logged after the move."""

    into: str = ""


@dataclass(frozen=True)
class AbilityEntry(AbilityTrigger):
    """Any other entry ability: what it did (`effect`, a `narration.ABILITY_EFFECT_TEXT` key, about `detail`) and the
    `changes` it made."""

    effect: str = ""
    detail: str = ""
    changes: tuple[Change, ...] = ()


@dataclass(frozen=True)
class AbilityAct:
    """An ability acting during a turn: the `changes` it made, the HP share it left its holder (`hp`) or the foe
    (`foe_hp`) with, or what else it did (`effect`, a `narration.ABILITY_EFFECT_TEXT` key, about `detail`)."""

    turn: int
    side: int
    pokemon: str
    ability: str
    changes: tuple[Change, ...] = ()
    hp: int | None = None
    fainted: bool = False
    foe: str = ""
    foe_hp: int | None = None
    foe_fainted: bool = False
    effect: str = ""
    detail: str = ""


@dataclass(frozen=True)
class FieldStart:
    """An attack that set a hazard on `side` as it hit (Stone Axe, Ceaseless Edge)."""

    turn: int
    side: int
    kind: str


@dataclass(frozen=True)
class FieldEnd:
    """A field or side state that wore off, or that `move` cleared. `side` is -1 for a state of the whole field."""

    turn: int
    kind: str
    side: int = -1
    move: str = ""


@dataclass(frozen=True)
class HazardHit:
    """An entry hazard other than Stealth Rock acting on an entering Pokémon: Spikes (`hp` is the share left), Toxic
    Spikes (`change` is the poison; `cleared` means a Poison type absorbed them) or Sticky Web (`change`)."""

    turn: int
    side: int
    pokemon: str
    hazard: str
    hp: int = 100
    fainted: bool = False
    change: Change | None = None
    cleared: bool = False


@dataclass(frozen=True)
class TerrainHeal:
    turn: int
    side: int
    pokemon: str
    hp: int


@dataclass(frozen=True)
class StatusDamage:
    """End-of-turn damage from `kind` ("burn", "poison" or "toxic")."""

    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool
    kind: str = "burn"


@dataclass(frozen=True)
class WeatherDamage:
    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool
    weather: str


@dataclass(frozen=True)
class WeatherEnd:
    turn: int
    weather: str


@dataclass(frozen=True)
class TrickRoomEnd:
    turn: int


@dataclass(frozen=True)
class HazardDamage:
    """Stealth Rock hurt a Pokémon as it entered; `hp` is the share left."""

    turn: int
    side: int
    pokemon: str
    hp: int
    fainted: bool


@dataclass(frozen=True)
class YawnSleep:
    """The Pokémon Yawn made drowsy last turn fell asleep at the end of `turn`."""

    turn: int
    side: int
    pokemon: str


@dataclass(frozen=True)
class VolatileTick:
    """A state on one Pokémon acted at the end of a turn or as a move landed: `kind` is its key, `hp` the share left
    (Leech Seed, Wish, a Substitute taking a hit: then the doll's), `count` a countdown it showed (Perish Song)."""

    turn: int
    side: int
    pokemon: str
    kind: str
    hp: int = 100
    fainted: bool = False
    count: int | None = None


@dataclass(frozen=True)
class VolatileEnd:
    """A state on one Pokémon wore off, or broke (a Substitute)."""

    turn: int
    side: int
    pokemon: str
    kind: str


@dataclass(frozen=True)
class SendOut:
    """A member of `side` comes in during `turn`: after a faint at the end of the turn, or right after a pivot move.
    `member` is its index in the side's roster (-1: not given)."""

    turn: int
    side: int
    pokemon: str
    member: int = -1


@dataclass(frozen=True)
class ItemHeal:
    """An item that changed HP at the end of a turn or right after a hit; `hp` is the share left (Black Sludge hurts)."""

    turn: int
    side: int
    pokemon: str
    item: str
    hp: int
    fainted: bool = False


@dataclass(frozen=True)
class ItemEffect:
    """An item that acted without moving HP: `effect` is "cure" (Lum Berry), "restore" (White Herb), "first"
    (Quick Claw) or the status a Flame or Toxic Orb inflicted ("burn", "toxic")."""

    turn: int
    side: int
    pokemon: str
    item: str
    effect: str


@dataclass(frozen=True)
class MegaEvolution:
    turn: int
    side: int
    pokemon: str
    ability: str | None
    form_id: int | None = None
    kind: str = "mega"


@dataclass(frozen=True)
class FormShift:
    """A held-item form taking hold on entry: `kind` is "mask" (Ogerpon's mask glowed, `change` is its +1),
    "terastal" or "stellar" (Terapagos) or an `ITEM_FORMS` kind ("origin", "crowned-sword", "crowned-shield").
    `form_id` is the `/pokemon` id of the form shown, if it has one."""

    turn: int
    side: int
    pokemon: str
    kind: str
    form_id: int | None = None
    change: Change | None = None


Event = (
    Action | AbilityTrigger | StatusDamage | WeatherDamage | WeatherEnd | SendOut | ItemHeal | ItemEffect | MegaEvolution
    | FormShift | TrickRoomEnd | HazardDamage | YawnSleep | FieldStart | FieldEnd | HazardHit | TerrainHeal
    | VolatileTick | VolatileEnd | AbilityAct
)


@dataclass(frozen=True)
class Carry:
    """What a Pokémon brings into a battle from the previous one of a run: its HP share (1..100) and its status."""

    hp: int
    status: str | None = None


CARRIED_STATUSES = ("burn", "poison", "toxic", "paralysis", "sleep", "freeze")


@dataclass
class BattleResult:
    """`remaining` is each side's HP share per roster member at the end (None: never sent out).
    `statuses` is the status each member ended with (None: none, or never sent out)."""

    winner: int
    turns: int
    events: list[Event] = field(default_factory=list)
    remaining: tuple[tuple[int | None, ...], tuple[int | None, ...]] = ((), ())
    statuses: tuple[tuple[str | None, ...], tuple[str | None, ...]] = ((), ())


def simulate(sides: tuple[Combatant | Sequence[Combatant], Combatant | Sequence[Combatant]], seed: int,
             carried: Sequence[Carry | None] = (), finale: int | None = None,
             unlimited_megas: bool = False) -> BattleResult:
    """Fight until one side has no Pokémon left or `TURN_LIMIT` turns pass.

    At the limit the side with more Pokémon left wins, then the one with the higher HP share.
    Each turn the active Pokémon picks its move with the highest expected damage that still has PP, or Struggle.
    The higher move priority acts first, then the faster Pokémon; a full tie is a coin flip from the seed.
    A weather move is picked when it swings the exchange by `WEATHER_SWING_MIN`; the weather lasts `WEATHER_TURNS` turns.
    A fainted Pokémon is replaced after the end-of-turn effects, so its successor takes no chip damage that turn.
    `carried` (per member of the first side, in order) starts a member hurt or with a status.
    `finale` is the second side's member index from which a second Mega Evolution is allowed; with `unlimited_megas`
    every member of the second side that can Mega Evolve does.
    Both sides follow the same rules and the same move choice (`_choose`).
    """
    rng = random.Random(seed)
    arena = _Arena()
    teams = (_Team(_roster(sides[0]), carried, arena=arena, side=0),
             _Team(_roster(sides[1]), finale=finale, unlimited_megas=unlimited_megas, arena=arena, side=1))
    arena.teams = teams
    events: list[Event] = []
    weather = arena.weather = _Weather()
    weather.teams = teams
    for side in (0, 1):
        _enter_forms(teams[side], side, 1, events)
    events.extend(_enter_battle((teams[0].active, teams[1].active), weather, rng))
    _item_triggers(1, (teams[0].active, teams[1].active), events)
    turn = 0
    loser: int | None = None
    while loser is None and turn < TURN_LIMIT:
        turn += 1
        arena.turn = turn
        for team in teams:
            team.start_turn()
        _mega_evolutions(teams, turn, weather, rng, events)
        fighters = (teams[0].active, teams[1].active)
        choices =(_choose(teams, 0, arena, weather.kind), _choose(teams, 1, arena, weather.kind))
        for fighter, choice in zip(fighters, choices):
            fighter.choice = choice
        trick_room = arena.trick_room > 0
        claws = _quick_claws(turn, fighters, choices, weather.kind, rng, events, trick_room)
        for side in _turn_order(fighters, choices, rng, weather.kind, claws, trick_room):
            fighters = (teams[0].active, teams[1].active)
            if fighters[side].hp == 0 or fighters[1 - side].hp == 0:
                continue
            fighters[side].fresh = False
            action = _act(turn, side, fighters, choices[side], weather, rng, arena)
            fighters[side].acted = True
            fighters[side].flopped = bool(action.move) and (action.missed or action.failed or action.multiplier == 0)
            _note_effect(teams[side], action)
            if action.move and _pivots(teams[side], action, choices[side]):
                action = replace(action, pivoted=True)
            events.append(action)
            events.extend(arena.log)
            arena.log.clear()
            loser = _exhausted(teams, (side, 1 - side) if _self_ko(teams[side].active, choices[side]) else (1 - side, side))
            if loser is not None:
                break
            if action.pivoted:
                loser = _pivot(teams, side, turn, arena, weather, rng, events)
                if loser is not None:
                    break
            _item_triggers(turn, (teams[0].active, teams[1].active), events)
            _calm_winds(turn, teams, weather, events)
        if loser is None:
            loser = _end_of_turn(turn, teams, weather, arena, rng, events)
    if loser is None:
        loser = 1 if teams[0].standing() >= teams[1].standing() else 0
    return BattleResult(
        winner=1 - loser, turns=turn, events=events, remaining=(teams[0].shares(), teams[1].shares()),
        statuses=(teams[0].statuses(), teams[1].statuses()),
    )


def _end_of_turn(turn: int, teams: tuple["_Team", "_Team"], weather: "_Weather", arena: "_Arena", rng: random.Random,
                 events: list[Event]) -> int | None:
    """Runs the `END_OF_TURN` steps in order; the side a step leaves with nobody to send out loses there."""
    fighters = (teams[0].active, teams[1].active)
    for step in END_OF_TURN:
        loser = _end_of_turn_step(step, turn, teams, fighters, weather, arena, rng, events)
        events.extend(arena.log)
        arena.log.clear()
        if loser is not None:
            return loser
    return None


def _end_of_turn_step(step: str, turn: int, teams: tuple["_Team", "_Team"], fighters: tuple["_Fighter", "_Fighter"],
                      weather: "_Weather", arena: "_Arena", rng: random.Random, events: list[Event]) -> int | None:
    if step == "cures":
        _cure_upkeep(turn, fighters, events, rng)
        return None
    if step == "status":
        return _status_upkeep(turn, teams, fighters, events)
    if step == "weather":
        _weather_upkeep(turn, fighters, weather, events)
        return _exhausted(teams, (0, 1))
    if step == "items":
        _item_upkeep(turn, fighters, events, rng)
        return _exhausted(teams, (0, 1))
    if step == "abilities":
        _ability_upkeep(turn, fighters, events, rng)
        return _exhausted(teams, (0, 1))
    if step == "volatiles":
        _volatile_upkeep(turn, fighters, events, rng)
        return _exhausted(teams, (0, 1))
    if step == "rooms":
        _room_upkeep(turn, arena, events)
    elif step == "terrain":
        _terrain_upkeep(turn, fighters, events, rng)
    elif step == "yawn":
        _yawn_upkeep(turn, fighters, events, rng)
    elif step == "sides":
        _side_upkeep(turn, arena, events)
    elif step == "trick-room":
        _trick_room_upkeep(turn, arena, events)
    elif step == "field":
        _field_upkeep(turn, arena, events)
    elif step == "winds":
        _calm_winds(turn, teams, weather, events)
    else:
        return _replace_fainted(teams, turn, arena, weather, rng, events)
    return None


def _cure_upkeep(turn: int, fighters: tuple["_Fighter", "_Fighter"], events: list[Event],
                 rng: random.Random) -> None:
    for side, fighter in enumerate(fighters):
        if fighter.hp > 0 and fighter.status is not None:
            _append(events, hooks.ability(fighter, "cures_status", fighter, side, turn, rng))


def _status_upkeep(turn: int, teams: tuple["_Team", "_Team"], fighters: tuple["_Fighter", "_Fighter"],
                   events: list[Event]) -> int | None:
    for side, fighter in enumerate(fighters):
        if fighter.hp > 0 and fighter.status in ("burn", "poison", "toxic"):
            damage = fighter.residual_damage()
            if _chip_free(fighter):
                continue
            damage = hooks.ability(fighter, "modify_status_damage", damage, fighter.status, default=damage)
            answer = hooks.ability(fighter, "status_damage", damage, fighter, side, turn)
            if answer is not None:
                events.append(answer)
                continue
            fighter.hp = max(0, fighter.hp - damage)
            events.append(
                StatusDamage(turn, side, fighter.combatant.name, fighter.hp_percent, fighter.hp == 0, fighter.status)
            )
            loser = _exhausted(teams, (side,))
            if loser is not None:
                return loser
    return None


def _calm_winds(turn: int, teams: tuple["_Team", "_Team"], weather: "_Weather", events: list[Event]) -> None:
    """Strong winds and lasting weather end once no Pokémon holding them up is out; no other weather comes back."""
    if (weather.current == STRONG_WINDS or weather.lasting) and not any(
            team.active.hp > 0 and hooks.ability(team.active, "keeps_weather", weather.current, default=False)
            for team in teams):
        events.append(WeatherEnd(turn, weather.current))
        weather.kind, weather.lasting = None, False


def _roster(side: Combatant | Sequence[Combatant]) -> tuple[Combatant, ...]:
    return (side,) if isinstance(side, Combatant) else tuple(side)


def _exhausted(teams: tuple["_Team", "_Team"], order: tuple[int, ...]) -> int | None:
    """The first side in `order` whose active Pokémon fainted with nobody left to send out."""
    return next((side for side in order if teams[side].active.hp == 0 and not teams[side].has_next), None)


def _replace_fainted(teams: tuple["_Team", "_Team"], turn: int, arena: "_Arena", weather: "_Weather",
                     rng: random.Random, events: list[Event]) -> int | None:
    """End of turn: each side whose active Pokémon fainted sends the next one, again while the hazards knock out
    the newcomer. Returns the side that ran out, if any."""
    while True:
        entering = tuple(side for side in (0, 1) if teams[side].active.hp == 0)
        if not entering:
            return None
        loser = _exhausted(teams, entering)
        if loser is not None:
            return loser
        standing = tuple(side for side in entering if _send_in(teams[side], side, turn, arena, events, rng))
        if standing:
            events.extend(_enter_battle((teams[0].active, teams[1].active), weather, rng, standing))
            _item_triggers(turn, (teams[0].active, teams[1].active), events)


def _send_in(team: "_Team", side: int, turn: int, arena: "_Arena", events: list[Event], rng: random.Random,
             member: int | None = None) -> bool:
    """Brings in the next member (or `member`): the hazards on its side in the order they were set, then its forms.
    False if the hazards knocked it out."""
    returning = team.send_next(member)
    fighter = team.active
    fighter.entered_turn = turn
    events.append(SendOut(turn, side, fighter.combatant.name, team.current))
    for hazard, layers in list(arena.hazards[side].items()):
        if fighter.hp > 0:
            _append(events, hooks.key("moves", hazard, "hazard", layers, fighter, side, turn, rng))
    if fighter.hp == 0:
        return False
    if not returning:
        _enter_forms(team, side, turn, events)
    return True


def _pivot(teams: tuple["_Team", "_Team"], side: int, turn: int, arena: "_Arena", weather: "_Weather",
           rng: random.Random, events: list[Event]) -> int | None:
    """The pivot move's user goes to the back of its group and the next healthy member of the group comes in."""
    team = teams[side]
    target = team.pivot_target()
    team.bench_active()
    events.extend(arena.log)
    arena.log.clear()
    if _send_in(team, side, turn, arena, events, rng, target):
        events.extend(_enter_battle((teams[0].active, teams[1].active), weather, rng, (side,)))
        return None
    return _exhausted(teams, (side,))


def _pivots(team: "_Team", action: Action, index: int | None) -> bool:
    """A pivot move that hit switches its user out when a healthy member of its group is waiting."""
    if index is None or action.missed or action.failed or action.multiplier == 0 or action.attacker_fainted:
        return False
    move = team.active.combatant.moves[index]
    return hooks.move(move, "switches_user_out", default=False) and team.pivot_target() is not None


def _note_effect(team: "_Team", action: Action) -> None:
    hooks.key("moves", action.effect, "remember", team)


def _yawn_upkeep(turn: int, fighters: tuple["_Fighter", "_Fighter"], events: list[Event], rng: random.Random) -> None:
    for side, fighter in enumerate(fighters):
        if fighter.drowsy_at != turn:
            continue
        fighter.drowsy_at = 0
        if fighter.hp > 0 and _open_to("sleep", fighter) and not _blocks_ailment(fighter, "sleep"):
            _inflict("sleep", fighter, side, rng)
            events.append(YawnSleep(turn, side, fighter.combatant.name))


def _trick_room_upkeep(turn: int, arena: "_Arena", events: list[Event]) -> None:
    if arena.trick_room == 0:
        return
    arena.trick_room -= 1
    if arena.trick_room == 0:
        events.append(TrickRoomEnd(turn))


def _terrain_upkeep(turn: int, fighters: tuple["_Fighter", "_Fighter"], events: list[Event],
                    rng: random.Random) -> None:
    for side, fighter in enumerate(fighters):
        if fighter.hp > 0:
            events.extend(_field(fighter, "end_of_turn", fighter, side, turn, rng))


def _volatile_upkeep(turn: int, fighters: tuple["_Fighter", "_Fighter"], events: list[Event],
                     rng: random.Random) -> None:
    """Each Pokémon's own states in the order they started (Leech Seed, Perish Song, Taunt's countdown)."""
    for side, fighter in enumerate(fighters):
        for kind in list(fighter.volatiles):
            if fighter.hp > 0 and kind in fighter.volatiles:
                _append(events, hooks.key("moves", kind, "volatile_end", fighter, side, turn, rng))


def _room_upkeep(turn: int, arena: "_Arena", events: list[Event]) -> None:
    for kind in list(arena.rooms):
        arena.rooms[kind] -= 1
        if arena.rooms[kind] == 0:
            del arena.rooms[kind]
            events.append(FieldEnd(turn, kind))


def _side_upkeep(turn: int, arena: "_Arena", events: list[Event]) -> None:
    for side, states in enumerate(arena.sides):
        for kind in list(states):
            states[kind] -= 1
            if states[kind] == 0:
                del states[kind]
                events.append(FieldEnd(turn, kind, side))


def _field_upkeep(turn: int, arena: "_Arena", events: list[Event]) -> None:
    """Gravity, then the terrain."""
    if arena.gravity:
        arena.gravity -= 1
        if arena.gravity == 0:
            events.append(FieldEnd(turn, "gravity"))
    if arena.terrain is not None:
        arena.terrain_turns -= 1
        if arena.terrain_turns == 0:
            events.append(FieldEnd(turn, arena.terrain))
            arena.terrain = None


def _enter_forms(team: "_Team", side: int, turn: int, events: list[Event]) -> None:
    """Everything a Pokémon that just entered changes about itself before the entry abilities: its Primal Reversion
    (which takes the side's Mega Evolution slot), Terapagos' Terastal form, then its item's form."""
    if _mega_ready(team, at_entry=True):
        _mega_evolve(team, side, turn, events)
    fighter = team.active
    combatant = fighter.combatant
    if combatant.tera:
        fighter.form_id = tera_forms.TERASTAL_FORM
        events.append(FormShift(turn, side, combatant.name, "terastal", tera_forms.TERASTAL_FORM))
    shift = hooks.item(fighter, "on_entry_form", fighter, side, turn)
    if shift is not None:
        fighter.form_id = shift.form_id
        events.append(shift)


def _mega_ready(team: "_Team", at_entry: bool) -> bool:
    """The active member holds a form the side's once-per-battle slot still allows: a Primal orb reverts it as it
    enters, any other form (Mega Stone, Ultra Burst, Terapagos' Stellar form) at the start of a turn."""
    mega = team.active.combatant.mega
    return (mega is not None and (mega.kind == "primal") == at_entry
            and (not team.mega_used or team.unlimited_megas))


def _mega_evolve(team: "_Team", side: int, turn: int, events: list[Event]) -> None:
    """The active member keeps its HP share, status, stat stages and states; its Mega form replaces the base stats,
    types and ability."""
    fighter = team.active
    combatant = fighter.entered_as or fighter.combatant
    mega = combatant.mega
    ability = combatant.ability
    if mega.ability_id is not None:
        ability = mega.ability_id if mega.ability_id in abilities.NAMES else None
    evolved = replace(combatant, types=mega.types, base=mega.base, ability=ability, mega=None, tera=False)
    form = _Fighter.enter(evolved)
    fighter.hp = max(1, round(fighter.hp * form.max_hp / fighter.max_hp))
    fighter.combatant, fighter.max_hp, fighter.stats = evolved, form.max_hp, form.stats
    fighter.entered_as = fighter.entered_stats = None
    fighter.form_id = mega.form_id
    team.mega_used = True
    if mega.kind == "stellar":
        events.append(FormShift(turn, side, fighter.combatant.name, "stellar", mega.form_id))
    else:
        events.append(MegaEvolution(turn, side, fighter.combatant.name, mega.ability, mega.form_id, mega.kind))


def _mega_evolutions(teams: tuple["_Team", "_Team"], turn: int, weather: "_Weather", rng: random.Random,
                     events: list[Event]) -> None:
    """The start of a turn: each active member whose form is ready takes it, the faster first, and its new ability
    acts as if it had just entered (Mega Charizard Y's Drought)."""
    ready = tuple(side for side in (0, 1) if _mega_ready(teams[side], at_entry=False))
    if not ready:
        return
    order = ready
    if len(ready) == 2:
        speeds = [team.active.stat("speed") for team in teams]
        order = (0, 1) if speeds[0] > speeds[1] or (speeds[0] == speeds[1] and rng.random() < 0.5) else (1, 0)
    for side in order:
        _mega_evolve(teams[side], side, turn, events)
        events.extend(_enter_battle((teams[0].active, teams[1].active), weather, rng, (side,)))
    _item_triggers(turn, (teams[0].active, teams[1].active), events)


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
        if self.current is not None and self.teams and any(
                team.active.hp > 0 and hooks.ability(team.active, "clears_weather", default=False) for team in self.teams):
            return None
        return self.current

    @kind.setter
    def kind(self, value: str | None) -> None:
        self.current = value


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
    once: set[str] = field(default_factory=set)
    arena: _Arena | None = field(default=None, repr=False, compare=False)
    side: int = field(default=0, repr=False, compare=False)

    def leave(self) -> None:
        """Switching out clears stat stages, the Choice lock, confusion, the toxic count, drowsiness, its own states
        (`volatiles`, `memory`), a changed type, ability, stat or moveset and what this and the last turn did to it;
        the times it was hit stay."""
        self.stages = dict.fromkeys(STAGES, 0)
        self.volatiles, self.memory, self.last_used = {}, {}, None
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
        base, ivs, level = combatant.base, combatant.ivs, combatant.level
        max_hp = 1 if base.hp == 1 else (2 * base.hp + ivs.hp) * level // 100 + level + 10
        stats = {key: _other_stat(getattr(base, key), getattr(ivs, key), level) for key in BATTLE_STATS}
        if combatant.nature in NATURE_MODIFIERS:
            up, down = NATURE_MODIFIERS[combatant.nature]
            stats[up] = stats[up] * 110 // 100
            stats[down] = stats[down] * 90 // 100
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
        """None while a move ignores its breakable ability (Mold Breaker) or the foe's Neutralizing Gas is out."""
        ability = self.combatant.ability
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
        stage = self.stages[key] if staged else 0
        context = (key, weather, self.status is not None, self.combatant.can_evolve)
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


def _carry_of(fighter: _Fighter) -> Carry | None:
    """None for a fighter at full health with no status, so an ordinary entry stays exact."""
    if fighter.hp == fighter.max_hp and fighter.status is None:
        return None
    return Carry(fighter.hp_percent, fighter.status)


def _enter_battle(fighters: tuple[_Fighter, _Fighter], weather: _Weather, rng: random.Random,
                  entering: tuple[int, ...] = (0, 1)) -> list[AbilityTrigger]:
    """Entry abilities of the `entering` sides fire faster Pokémon first, so the slower weather setter's weather stays."""
    order = entering
    speeds = [fighter.stat("speed") for fighter in fighters]
    if len(entering) == 2 and all(hooks.has("abilities", fighter.ability, "on_entry") for fighter in fighters):
        order = (0, 1) if speeds[0] > speeds[1] or (speeds[0] == speeds[1] and rng.random() < 0.5) else (1, 0)
    triggers: list = []
    for side in order:
        trigger = hooks.ability(fighters[side], "on_entry", fighters[side], fighters[1 - side], side, weather)
        if trigger is not None:
            triggers.append(trigger)
        log = fighters[side].arena.log if fighters[side].arena is not None else []
        triggers.extend(log)
        log.clear()
    return triggers


def _turn_order(fighters: tuple[_Fighter, _Fighter], choices: tuple[int | None, int | None],
                rng: random.Random, weather: str | None = None,
                claws: tuple[bool, bool] = (False, False), trick_room: bool = False) -> tuple[int, int]:
    """Higher priority first, then one not held back to the end of its bracket (Stall), then a Quick Claw, then the
    faster Pokémon (the slower one under Trick Room)."""
    keys = [
        (_priority(fighter, choice), not _moves_last(fighter, choice), claw,
         fighter.stat("speed", weather) * (-1 if trick_room else 1))
        for fighter, choice, claw in zip(fighters, choices, claws)
    ]
    if keys[0] != keys[1]:
        return (0, 1) if keys[0] > keys[1] else (1, 0)
    return (0, 1) if rng.random() < 0.5 else (1, 0)


def _priority(fighter: _Fighter, choice: int | None) -> int:
    if choice is None:
        return 0
    return _move_priority(fighter, fighter.combatant.moves[choice])


def _moves_last(fighter: _Fighter, choice: int | None) -> bool:
    return hooks.ability(fighter, "moves_last", _chosen(fighter, choice), default=False)


def _move_priority(fighter: _Fighter, move: Move) -> int:
    return (move.priority + hooks.ability(fighter, "modify_priority", move, fighter, default=0)
            + hooks.move(move, "modify_priority", fighter, default=0))


def _quick_claws(turn: int, fighters: tuple[_Fighter, _Fighter], choices: tuple[int | None, int | None],
                 weather: str | None, rng: random.Random, events: list[Event],
                 trick_room: bool = False) -> tuple[bool, bool]:
    """Which Quick Claw holders may move first this turn (20% each; no draw without the item). Only a claw that
    puts a holder that would move second ahead of a foe in the same priority bracket is logged."""
    claws = tuple(hooks.item(fighter, "moves_first", rng, default=False) for fighter in fighters)
    drawn = tuple(not claw and hooks.ability(fighter, "moves_first", _chosen(fighter, choice), rng, default=False)
                  for fighter, choice, claw in zip(fighters, choices, claws))
    firsts = (claws[0] or drawn[0], claws[1] or drawn[1])
    if firsts[0] and firsts[1] or _priority(fighters[0], choices[0]) != _priority(fighters[1], choices[1]):
        return firsts
    for side, fighter in enumerate(fighters):
        mine, theirs = fighter.stat("speed", weather), fighters[1 - side].stat("speed", weather)
        if firsts[side] and (mine >= theirs if trick_room else mine <= theirs):
            events.append(ItemEffect(turn, side, fighter.combatant.name, fighter.item, "first") if claws[side] else
                          AbilityAct(turn, side, fighter.combatant.name, fighter.ability, effect="first"))
    return firsts


def _chosen(fighter: _Fighter, choice: int | None) -> Move:
    return STRUGGLE if choice is None else fighter.combatant.moves[choice]


def _weather_upkeep(turn: int, fighters: tuple[_Fighter, _Fighter], weather: _Weather,
                    events: list[Event]) -> int | None:
    """Chip damage to both sides, then the countdown, which runs on while an ability clears the weather. Returns the
    first side that fainted, if any."""
    if weather.current is None:
        return None
    fainted = None
    for side, fighter in enumerate(fighters):
        chip = _weather_chip(fighter, weather.kind)
        if fighter.hp > 0 and chip:
            fighter.hp = max(0, fighter.hp - chip)
            events.append(WeatherDamage(
                turn, side, fighter.combatant.name, fighter.hp_percent, fighter.hp == 0, weather.kind,
            ))
            if fighter.hp == 0 and fainted is None:
                fainted = side
    if weather.current == STRONG_WINDS or weather.lasting:
        return fainted
    weather.turns_left -= 1
    if weather.turns_left == 0:
        events.append(WeatherEnd(turn, weather.current))
        weather.kind = None
    return fainted


def _item_upkeep(turn: int, fighters: tuple[_Fighter, _Fighter], events: list[Event], rng: random.Random) -> None:
    """End-of-turn items (Leftovers, Black Sludge, the Flame and Toxic Orbs), then the one-use items."""
    for side, fighter in enumerate(fighters):
        if fighter.hp > 0:
            _append(events, hooks.item(fighter, "end_of_turn", fighter, side, turn, rng))
    _item_triggers(turn, fighters, events)


def _ability_upkeep(turn: int, fighters: tuple[_Fighter, _Fighter], events: list[Event], rng: random.Random) -> None:
    for side, fighter in enumerate(fighters):
        if fighter.hp > 0:
            _append(events, hooks.ability(fighter, "end_of_turn", fighter, side, turn, rng))


def _item_triggers(turn: int, fighters: tuple[_Fighter, _Fighter], events: list[Event]) -> None:
    """One-use items that react to the state a Pokémon is in: Sitrus Berry at half HP, Lum Berry on a status or
    confusion, White Herb on a lowered stat."""
    for side, fighter in enumerate(fighters):
        if fighter.hp > 0:
            _append(events, hooks.item(fighter, "on_update", fighter, side, turn))


def _append(events: list[Event], event: Event | tuple[Event, ...] | None) -> None:
    if isinstance(event, tuple):
        events.extend(event)
    elif event is not None:
        events.append(event)


def _weather_chip(fighter: _Fighter, weather: str | None) -> int:
    return max(1, fighter.max_hp // WEATHER_CHIP_FRACTION) if _chipped_by(fighter, weather) else 0


def _chipped_by(fighter: _Fighter, weather: str | None) -> bool:
    immune = WEATHER_CHIP_IMMUNE_TYPES.get(weather)
    return (immune is not None and not immune.intersection(fighter.combatant.types) and not _chip_free(fighter)
            and not hooks.ability(fighter, "blocks_weather_chip", weather, default=False))


def _act(turn: int, side: int, fighters: tuple[_Fighter, _Fighter], index: int | None, weather: _Weather,
         rng: random.Random, arena: _Arena | None = None) -> Action:
    """One Pokémon's turn. A self-KO move (Explosion) faints its user once used, hit, miss or immune target, and an
    HP-cost move (Steel Beam) takes its share then too."""
    action = _resolve(turn, side, fighters, index, weather, rng, arena)
    if action.move:
        used = STRUGGLE if index is None else fighters[side].combatant.moves[index]
        action = replace(action, move_id=used.id)
        fighters[side].last_used = index
        if arena is not None:
            arena.last_move, arena.last_move_turn = used, turn
        paid = hooks.move(used, "pays_hp", fighters[side]) if not action.failed or action.blocked else None
        if paid is not None:
            action = replace(action, changes=(*action.changes, paid), attacker_hp=fighters[side].hp_percent,
                             attacker_fainted=fighters[side].hp == 0)
    if action.move and _self_ko(fighters[side], index) and not _damped(fighters[side]):
        fighters[side].hp = 0
        return replace(action, attacker_hp=0, attacker_fainted=True)
    return action


def _self_ko(fighter: _Fighter, index: int | None) -> bool:
    return index is not None and hooks.move(fighter.combatant.moves[index], "faints_user", default=False)


def _damped(fighter: _Fighter) -> bool:
    """A foe's ability keeps self-KO moves from working at all (Damp)."""
    foe = fighter.arena.foe_of(fighter) if fighter.arena is not None else None
    return foe is not None and foe.hp > 0 and hooks.ability(foe, "prevents_self_ko", default=False)


def _resolve(turn: int, side: int, fighters: tuple[_Fighter, _Fighter], index: int | None, weather: _Weather,
             rng: random.Random, arena: _Arena | None = None) -> Action:
    """A move charged on the last turn (Solar Beam) comes out now with no PP paid, unless the user cannot act."""
    attacker, defender = fighters[side], fighters[1 - side]
    names = (attacker.combatant.name, defender.combatant.name)
    readied = next(iter(_field(attacker, "readied", attacker)), None)
    move = readied or (STRUGGLE if index is None else attacker.combatant.moves[index])
    recovered, blocked = _start_of_action(attacker, move, rng)
    if not blocked and hooks.ability(attacker, "skips_turn", attacker, default=False):
        blocked = attacker.ability
    if blocked:
        if blocked == "confusion":
            attacker.hp = max(0, attacker.hp - _damage(attacker, attacker, CONFUSION_HIT, 1.0, False, None, rng))
        return Action(
            turn, side, *names, move="", defender_hp=defender.hp_percent, blocked=blocked, recovered=recovered,
            attacker_hp=attacker.hp_percent, attacker_fainted=attacker.hp == 0,
        )
    if index is not None and readied is None:
        attacker.pp[index] -= 1
        extra = hooks.ability(defender, "pp_cost", move, default=0)
        if extra:
            attacker.pp[index] = max(0, attacker.pp[index] - extra)
        if hooks.item(attacker, "locks_move", default=False) or hooks.ability(attacker, "locks_move", default=False):
            attacker.locked = index
    stage = arena if arena is not None else _Arena(weather=weather)
    called = hooks.move(move, "calls", attacker, defender, side, stage, rng, default=move)
    if called is None:
        return Action(turn, side, *names, move.name, failed=True, recovered=recovered, defender_hp=defender.hp_percent,
                      attacker_hp=attacker.hp_percent)
    effect, charged = (None if readied else hooks.move(called, "charges", attacker, side, weather.kind)) or ("", ())
    if effect:
        return Action(turn, side, *names, called.name, effect=effect, changes=charged, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent)
    with _ability_ignored(attacker, defender, called):
        action = _strike(turn, side, attacker, defender,
                         _retyped(attacker, move_power.typed(called, weather.kind, attacker)), recovered, weather, rng,
                         stage)
    action = replace(action, changes=(*charged, *action.changes)) if charged else action
    return action if called is move else replace(action, via=move.name)


@contextmanager
def _ability_ignored(attacker: _Fighter, defender: _Fighter, move: Move) -> Iterator[None]:
    """A move that ignores abilities (Sunsteel Strike) or a user's ability that does (Mold Breaker) leaves the
    target's breakable ability out until its contact ability acts."""
    defender.ability_ignored = (hooks.move(move, "ignores_ability", default=False)
                                or hooks.ability(attacker, "breaks_abilities", move, default=False))
    try:
        yield
    finally:
        defender.ability_ignored = False


def _strike(turn: int, side: int, attacker: _Fighter, defender: _Fighter, move: Move, recovered: tuple[str, ...],
            weather: _Weather, rng: random.Random, arena: _Arena) -> Action:
    """The used move acts on the defender, once its user could act and paid the PP."""
    names = (attacker.combatant.name, defender.combatant.name)
    backfired = next(iter(_field(attacker, "backfires", move, attacker)), "")
    if backfired:
        return Action(turn, side, *names, move.name, failed=True, blocked=backfired, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent,
                      attacker_fainted=attacker.hp == 0)
    if hooks.move(move, "fails", attacker, defender, default=False):
        return Action(turn, side, *names, move.name, failed=True, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent)
    _announce(attacker, hooks.ability(attacker, "before_move", move, attacker, side, turn))
    if move.damaging and weather.lasting and weather.kind and move.type == PRIMAL_DOUSED.get(weather.kind):
        return Action(turn, side, *names, move.name, failed=True, weather=weather.kind, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent)
    stopped = _stopped(attacker, defender, move)
    if stopped:
        absorbed = hooks.ability(defender, "absorbs", move, defender, 1 - side, default=()) if (
            stopped == defender.ability) else ()
        changes = tuple(change for answer in _field(defender, "punishes", move, attacker, side, rng)
                        for change in answer) + tuple(absorbed) + _crash(attacker, move)
        return Action(turn, side, *names, move.name, failed=True, blocked=stopped, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent, changes=changes,
                      attacker_fainted=attacker.hp == 0)
    if _dodges(attacker, defender, move):
        return Action(turn, side, *names, move.name, missed=True, recovered=recovered, defender_hp=defender.hp_percent,
                      attacker_hp=attacker.hp_percent, changes=_crash(attacker, move),
                      attacker_fainted=attacker.hp == 0)
    used = hooks.move(move, "use", attacker, defender, side, turn, weather, arena, rng)
    if used is not None:
        return Action(turn, side, *names, move.name, recovered=recovered, defender_hp=defender.hp_percent,
                      attacker_hp=attacker.hp_percent, **used)
    hooks.move(move, "before_hit", attacker, defender)
    multiplier = _multiplier(move, defender, weather.kind)
    accuracy = hooks.move(move, "own_accuracy", attacker, defender)
    if accuracy is None:
        accuracy = _accuracy(attacker, defender, move)
    checks_accuracy = (move.accuracy is not None and not hooks.move(move, "skips_accuracy", weather.kind, default=False)
                       and not _sure_hit(attacker, defender))
    if checks_accuracy and rng.random() * 100 >= accuracy:
        crash = _crash(attacker, move)
        return Action(turn, side, *names, move.name, missed=True, multiplier=multiplier, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent, changes=crash,
                      attacker_fainted=attacker.hp == 0)
    if multiplier == 0:
        granted = hooks.ability(defender, "immune_to", move, defender, default=False) and effectiveness(
            move.type, defender.combatant.types) > 0
        crash = _crash(attacker, move)
        return Action(turn, side, *names, move.name, multiplier=0, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent,
                      ability=defender.ability if granted else None, changes=crash,
                      attacker_fainted=attacker.hp == 0)
    critical, hits, dealt, sturdy, endured, berry, shielded = False, 0, 0, False, "", "", False
    hooks.move(move, "draws", attacker, rng)
    fixed = hooks.move(move, "fixed_damage", attacker, defender, rng)
    resisted = defender.item if fixed is None and hooks.item(defender, "resists", move.type, multiplier,
                                                             default=False) else ""
    crit_stage = (hooks.move(move, "crit_stage", default=move.crit_stage) + hooks.item(attacker, "crit_stage", default=0)
                  + sum(_field(attacker, "crit_stage")) + hooks.ability(attacker, "crit_stage", default=0))
    if hooks.ability(attacker, "always_crits", defender, default=False):
        crit_stage = len(CRITICAL_CHANCES) - 1
    no_crit = any(_field(defender, "guards_crit")) or hooks.ability(defender, "guards_crit", default=False)
    hit_count = _hit_count(move, attacker, rng)
    rolls_each_hit = (checks_accuracy and hooks.move(move, "rolls_each_hit", default=False)
                      and not hooks.ability(attacker, "skips_hit_rolls", default=False))
    for hit in range(hit_count):
        if hit > 0 and rolls_each_hit and rng.random() * 100 >= accuracy:
            break
        if fixed is None:
            hit_critical = rng.random() < CRITICAL_CHANCES[min(crit_stage, len(CRITICAL_CHANCES) - 1)] and not no_crit
            damage = _damage(attacker, defender, move, multiplier, hit_critical, weather.kind, rng, hit)
        else:
            hit_critical, damage = False, fixed
        if resisted and hit == 0:
            damage, defender.item = max(1, int(damage * items.RESIST_BERRY_MULTIPLIER)), None
            defender.ate_berry = True
        if any(_field(defender, "takes_hit", damage, attacker, defender, move)):
            hits, critical, shielded = hits + 1, critical or hit_critical, True
            continue
        if hooks.ability(defender, "takes_hit", damage, attacker, defender, move, default=False):
            hits, critical = hits + 1, critical or hit_critical
            continue
        damage = min(defender.hp, damage)
        lethal, from_full, held = damage >= defender.hp, defender.hp == defender.max_hp > 1, defender.item
        if lethal and hooks.move(move, "spares", default=False):
            damage = defender.hp - 1
        elif lethal and any(_field(defender, "endures", defender, from_full, rng)):
            damage = defender.hp - 1
        elif lethal and hooks.ability(defender, "endures", defender, from_full, rng, default=False):
            damage, sturdy = defender.hp - 1, True
        elif lethal and hooks.item(defender, "endures", defender, from_full, rng, default=False):
            damage, endured = defender.hp - 1, held
        defender.hp -= damage
        defender.times_hit += 1
        defender.hit_by_foe = defender.hit_by_foe or damage > 0
        critical, hits, dealt = critical or hit_critical, hits + 1, dealt + damage
        if damage > 0 and makes_contact(attacker, move):
            attacker.hp = max(0, attacker.hp - (0 if _chip_free(attacker) else hooks.item(
                defender, "on_contact_hit", attacker, default=0)))
        if defender.hp == 0 or attacker.hp == 0:
            break
        held = defender.item
        if hit < hit_count - 1 and hooks.item(defender, "between_hits", defender, default=False):
            berry = held
    if dealt > 0:
        defender.hurt = Hurt(move.physical, dealt, makes_contact(attacker, move))
    if defender.hp == 0:
        _field(defender, "on_knocked_out", attacker, move, turn, side)
    changes, ability = (), defender.ability if sturdy else None
    if defender.hp > 0 and (not shielded or move.stat_on_user):
        changes, blocked_by = _secondary_effects(side, move, attacker, defender, rng)
        defender.ability_ignored = False
        contact = None if shielded else _contact_effect(side, move, attacker, defender, rng)
        if contact:
            changes, ability = (*changes, contact), defender.ability
        ability = ability or blocked_by
    recoil, drained = move is STRUGGLE, move.drain > 0
    if recoil:
        attacker.hp = max(0, attacker.hp - max(1, attacker.max_hp // STRUGGLE_RECOIL_FRACTION))
    elif move.drain < 0 and not _recoil_free(attacker):
        attacker.hp = max(0, attacker.hp - max(1, dealt * -move.drain // 100))
        recoil = True
    elif drained:
        healed = max(1, dealt * move.drain // 100)
        healed = hooks.item(attacker, "modify_drain", healed, default=healed)
        if hooks.ability(defender, "inverts_drain", default=False):
            drained = False
            attacker.hp = max(0, attacker.hp - (0 if _chip_free(attacker) else healed))
            _announce(defender, AbilityAct(turn, 1 - side, defender.combatant.name, defender.ability,
                                           foe=attacker.combatant.name, foe_hp=attacker.hp_percent,
                                           foe_fainted=attacker.hp == 0))
        else:
            attacker.hp = min(attacker.max_hp, attacker.hp + healed)
    attacker_item = _attacker_item_effect(attacker, move, dealt, drained)
    defender_item = endured or _defender_item_effect(defender, attacker, move, multiplier, dealt) or berry or resisted
    changes = (*changes, *(hooks.move(move, "after_move", attacker, defender, dealt) or ()))
    action = Action(
        turn, side, *names, move.name, multiplier=multiplier, critical=critical, changes=changes, recoil=recoil,
        defender_hp=defender.hp_percent, knockout=defender.hp == 0, attacker_fainted=attacker.hp == 0,
        recovered=recovered, hits=hits, drained=drained, attacker_hp=attacker.hp_percent, ability=ability,
        attacker_item=attacker_item, defender_item=defender_item,
    )
    if hits:
        defender.ability_ignored = False
        hit = Hit(side, turn, attacker, defender, move, dealt, hits, critical, multiplier, shielded, rng)
        _announce(defender, hooks.ability(defender, "after_hit", hit))
        _announce(attacker, hooks.ability(attacker, "after_hit_as_user", hit))
    return action


@dataclass(frozen=True)
class Hit:
    """A damaging move that hit, for the abilities that answer it once the move is over: `side` is the user's,
    `dealt` the damage past any Substitute (`shielded`), `hits` how many landed."""

    side: int
    turn: int
    user: "_Fighter"
    target: "_Fighter"
    move: Move
    dealt: int
    hits: int
    critical: bool
    multiplier: float
    shielded: bool
    rng: random.Random

    @property
    def contact(self) -> bool:
        return makes_contact(self.user, self.move)


def _announce(fighter: "_Fighter", event) -> None:
    """Logs what an ability did mid-action, shown after the action."""
    if event is not None and fighter.arena is not None:
        _append(fighter.arena.log, event)


def _unnerved(fighter: "_Fighter", item: str) -> bool:
    """A foe's ability keeps `fighter` from eating its berry (Unnerve)."""
    if not item.endswith("-berry") or fighter.arena is None:
        return False
    foe = fighter.arena.foe_of(fighter)
    return foe is not None and foe is not fighter and foe.hp > 0 and hooks.ability(foe, "unnerves", default=False)


def _chip_free(fighter: "_Fighter") -> bool:
    """Only a move's own hits hurt the Pokémon: no status, weather, hazard, recoil or item chip (Magic Guard)."""
    return hooks.ability(fighter, "blocks_indirect", default=False)


def _recoil_free(fighter: "_Fighter") -> bool:
    return _chip_free(fighter) or hooks.ability(fighter, "blocks_recoil", default=False)


def _weather_of(fighter: "_Fighter") -> str | None:
    return fighter.arena.weather.kind if fighter.arena is not None else None


def _crash(attacker: _Fighter, move: Move) -> tuple[Change, ...]:
    crash = hooks.move(move, "crashes", attacker)
    return () if crash is None else (crash,)


def _weather_of(fighter: "_Fighter") -> str | None:
    return fighter.arena.weather.kind if fighter.arena is not None else None


def _weight(fighter: "_Fighter") -> float:
    return fighter.combatant.weight * hooks.ability(fighter, "modify_weight", default=1.0)


def _retyped(attacker: _Fighter, move: Move) -> Move:
    """A state that changes the type of the user's move (Electrify, Ion Deluge)."""
    kind = next(iter(_field(attacker, "retypes_move", move)), None)
    return move if kind is None else replace(move, type=kind)


def _attacker_item_effect(attacker: _Fighter, move: Move, dealt: int, drained: bool) -> str:
    """The user's item that acted after its move (Life Orb, Shell Bell, Big Root), or ""."""
    item = attacker.item
    if dealt <= 0 or move is STRUGGLE or item is None:
        return ""
    return item if hooks.item(attacker, "after_move_as_user", attacker, move, dealt, drained, default=False) else ""


def _defender_item_effect(defender: _Fighter, attacker: _Fighter, move: Move, multiplier: float, dealt: int) -> str:
    """The target's item that acted on the move (Rocky Helmet, already applied per hit; Weakness Policy), or ""."""
    item = defender.item
    acted = hooks.item(defender, "after_move_as_target", defender, attacker, move, multiplier, dealt, default=False)
    return item if acted else ""


def makes_contact(attacker: _Fighter, move: Move) -> bool:
    """The move touches its target (Showdown's contact flag), unless the user's ability or item says it does not."""
    return (move.flagged("contact") and not hooks.ability(attacker, "drops_contact", default=False)
            and not hooks.item(attacker, "drops_contact", move, default=False))


def _start_of_action(attacker: _Fighter, move: Move, rng: random.Random) -> tuple[tuple[str, ...], str]:
    """What ended before the Pokémon acts, and what stops it from using its move ("" if nothing)."""
    recovered: list[str] = []
    if attacker.status == "sleep":
        if attacker.sleep_left > 0:
            attacker.sleep_left -= 1
            if not hooks.move(move, "acts_asleep", default=False):
                return (), "sleep"
        else:
            attacker.status = None
            recovered.append("sleep")
    elif attacker.status == "freeze":
        thawed = (rng.random() < FREEZE_THAW_CHANCE or move.type == "fire"
                  or hooks.move(move, "thaws_user", default=False))
        if not thawed:
            return (), "freeze"
        attacker.status = None
        recovered.append("freeze")
    banned = _banned(attacker, move)
    if banned:
        return tuple(recovered), banned
    if attacker.confusion_left > 0:
        attacker.confusion_left -= 1
        if attacker.confusion_left == 0:
            recovered.append("confusion")
        elif rng.random() < CONFUSION_SELF_HIT_CHANCE:
            return tuple(recovered), "confusion"
    if attacker.status == "paralysis" and rng.random() < FULL_PARALYSIS_CHANCE:
        return tuple(recovered), "paralysis"
    return tuple(recovered), ""


def _hit_count(move: Move, attacker: _Fighter, rng: random.Random) -> int:
    counted = hooks.move(move, "hit_count", attacker)
    if counted is None:
        counted = hooks.ability(attacker, "hit_count", move)
    if counted is not None:
        return counted
    if move.max_hits <= 1:
        return 1
    if (move.min_hits, move.max_hits) == (2, 5):
        return rng.choices(list(MULTI_HIT_ODDS), weights=list(MULTI_HIT_ODDS.values()))[0]
    return rng.randint(move.min_hits, move.max_hits)


def _damage(attacker: _Fighter, defender: _Fighter, move: Move, multiplier: float, critical: bool,
            weather: str | None, rng: random.Random, hit: int | None = None) -> int:
    damage = _unrolled_damage(attacker, defender, move, multiplier, weather, hit, critical)
    damage *= (CRITICAL_MULTIPLIER if critical else 1.0) * rng.randint(85, 100) / 100
    return max(1, int(damage))


def _unrolled_damage(attacker: _Fighter, defender: _Fighter, move: Move, multiplier: float,
                     weather: str | None, hit: int | None = None, critical: bool = False) -> float:
    """`move` is already `move_power.typed`; `hit` is the 0-based hit of a multi-hit move (None: the mean hit)."""
    attack, defense = _stats_for(attacker, defender, move, weather)
    level = attacker.combatant.level
    power = _power(attacker, defender, move, weather, multiplier, hit)
    damage = ((2 * level // 5 + 2) * power * attack / max(1, defense)) // DAMAGE_DIVISOR + 2
    return (
        damage * _stab(attacker, move) * multiplier * _weather_boost(move, weather)
        * _damage_taken(attacker, defender, move, multiplier, critical) * _item_boost(attacker, move, multiplier)
        * _screen(attacker, defender, move, critical) * _exposed(attacker, defender)
    )


def _screen(attacker: _Fighter, defender: _Fighter, move: Move, critical: bool) -> float:
    """The strongest screen on the defender's side (Aurora Veil does not stack with Reflect or Light Screen). A critical
    hit, a hit on itself (confusion) and an Infiltrator pass it."""
    screens = _field(defender, "screen", move)
    if not screens or critical or attacker is defender or _infiltrates(attacker):
        return 1.0
    return min(screens)


def _exposed(attacker: _Fighter, defender: _Fighter) -> float:
    return 1.0 if attacker is defender else math.prod(_field(defender, "takes_more", attacker))


def _infiltrates(fighter: _Fighter) -> bool:
    return hooks.ability(fighter, "infiltrates", default=False)


def _secondary_effects(side: int, move: Move, attacker: _Fighter, defender: _Fighter,
                       rng: random.Random) -> tuple[tuple[Change, ...], str | None]:
    """The effects that landed, and the defender's ability if it stopped the move's ailment."""
    changes: list[Change] = []
    blocked_by = None
    if _ailment_lands(move, attacker, defender, rng):
        if _blocks_ailment(defender, move.ailment):
            blocked_by = defender.ability
        else:
            changes.append(_inflict(move.ailment, defender, 1 - side, rng))
    if defender.status == "freeze" and (move.type == "fire" or hooks.move(move, "thaws_user", default=False)):
        defender.status = None
        changes.append(Change(1 - side, defender.combatant.name, "thaw"))
    if move.stat_changes and rng.random() * 100 < move.stat_chance * _chance_scale(
            move, attacker, None if move.stat_on_user else defender):
        target, target_side = (attacker, side) if move.stat_on_user else (defender, 1 - side)
        guarded = not move.stat_on_user and _stats_guarded(defender, not _infiltrates(attacker))
        for key, stages in move.stat_changes:
            change = shift_stage(target, target_side, key, stages, guarded=guarded,
                                 by=None if move.stat_on_user else attacker)
            if change is not None:
                changes.append(change)
    changes.extend(hooks.move(move, "secondary", attacker, defender, side, rng, default=()))
    return tuple(changes), blocked_by


def shift_stage(fighter: _Fighter, side: int, key: str, stages: int, *, guarded: bool = False,
                by: "_Fighter | None" = None) -> Change | None:
    """Moves one stat stage within ±6 after its holder's ability scales it (Contrary, Simple); the `Change` that
    landed, None when none did. A drop is stopped when `guarded` (Mist); `by` is the foe lowering it, and the holder's
    ability may keep the stat (Clear Body), bounce the drop back at `by` (Mirror Armor) or answer it (Defiant)."""
    stages *= hooks.ability(fighter, "stage_factor", default=1)
    if guarded and stages < 0:
        return None
    by_foe = by is not None and by is not fighter and stages < 0
    if by_foe and hooks.ability(fighter, "guards_stat", key, fighter, default=False):
        _ability_act(fighter, effect="guard")
        return None
    if by_foe and hooks.ability(fighter, "reflects_drop", default=False):
        _ability_act(fighter, changes=tuple(filter(None, (shift_stage(by, 1 - side, key, stages),))))
        return None
    before = fighter.stages[key]
    fighter.stages[key] = max(-MAX_STAGE, min(MAX_STAGE, before + stages))
    if fighter.stages[key] == before:
        return None
    fighter.lowered = fighter.lowered or fighter.stages[key] < before
    change = Change(side, fighter.combatant.name, key, fighter.stages[key] - before)
    if by_foe:
        _announce(fighter, hooks.ability(fighter, "on_stat_lowered", fighter, side))
    return change


def _ability_act(fighter: _Fighter, **details) -> None:
    """Logs `fighter`'s ability acting mid-turn (`AbilityAct` fields in `details`)."""
    if fighter.arena is not None:
        fighter.arena.log.append(AbilityAct(fighter.arena.turn, fighter.side, fighter.combatant.name,
                                            fighter.ability or fighter.combatant.ability, **details))


def _contact_effect(side: int, move: Move, attacker: _Fighter, defender: _Fighter,
                    rng: random.Random) -> Change | None:
    return hooks.ability(defender, "on_contact", side, move, attacker, defender, rng)


def _ailment_lands(move: Move, attacker: _Fighter, defender: _Fighter, rng: random.Random) -> bool:
    if move.ailment not in AILMENT_IMMUNE_TYPES:
        return False
    return (_open_to(move.ailment, defender, not _infiltrates(attacker))
            and rng.random() * 100 < move.ailment_chance * _chance_scale(move, attacker, defender))


def _chance_scale(move: Move, attacker: _Fighter, defender: _Fighter | None) -> float:
    """Scales the chance of a move's added effect: the user's ability (Serene Grace, Sheer Force), and the target's
    when the effect lands on it (Shield Dust)."""
    if defender is not None and hooks.ability(defender, "blocks_secondary", default=False):
        return 0.0
    return hooks.ability(attacker, "secondary_chance", move, default=1.0)


def _open_to(ailment: str, fighter: _Fighter, by_foe: bool = False) -> bool:
    """Whether `fighter` can get `ailment` now. `by_foe`: a foe inflicts it and its side's guards (Safeguard) count."""
    if any(kind in fighter.combatant.types for kind in AILMENT_IMMUNE_TYPES[ailment]):
        return False
    if any(_field(fighter, "guards_ailment", ailment, fighter, by_foe)):
        return False
    return fighter.confusion_left == 0 if ailment == "confusion" else fighter.status is None


def _stats_guarded(fighter: _Fighter, by_foe: bool = True) -> bool:
    """Whether a foe cannot lower `fighter`'s stats now (Mist)."""
    return by_foe and any(_field(fighter, "guards_stats"))


def _inflict(ailment: str, defender: _Fighter, side: int, rng: random.Random) -> Change:
    if ailment == "confusion":
        defender.confusion_left = rng.randint(*CONFUSION_TURNS)
    else:
        defender.status = ailment
        defender.toxic_ticks = 0
        if ailment == "sleep":
            defender.sleep_left = rng.randint(*SLEEP_TURNS)
    return Change(side, defender.combatant.name, ailment)


def _choose(teams: tuple["_Team", "_Team"], side: int, arena: _Arena, weather: str | None) -> int | None:
    """The move `side`'s active Pokémon uses this turn, by one rule for both sides. First an effect move whose moment
    has come: Trick Room on its first turn in when its team is slower than the foe and none has been set, Stealth Rock
    once while the foe has members to come, Swords Dance once per entry above half HP and below +6 Attack, Yawn on a
    foe with no status, Thunder Wave on a faster foe it can
    paralyze, then the field and side moves by their own `wanted` (a screen once on entry, each hazard until its
    layers are full, a terrain that helps it, Rapid Spin or Defog to clear its own hazards). A self-KO move only when it surely knocks the foe out (and no other move does) or the user is at 1/3 HP
    or less, never by the side's last member. Then a pivot move when the foe has a
    super-effective hit on it and a member of its group can come in. Otherwise `_best_move`."""
    team, foes = teams[side], teams[1 - side]
    attacker, defender = team.active, foes.active
    forced = next(iter(_field(attacker, "forces_move", attacker)), None)
    if forced is not None:
        return forced
    best = _best_move(attacker, defender, weather)
    self_ko = _usable(attacker, "self-ko")
    if best is None and attacker.locked is None and self_ko is not None:
        return self_ko
    if self_ko is not None and team.has_next and attacker.locked is None and (
        _surely_finishes(attacker, defender, attacker.combatant.moves[self_ko], weather)
        or attacker.hp * abilities.LOW_HP_FRACTION <= attacker.max_hp
    ) and not (best is not None and _surely_finishes(attacker, defender, attacker.combatant.moves[best], weather)):
        return self_ko
    if attacker.locked is not None or hooks.item(attacker, "bars_status_moves", default=False):
        return best
    if best is not None and _surely_finishes(attacker, defender, attacker.combatant.moves[best], weather):
        return best
    for effect in (*STATUS_EFFECTS, *CHOSEN_DAMAGE_EFFECTS):
        for index in _with_effect(attacker, effect):
            move = attacker.combatant.moves[index]
            if not _banned(attacker, move) and not _wasted_on(attacker, defender, move) and hooks.move(
                    move, "wanted", team, foes, side, arena, weather, default=False):
                return index
    pivot = _usable(attacker, "pivot")
    if pivot is not None and team.pivot_target() is not None and _threatened(attacker, defender, weather):
        return pivot
    if best is None:
        return next((index for index in range(len(attacker.combatant.moves)) if attacker.pp[index] > 0), None)
    return best


def _paralyzable(move: Move, fighter: _Fighter, by_foe: bool = True) -> bool:
    """Thunder Wave fails on a Pokémon with a status, an Electric type, one its type cannot touch (Ground), one a
    state guards or an ability that blocks paralysis."""
    return (_open_to("paralysis", fighter, by_foe) and effectiveness(move.type, fighter.combatant.types) > 0
            and not _blocks_ailment(fighter, "paralysis"))


def _yawnable(fighter: _Fighter, by_foe: bool = True) -> bool:
    return (_open_to("sleep", fighter, by_foe) and not fighter.drowsy_at
            and not _blocks_ailment(fighter, "sleep"))


def _blocks_ailment(fighter: _Fighter, ailment: str) -> bool:
    """`fighter`'s ability keeps `ailment` off it (Insomnia; Leaf Guard in sun)."""
    return hooks.ability(fighter, "blocks_ailment", ailment, fighter, default=False)


def _usable(fighter: _Fighter, effect: str) -> int | None:
    return next(iter(_with_effect(fighter, effect)), None)


def _with_effect(fighter: _Fighter, effect: str) -> list[int]:
    return [index for index, move in enumerate(fighter.combatant.moves) if move.effect == effect and fighter.pp[index] > 0]


def _threatened(fighter: _Fighter, foe: _Fighter, weather: str | None) -> bool:
    """Whether `foe` has a super-effective damaging move with PP against `fighter`."""
    return any(_multiplier(move_power.typed(move, weather, foe), fighter, weather) > 1
               for index, move in enumerate(foe.combatant.moves)
               if foe.pp[index] > 0 and move.damaging)


def _best_move(attacker: _Fighter, defender: _Fighter, weather: str | None) -> int | None:
    """Index of the move to use; None means Struggle.

    The damaging move with PP left and the highest score, unless a weather move swings the exchange and no
    damaging move is sure to finish the foe. A Choice item holder repeats its first move until it runs out of
    PP and never starts with a weather move.
    """
    if attacker.locked is not None:
        return attacker.locked if attacker.pp[attacker.locked] > 0 else None
    best, best_score = None, -1.0
    for index, move in enumerate(attacker.combatant.moves):
        if attacker.pp[index] <= 0 or move.weather or move.effect in STATUS_EFFECTS or move.effect == "self-ko":
            continue
        score = _move_score(attacker, defender, move, weather)
        if score > best_score:
            best, best_score = index, score
    if hooks.item(attacker, "bars_status_moves", default=False) or (
        best is not None and _surely_finishes(attacker, defender, attacker.combatant.moves[best], weather)
    ):
        return best
    setter = _best_weather_move(attacker, defender, weather)
    return best if setter is None else setter


def _surely_finishes(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None) -> bool:
    """Whether a hit with the lowest damage roll that cannot miss knocks the defender out."""
    move = move_power.typed(move, weather, attacker)
    never_misses = move.accuracy in (None, 100) or hooks.move(move, "skips_accuracy", weather, default=False)
    multiplier = _multiplier(move, defender, weather)
    fixed = hooks.move(move, "fixed_damage", attacker, defender, None)
    if fixed is None:
        lowest = _unrolled_damage(attacker, defender, move, multiplier, weather) * LOWEST_ROLL
    else:
        lowest = fixed if multiplier > 0 else 0
    return (never_misses and lowest >= defender.hp and not _banned(attacker, move)
            and not _stopped(attacker, defender, move) and not hooks.move(move, "spares", default=False)
            and not hooks.move(move, "fails", attacker, defender, default=False))


def _best_weather_move(attacker: _Fighter, defender: _Fighter, weather: str | None) -> int | None:
    best, best_swing = None, WEATHER_SWING_MIN
    for index, move in enumerate(attacker.combatant.moves):
        if attacker.pp[index] > 0 and move.weather and weather not in (move.weather, STRONG_WINDS):
            swing = _weather_swing(attacker, defender, weather, move.weather)
            if swing >= best_swing:
                best, best_swing = index, swing
    return best


def _weather_swing(attacker: _Fighter, defender: _Fighter, now: str | None, new: str) -> float:
    """How much better the exchange gets for `attacker` if `new` replaces `now`: damage ratio × chip damage asymmetry."""
    mine = _best_score(attacker, defender, new) / max(1.0, _best_score(attacker, defender, now))
    theirs = max(1.0, _best_score(defender, attacker, now)) / max(1.0, _best_score(defender, attacker, new))
    chip = (_chipped_by(defender, new) - _chipped_by(defender, now)) - (_chipped_by(attacker, new) - _chipped_by(attacker, now))
    return mine * theirs * WEATHER_CHIP_SWING ** chip


def _best_score(attacker: _Fighter, defender: _Fighter, weather: str | None) -> float:
    scores = [
        _move_score(attacker, defender, move, weather)
        for index, move in enumerate(attacker.combatant.moves)
        if attacker.pp[index] > 0 and not move.weather and move.effect not in (*STATUS_EFFECTS, "self-ko")
    ]
    return max(scores, default=0.0)


def _move_score(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None) -> float:
    """Power × STAB × type × weather × accuracy × attack/defense × the share a turn gets of a move that takes two
    (`score_share`); 0 for a move a state bans or stops, one that cannot reach the hiding foe, one expected to fail,
    or one a sleeping user cannot use while it knows one it can (Snore). A move with set damage scores the power that
    would deal that damage at even attack and defense."""
    move = move_power.typed(move, weather, attacker)
    with _ability_ignored(attacker, defender, move):
        if (_banned(attacker, move) or _stopped(attacker, defender, move) or _dodges(attacker, defender, move)
                or hooks.move(move, "fails", attacker, defender, default=False)
                or hooks.move(move, "wasted", attacker, defender, default=False) or _sleeps_through(attacker, move)):
            return 0.0
        return (_damage_score(attacker, defender, move, weather) * hooks.move(move, "score_share", weather, default=1.0)
                * _hp_kept(attacker, defender, move, weather))


def _damage_score(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None) -> float:
    attack, defense = _stats_for(attacker, defender, move, weather)
    skips = move.accuracy is None or hooks.move(move, "skips_accuracy", weather, default=False)
    accuracy = 100 if skips else hooks.move(move, "own_accuracy", attacker, defender, default=move.accuracy)
    multiplier = _multiplier(move, defender, weather)
    fixed = hooks.move(move, "fixed_damage", attacker, defender, None)
    if fixed is not None:
        return fixed * (multiplier > 0) * accuracy * DAMAGE_DIVISOR / (2 * attacker.combatant.level // 5 + 2)
    return (
        _power(attacker, defender, move, weather, multiplier) * _expected_hits(move, attacker, accuracy)
        * _stab(attacker, move) * multiplier
        * _weather_boost(move, weather) * _damage_taken(attacker, defender, move, multiplier, False)
        * _item_boost(attacker, move, multiplier)
        * accuracy * attack / max(1, defense) * _screen(attacker, defender, move, False) * _exposed(attacker, defender)
    )


def _hp_kept(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None) -> float:
    """The share of its HP the user keeps after the recoil and HP cost it expects the move to take (Brave Bird,
    Steel Beam)."""
    paid = hooks.move(move, "hp_paid", attacker, default=0)
    if move.drain < 0:
        dealt = _unrolled_damage(attacker, defender, move, _multiplier(move, defender, weather), weather)
        paid += min(defender.hp, dealt) * -move.drain / 100
    return max(0.0, 1 - paid / max(1, attacker.hp))


def _sleeps_through(attacker: _Fighter, move: Move) -> bool:
    if attacker.status != "sleep" or attacker.sleep_left == 0 or _acts_asleep(move):
        return False
    return any(_acts_asleep(known) for known in attacker.combatant.moves)


def _acts_asleep(move: Move) -> bool:
    return hooks.move(move, "acts_asleep", default=False)


def _expected_hits(move: Move, attacker: _Fighter, accuracy: float) -> float:
    """Hits that each draw for accuracy count only while every earlier one landed."""
    if accuracy < 100 and hooks.move(move, "rolls_each_hit", default=False):
        return sum((accuracy / 100) ** hit for hit in range(move.max_hits))
    expected = hooks.ability(attacker, "expected_hits", move, default=move.expected_hits)
    return hooks.move(move, "hit_count", attacker, default=expected)


def _damage_taken(attacker: _Fighter, defender: _Fighter, move: Move, multiplier: float, critical: bool) -> float:
    if attacker is defender:
        return 1.0
    return (hooks.ability(defender, "modify_damage_taken", move, multiplier, defender, attacker, default=1.0)
            * hooks.ability(attacker, "modify_damage_dealt", move, multiplier, critical, attacker, defender,
                            default=1.0))


def _item_boost(attacker: _Fighter, move: Move, multiplier: float) -> float:
    if move is STRUGGLE:
        return 1.0
    punch = move.id in PUNCH_MOVES
    return hooks.item(attacker, "modify_damage", move.type, multiplier, move.physical, punch, default=1.0)


def _weather_boost(move: Move, weather: str | None) -> float:
    boost = WEATHER_MOVE_BOOST.get(weather, {}).get(move.type, 1.0)
    return hooks.move(move, "modify_weather_boost", weather, boost, default=boost)


def _power(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None, multiplier: float,
           hit: int | None = None) -> float:
    """The move's power in this battle state (`move_power`), then the attacker's ability on that power, the field, and
    a target hiding where the move reaches it (Earthquake on Dig)."""
    if move is STRUGGLE or move is CONFUSION_HIT:
        return move.power
    power = move_power.power(move, attacker, defender, weather, multiplier, hit)
    extra_hit = hooks.ability(attacker, "extra_hit_power", default=1.0) if hit and move.max_hits <= 1 else 1.0
    return power * (hooks.ability(attacker, "modify_power", move, power, attacker, defender, weather, default=1.0)
                    * hooks.ability(defender, "modify_foe_power", move, defender, default=1.0)) * math.prod(
        _field(attacker, "field_power", move, attacker, defender)) * (_hidden(defender, move) or 1.0) * extra_hit


def _stab(attacker: _Fighter, move: Move) -> float:
    if move.type not in attacker.combatant.types:
        return 1.0
    return hooks.ability(attacker, "modify_stab", default=STAB_MULTIPLIER)


def _multiplier(move: Move, defender: _Fighter, weather: str | None = None) -> float:
    """Strong winds take away the Flying type's weaknesses. A state that grounds the defender (Gravity) lets a Ground
    move hit it through its Flying type and its airborne ability."""
    if move.type is None:
        return 1.0
    forced_down = move.type == "ground" and (any(_field(defender, "grounds"))
                                             or hooks.move(move, "hits_airborne", default=False))
    if not forced_down and hooks.ability(defender, "immune_to", move, defender, default=False):
        return 0.0
    if not forced_down and move.type == "ground" and any(_field(defender, "lifts")):
        return 0.0
    types = defender.combatant.types
    if forced_down or weather == STRONG_WINDS and effectiveness(move.type, ("flying",)) > 1:
        types = tuple(kind for kind in types if kind != "flying")
    exposed = set(_field(defender, "exposes", move.type))
    foe = defender.arena.foe_of(defender) if defender.arena is not None else None
    if foe is not None and foe is not defender:
        exposed |= {hooks.ability(foe, "exposes", move.type)} - {None}
    if exposed:
        types = tuple(kind for kind in types if kind not in exposed or effectiveness(move.type, (kind,)) > 0)
    return (effectiveness(move.type, types) * hooks.move(move, "type_multiplier", types, default=1.0)
            * math.prod(_field(defender, "weakens", move.type)))


def _field(fighter: _Fighter, hook: str, *args) -> list:
    """The answers of the field and side states acting on `fighter`'s side, then of its own states (`volatiles`),
    that run `hook`, None left out."""
    arena = fighter.arena
    states = (*(arena.states(fighter.side) if arena is not None else ()), *fighter.volatiles)
    return [answer for state in states if (answer := hooks.key("moves", state, hook, *args)) is not None]


def _grounded(fighter: _Fighter) -> bool:
    """A Flying type, an airborne ability (Levitate) or a lifting state (Magnet Rise) floats unless a state grounds it
    (Gravity, Ingrain)."""
    if any(_field(fighter, "grounds")):
        return True
    return ("flying" not in fighter.combatant.types and not hooks.ability(fighter, "airborne", default=False)
            and not any(_field(fighter, "lifts")))


def _banned(fighter: _Fighter, move: Move) -> str:
    """The state that keeps `fighter` from using `move` at all ("gravity", "taunt"), or ""."""
    return next(iter((*_field(fighter, "bans_move", move, fighter),
                      *_foe_field(fighter, "bans_foe_move", move, fighter))), "")


def _foe_field(fighter: _Fighter, hook: str, *args) -> list:
    """The answers of the states on the foe facing `fighter` (Imprison) that run `hook`."""
    foe = fighter.arena.foe_of(fighter) if fighter.arena is not None else None
    if foe is None:
        return []
    return [answer for state in foe.volatiles if (answer := hooks.key("moves", state, hook, *args)) is not None]


def _accuracy(attacker: _Fighter, defender: _Fighter, move: Move) -> float:
    return ((move.accuracy or 0) * _accuracy_stages(attacker, defender, move)
            * (hooks.item(attacker, "accuracy_as_user", default=1.0)
               * hooks.item(defender, "accuracy_as_target", default=1.0)) * math.prod(_field(attacker, "modify_accuracy"))
            * hooks.ability(attacker, "accuracy_as_user", move, default=1.0)
            * hooks.ability(defender, "accuracy_as_target", move, defender, default=1.0))


def _accuracy_stages(attacker: _Fighter, defender: _Fighter, move: Move | None = None) -> float:
    """The user's accuracy stage less the target's evasion stage, on the Gen 9 thirds table. A state that exposes the
    target (Foresight) drops its raised evasion, and a move that ignores stages (Sacred Sword) any evasion, and so does
    a user's ability that ignores evasion (Keen Eye) or every foe stage (Unaware). A target's Unaware ignores the
    user's accuracy stage."""
    ignores = (move is not None and _ignores_stages(move) or hooks.ability(attacker, "ignores_evasion", default=False)
               or hooks.ability(attacker, "ignores_foe_stages", default=False))
    evasion = 0 if ignores else defender.stages["evasion"]
    if evasion > 0 and any(_field(defender, "exposes", None)):
        evasion = 0
    accuracy = 0 if hooks.ability(defender, "ignores_foe_stages", default=False) else attacker.stages["accuracy"]
    stage = max(-MAX_STAGE, min(MAX_STAGE, accuracy - evasion))
    return (3 + stage) / 3 if stage >= 0 else 3 / (3 - stage)


def _dodges(attacker: _Fighter, defender: _Fighter, move: Move) -> bool:
    aimed = move.damaging or hooks.move(move, "targets_foe", default=False)
    return aimed and _hidden(defender, move) == 0 and not _sure_hit(attacker, defender)


def _hidden(defender: _Fighter, move: Move) -> float:
    """0 when `defender` hides where `move` cannot reach it (Fly, Dig); otherwise the power multiplier of a move
    that reaches it there (Earthquake on Dig), 1 when it hides nowhere."""
    return math.prod(_field(defender, "hides", move, defender))


def _sure_hit(attacker: _Fighter, defender: _Fighter) -> bool:
    """A state on the target makes the user's move hit without a draw (Lock-On, Telekinesis), and so does No Guard on
    either side."""
    return (any(_field(defender, "sure_hit", attacker)) or hooks.ability(attacker, "sure_hits", default=False)
            or hooks.ability(defender, "sure_hits", default=False))


def _stopped(attacker: _Fighter, defender: _Fighter, move: Move) -> str:
    """The state or ability that makes `move` fail on `defender` once used ("psychic-terrain", "soundproof"), or
    ""."""
    priority = _move_priority(attacker, move)
    stopped = next(iter(_field(defender, "stops_move", move, priority, defender)), "")
    if stopped or attacker is defender:
        return stopped
    if hooks.ability(defender, "stops_move", move, priority, defender, attacker, default=False):
        return defender.ability
    if hooks.ability(attacker, "fails_against", move, defender, default=False):
        return attacker.ability
    return ""


def _wasted_on(attacker: _Fighter, defender: _Fighter, move: Move) -> bool:
    """The move would fail on the defender or its ability would bounce it back (Magic Bounce)."""
    bounced = hooks.move(move, "targets_foe", default=False) and hooks.ability(defender, "reflects", move,
                                                                              default=False)
    return bool(_stopped(attacker, defender, move)) or bounced


def _stats_for(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None = None) -> tuple[float, float]:
    """The user's Attack against the target's Defense for a physical move and the special pair otherwise, unless the
    move names its own (`stat_source`: Psyshock, Foul Play, Body Press). A burn halves any attack stat but Special
    Attack."""
    source, attack_key, defense_key = hooks.move(move, "stat_source", attacker, defender, weather, default=None) or (
        attacker, *STAT_PAIRS[move.physical])
    boosted = (DEFENSE_BOOSTED_TYPE if defense_key == "defense" else SPECIAL_DEFENSE_BOOSTED_TYPE).get(weather)
    boost = 1.5 if boosted in defender.combatant.types else 1.0
    halved = (attack_key != "special_attack" and attacker.status == "burn"
              and not hooks.ability(attacker, "ignores_burn", default=False) and not _ignores_burn(move))
    unaware = hooks.ability(attacker, "ignores_foe_stages", default=False)
    defense = defender.stat(defense_key, weather, staged=not _ignores_stages(move) and not unaware)
    attack = source.stat(attack_key, weather, staged=not hooks.ability(defender, "ignores_foe_stages", default=False))
    return attack * (0.5 if halved else 1.0), defense * boost


def _ignores_burn(move: Move) -> bool:
    return hooks.move(move, "ignores_burn", default=False)


def _ignores_stages(move: Move) -> bool:
    return hooks.move(move, "ignores_stages", default=False)


def _other_stat(base: int, iv: int, level: int) -> int:
    return (2 * base + iv) * level // 100 + 5
