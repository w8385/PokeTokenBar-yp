"""Automatic battle between rosters of up to three Pokémon, fought one at a time in order: base stats, level
(capped at 50), IVs, natures, type effectiveness and level-up moves with PP, priority, critical-hit stages,
multi-hit, drain and recoil, the major statuses (burn, paralysis, poison, toxic, sleep, freeze), confusion, stat
stages, five-turn weather, about twenty abilities and one held item per Pokémon, and the effect moves (Trick Room,
Yawn, Thunder Wave, the pivot moves) with the field and side states: terrains, Gravity, screens, Tailwind, Safeguard,
Mist, Lucky Chant and the entry hazards. Abilities, items, move effects and active states act through their handlers
in `ypoke.effects`, which this turn loop calls at the hook points of `effects.hooks.HOOKS`.
The next member comes in when one faints; the only other switch is a pivot move's. The first member of a side
holding its Mega Stone Mega Evolves at the start of its first turn, after its entry ability has acted; a Primal orb
reverts its holder as it enters.
This module is the turn loop; the events it logs live in `battle_events` and each Pokémon's state in `fighter`, and
both are importable from here too."""

import math
import random
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass, field, replace
from typing import NamedTuple

from ypoke import abilities, items, move_power, tera_forms
from ypoke.battle_events import (
    AbilityAct, AbilityEntry, AbilityField, AbilityRetype, AbilityTransform, AbilityTrigger, Action, BattleResult,
    Change, Event, FieldEnd, FieldStart, FormShift, HazardDamage, HazardHit, ItemEffect, ItemHeal, MegaEvolution,
    SendOut, StatusDamage, TerrainHeal, TrickRoomEnd, VolatileEnd, VolatileTick, WeatherDamage, WeatherEnd, YawnSleep,
)
from ypoke.effects import hooks
from ypoke.fighter import (
    _NATURE_NAMES, _NATURE_ORDER, BATTLE_STATS, BURN_DAMAGE_FRACTION, CARRIED_STATUSES, MULTI_HIT_ODDS,
    NATURE_MODIFIERS, POISON_DAMAGE_FRACTION, RESIDUAL_FRACTIONS, SLEEP_TURNS, STAGES, STATUS_EFFECTS, STRONG_WINDS,
    TOXIC_DAMAGE_FRACTION, WEATHER_MOVE_BOOST, BaseStats, Carry, Combatant, Hurt, MegaForm, Move, _announce, _append,
    _Arena, _carry_of, _field, _Fighter, _other_stat, _sheltered, _stats_of, _take_form, _Team, _Weather,
)
from ypoke.move_effects import CHOSEN_DAMAGE_EFFECTS, FLAGS, POWERLESS_ATTACKS, PUNCH_MOVES, STATUS_MOVES
from ypoke.type_chart import effectiveness

STAB_MULTIPLIER = 1.5
CRITICAL_MULTIPLIER = 1.5
DAMAGE_DIVISOR = 50
LOWEST_ROLL = 0.85
CRITICAL_CHANCES = (1 / 24, 1 / 8, 1 / 2, 1.0)
FULL_PARALYSIS_CHANCE = 0.25
STRUGGLE_RECOIL_FRACTION = 4
MAX_STAGE = 6
TURN_LIMIT = 300
BATTLE_LEVEL = 50
WEATHER_TURNS = 5
# Under Desolate Land's sun or Primordial Sea's rain, damaging moves of this type fail; Air Lock lifts it.
PRIMAL_DOUSED = {"sun": "water", "rain": "fire"}
WEATHER_CHIP_FRACTION = 16
WEATHER_CHIP_IMMUNE_TYPES = {"sandstorm": {"rock", "ground", "steel"}, "hail": {"ice"}}
SPECIAL_DEFENSE_BOOSTED_TYPE = {"sandstorm": "rock"}
DEFENSE_BOOSTED_TYPE = {"snow": "ice"}
STAT_PAIRS = {True: ("attack", "defense"), False: ("special_attack", "special_defense")}
WEATHER_SWING_MIN = 1.3
WEATHER_CHIP_SWING = 1.5
FREEZE_THAW_CHANCE = 0.2
CONFUSION_SELF_HIT_CHANCE = 1 / 3
CONFUSION_SELF_HIT_POWER = 40
CONFUSION_TURNS = (2, 5)
AILMENT_IMMUNE_TYPES = {
    "burn": ("fire",), "paralysis": ("electric",), "poison": ("poison", "steel"), "toxic": ("poison", "steel"),
    "freeze": ("ice",), "sleep": (), "confusion": (),
}
TRICK_ROOM_TURNS = 5
STEALTH_ROCK_FRACTION = 8
SWORDS_DANCE_STAGES = 2
END_OF_TURN = ("cures", "status", "weather", "terrain", "items", "abilities", "volatiles", "yawn", "sides", "trick-room",
               "rooms", "field", "winds", "replace")
STRUGGLE = Move("발버둥", None, 50, physical=True, id=165)
CONFUSION_HIT = Move("혼란", None, CONFUSION_SELF_HIT_POWER, physical=True)


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
    arena = _Arena(rng=rng)
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
            events.extend(_danced(turn, side, fighters, action, choices[side], weather, rng, arena))
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
                events.extend(answer)
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
    if weather.held and not any(
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
    the newcomer. The standing foe's ability answers each faint first (Soul-Heart). Returns the side that ran out,
    if any."""
    while True:
        entering = tuple(side for side in (0, 1) if teams[side].active.hp == 0)
        if not entering:
            return None
        loser = _exhausted(teams, entering)
        if loser is not None:
            return loser
        for side in entering:
            foe = teams[1 - side].active
            if foe.hp > 0:
                _append(events, hooks.ability(foe, "on_foe_fainted", foe))
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


def _enter_battle(fighters: tuple[_Fighter, _Fighter], weather: _Weather, rng: random.Random,
                  entering: tuple[int, ...] = (0, 1)) -> list[AbilityTrigger]:
    """Entry abilities of the `entering` sides fire faster Pokémon first, so the slower weather setter's weather stays."""
    order = entering
    speeds = [fighter.stat("speed") for fighter in fighters]
    if len(entering) == 2 and all(_entry_takes_turns(fighter) for fighter in fighters):
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


def _entry_takes_turns(fighter: _Fighter) -> bool:
    """Air Lock only announces itself on entry, so it leaves the entry order and its speed-tie draw alone."""
    return (hooks.has("abilities", fighter.ability, "on_entry")
            and not hooks.has("abilities", fighter.ability, "clears_weather"))


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
    return (hooks.ability(fighter, "moves_last", _chosen(fighter, choice), default=False)
            or hooks.item(fighter, "moves_last", default=False))


def _move_priority(fighter: _Fighter, move: Move) -> int:
    return (move.priority + hooks.ability(fighter, "modify_priority", move, fighter, default=0)
            + hooks.move(move, "modify_priority", fighter, default=0))


def _quick_claws(turn: int, fighters: tuple[_Fighter, _Fighter], choices: tuple[int | None, int | None],
                 weather: str | None, rng: random.Random, events: list[Event],
                 trick_room: bool = False) -> tuple[bool, bool]:
    """Which Quick Claw holders may move first this turn (20% each; no draw without the item). Only a claw that
    puts a holder that would move second ahead of a foe in the same priority bracket is logged, and so is a berry
    used up for it (Custap Berry)."""
    held = tuple(fighter.item for fighter in fighters)
    claws = tuple(hooks.item(fighter, "moves_first", fighter, rng, default=False) for fighter in fighters)
    for side, fighter in enumerate(fighters):
        if claws[side] and fighter.item != held[side]:
            events.append(ItemEffect(turn, side, fighter.combatant.name, held[side], "first"))
    drawn = tuple(not claw and hooks.ability(fighter, "moves_first", _chosen(fighter, choice), rng, default=False)
                  for fighter, choice, claw in zip(fighters, choices, claws))
    firsts = (claws[0] or drawn[0], claws[1] or drawn[1])
    if firsts[0] and firsts[1] or _priority(fighters[0], choices[0]) != _priority(fighters[1], choices[1]):
        return firsts
    for side, fighter in enumerate(fighters):
        mine, theirs = fighter.stat("speed", weather), fighters[1 - side].stat("speed", weather)
        if firsts[side] and (mine >= theirs if trick_room else mine <= theirs) and fighter.item == held[side]:
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
    if weather.held:
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
    """Abilities that follow the field (Forecast), then one-use items that react to the state a Pokémon is in: Sitrus
    Berry at half HP, Lum Berry on a status or confusion, White Herb on a lowered stat."""
    for side, fighter in enumerate(fighters):
        if fighter.hp > 0:
            _append(events, hooks.ability(fighter, "on_update", fighter, side, turn))
            _append(events, hooks.item(fighter, "on_update", fighter, side, turn))


def _weather_chip(fighter: _Fighter, weather: str | None) -> int:
    return max(1, fighter.max_hp // WEATHER_CHIP_FRACTION) if _chipped_by(fighter, weather) else 0


def _chipped_by(fighter: _Fighter, weather: str | None) -> bool:
    immune = WEATHER_CHIP_IMMUNE_TYPES.get(weather)
    return (immune is not None and not immune.intersection(fighter.combatant.types) and not _chip_free(fighter)
            and not hooks.ability(fighter, "blocks_weather_chip", weather, default=False)
            and not hooks.item(fighter, "blocks_weather_chip", default=False))


def _act(turn: int, side: int, fighters: tuple[_Fighter, _Fighter], index: int | None, weather: _Weather,
         rng: random.Random, arena: _Arena | None = None) -> Action:
    """One Pokémon's turn. A self-KO move (Explosion) faints its user once used, hit, miss or immune target, and an
    HP-cost move (Steel Beam) takes its share then too."""
    action = _resolve(turn, side, fighters, index, weather, rng, arena)
    user = fighters[side]
    tried = STRUGGLE if index is None else user.combatant.moves[index]
    _field(user, "after_own_move", user, _retyped(user, move_power.typed(tried, weather.kind, user)))
    if action.move:
        used = STRUGGLE if index is None else fighters[side].combatant.moves[index]
        action = replace(action, move_id=used.id)
        fighters[side].last_used = index
        if arena is not None:
            arena.last_move, arena.last_move_turn = used, turn
        damped = _damped(fighters[side], used)
        paid = hooks.move(used, "pays_hp", fighters[side]) if (
            not action.failed or action.blocked) and not damped else None
        if paid is not None:
            action = replace(action, changes=(*action.changes, paid), attacker_hp=fighters[side].hp_percent,
                             attacker_fainted=fighters[side].hp == 0)
        worked = not (action.failed or action.missed or action.multiplier == 0)
        _announce(fighters[side], hooks.item(fighters[side], "after_use", fighters[side], used, worked))
        if _self_ko(fighters[side], index) and not damped:
            fighters[side].hp = 0
            return replace(action, attacker_hp=0, attacker_fainted=True)
    return action


def _self_ko(fighter: _Fighter, index: int | None) -> bool:
    return index is not None and hooks.move(fighter.combatant.moves[index], "faints_user", default=False)


def _damped(fighter: _Fighter, move: Move) -> bool:
    """A foe's ability keeps the self-KO move from working at all (Damp), unless the user's ability or the move
    ignores it."""
    foe = fighter.arena.foe_of(fighter) if fighter.arena is not None else None
    if foe is None or foe.hp == 0:
        return False
    with _ability_ignored(fighter, foe, move):
        return hooks.ability(foe, "prevents_self_ko", move, default=False)


def _danced(turn: int, side: int, fighters: tuple[_Fighter, _Fighter], action: Action, choice: int | None,
            weather: _Weather, rng: random.Random, arena: _Arena) -> tuple[Event, ...]:
    """The foe repeats the dance the user just used (Dancer), asleep or flinched too, with no PP and no lock into
    it. A copy is not copied again, nor a dance a called move (Metronome) brought."""
    user, dancer = fighters[side], fighters[1 - side]
    move = _chosen(user, choice)
    if (not action.move or action.via or not move.flagged(abilities.DANCE_FLAG) or user.hp == 0 or dancer.hp == 0
            or tuple(_field(dancer, "hides", move, dancer))
            or not hooks.ability(dancer, "copies_dance", default=False)):
        return ()
    held = set(dancer.volatiles)
    with _ability_ignored(dancer, user, move):
        copied = _strike(turn, 1 - side, dancer, user, _retyped(dancer, move_power.typed(move, weather.kind, dancer)),
                         (), weather, rng, arena)
    locks = set(dancer.volatiles) - held
    for key in locks:
        del dancer.volatiles[key]
    copied = replace(copied, move_id=move.id,
                     changes=tuple(change for change in copied.changes if change.kind not in locks))
    return AbilityAct(turn, 1 - side, dancer.combatant.name, dancer.ability, effect="dance"), copied


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
    effect, charged = (None if readied else hooks.move(called, "charges", attacker, side, _sheltered(
        attacker, _move_weather(attacker, weather.kind)))) or ("", ())
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


class _Aim(NamedTuple):
    multiplier: float
    accuracy: float
    checks: bool


@dataclass
class HitResult:
    """One hit of a damaging move: `damage` is the HP the Pokémon itself lost, `absorbed` the HP its Substitute took
    (`on_substitute`), and `blocked_by` the ability that took the hit for no HP (Disguise, Ice Face)."""

    damage: int = 0
    absorbed: int = 0
    on_substitute: bool = False
    blocked_by: str | None = None
    critical: bool = False

    @property
    def reached(self) -> bool:
        """The hit landed on the Pokémon itself, not its Substitute; a Disguise hit takes no HP but lands."""
        return not self.on_substitute


@dataclass
class MoveResult:
    """What a damaging move did, hit by hit. `sheer_forced`: the user's Sheer Force boosts the move, read once as it
    starts."""

    move: Move
    sheer_forced: bool = False
    hits: list[HitResult] = field(default_factory=list)

    @property
    def landed(self) -> bool:
        return bool(self.hits)

    @property
    def reached(self) -> bool:
        return any(hit.reached for hit in self.hits)

    @property
    def total_damage(self) -> int:
        """Showdown's `totalDamage`: the HP the Pokémon lost, a Substitute's share left out."""
        return sum(hit.damage for hit in self.hits)

    @property
    def absorbed(self) -> int:
        return sum(hit.absorbed for hit in self.hits)

    @property
    def critical(self) -> bool:
        return any(hit.critical for hit in self.hits)


@dataclass
class _Volley:
    """The hits of one move (`result`) and what the Action logs of them: the `changes` they made; `endured` names the
    item that held the defender on, `answered` the one that answered a hit, `berry` the one it ate between hits,
    `resisted` its resist berry; `contact` the ability that hit back at a contact hit, `blocked_by` the one that
    stopped an ailment, and `lessened` the one that weakened a hit taken at full HP (Multiscale)."""

    result: MoveResult
    changes: list[Change] = field(default_factory=list)
    sturdy: bool = False
    barbed: bool = False
    endured: str = ""
    answered: str = ""
    berry: str = ""
    resisted: str = ""
    contact: str | None = None
    blocked_by: str | None = None
    lessened: str | None = None


def _strike(turn: int, side: int, attacker: _Fighter, defender: _Fighter, move: Move, recovered: tuple[str, ...],
            weather: _Weather, rng: random.Random, arena: _Arena) -> Action:
    """The used move acts on the defender, once its user could act and paid the PP."""
    names = (attacker.combatant.name, defender.combatant.name)
    held_off = _held_off(turn, side, attacker, defender, move, recovered, weather, rng)
    if held_off is not None:
        return held_off
    before = weather.current
    used = hooks.move(move, "use", attacker, defender, side, turn, weather, arena, rng)
    if used is not None:
        started = weather.current is not None and weather.current != before
        return Action(turn, side, *names, move.name, recovered=recovered, defender_hp=defender.hp_percent,
                      attacker_hp=attacker.hp_percent, cleared_by=weather.cleared_by if started else "", **used)
    result = MoveResult(move, sheer_forced=hooks.ability(attacker, "secondary_chance", move, default=1.0) == 0)
    hooks.move(move, "before_hit", attacker, defender)
    aim = _aim(attacker, defender, move, weather)
    whiffed = _whiffed(turn, side, attacker, defender, move, recovered, aim, rng)
    if whiffed is not None:
        return whiffed
    volley = _land_hits(turn, side, attacker, defender, move, aim, weather, rng, result)
    hit = _hit(side, turn, attacker, defender, move, result, result.hits[-1] if result.landed else HitResult(),
               aim.multiplier, rng)
    changes, ability = _after_hits(turn, side, attacker, defender, move, volley)
    added = not result.sheer_forced
    recoil, drained = _recoil_or_drain(turn, side, attacker, defender, move, result.total_damage + result.absorbed)
    after_item = _defender_item_effect(hit) if result.landed and added else ""
    defender_item = volley.endured or volley.answered or after_item or volley.berry or volley.resisted
    if result.landed and added:
        _announce(defender, hooks.ability(defender, "after_move_secondary", hit))
    with _ability_ignored(attacker, defender, move):
        changes = (*changes, *_answers(
            added and hooks.move(move, "after_move_secondary_self", attacker, defender, result)))
    attacker_item = _attacker_item_effect(attacker, defender, result, drained)
    if result.landed and added:
        _announce(attacker, hooks.ability(attacker, "after_move_secondary_self", attacker, defender, result))
    with _ability_ignored(attacker, defender, move):
        changes = (*changes, *_answers(hooks.move(move, "after_move", attacker, defender, result)))
    action = Action(
        turn, side, *names, move.name, multiplier=aim.multiplier, critical=result.critical, changes=changes,
        recoil=recoil, defender_hp=defender.hp_percent, knockout=defender.hp == 0, attacker_fainted=attacker.hp == 0,
        recovered=recovered, hits=len(result.hits), drained=drained, attacker_hp=attacker.hp_percent, ability=ability,
        attacker_item=attacker_item, defender_item=defender_item,
    )
    if result.landed:
        _announce(attacker, hooks.ability(attacker, "source_after_faint", hit))
    return action


def _answers(*answers) -> tuple[Change, ...]:
    return tuple(change for answer in answers if answer for change in answer)


def _held_off(turn: int, side: int, attacker: _Fighter, defender: _Fighter, move: Move, recovered: tuple[str, ...],
              weather: _Weather, rng: random.Random) -> Action | None:
    """The move goes no further before it is used: a state turns it on its user (Powder), it fails on its own terms,
    the weather douses it, the defender's protection or ability stops it, or the defender is out of reach (Fly)."""
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
    if _doused(move, weather):
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
    return None


def _aim(attacker: _Fighter, defender: _Fighter, move: Move, weather: _Weather) -> _Aim:
    """The move's effectiveness on the defender, its accuracy and whether it rolls for it."""
    multiplier = _multiplier(move, defender, weather.kind)
    accuracy = hooks.move(move, "own_accuracy", attacker, defender)
    if accuracy is None:
        accuracy = _accuracy(attacker, defender, move)
    attacker.primed = None
    checks = (move.accuracy is not None and not hooks.move(move, "skips_accuracy", weather.kind, default=False)
              and not _sure_hit(attacker, defender))
    return _Aim(multiplier, accuracy, checks)


def _whiffed(turn: int, side: int, attacker: _Fighter, defender: _Fighter, move: Move, recovered: tuple[str, ...],
             aim: _Aim, rng: random.Random) -> Action | None:
    """The defender's type or ability takes nothing from the move, or else the accuracy roll misses."""
    names = (attacker.combatant.name, defender.combatant.name)
    if aim.multiplier == 0:
        granted = hooks.ability(defender, "immune_to", move, defender, default=False) and effectiveness(
            move.type, defender.combatant.types) > 0
        crash = _crash(attacker, move)
        return Action(turn, side, *names, move.name, multiplier=0, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent,
                      ability=defender.ability if granted else None, changes=crash,
                      attacker_fainted=attacker.hp == 0)
    if aim.checks and rng.random() * 100 >= aim.accuracy:
        _announce(attacker, hooks.item(attacker, "on_miss", attacker))
        crash = _crash(attacker, move)
        return Action(turn, side, *names, move.name, missed=True, multiplier=aim.multiplier, recovered=recovered,
                      defender_hp=defender.hp_percent, attacker_hp=attacker.hp_percent, changes=crash,
                      attacker_fainted=attacker.hp == 0)
    return None


def _land_hits(turn: int, side: int, attacker: _Fighter, defender: _Fighter, move: Move, aim: _Aim,
               weather: _Weather, rng: random.Random, result: MoveResult) -> _Volley:
    """Each hit rolls its critical hit and damage, then lands on the defender, its Substitute or an ability that takes
    it (Disguise). A move that rolls each hit stops at its first miss; any move stops once either side faints."""
    volley = _Volley(result)
    hooks.move(move, "draws", attacker, rng)
    fixed = hooks.move(move, "fixed_damage", attacker, defender, rng)
    volley.resisted = defender.item if fixed is None and hooks.item(defender, "resists", move.type, aim.multiplier,
                                                                    default=False) else ""
    crit_stage = (hooks.move(move, "crit_stage", default=move.crit_stage) + hooks.item(attacker, "crit_stage", default=0)
                  + sum(_field(attacker, "crit_stage")) + hooks.ability(attacker, "crit_stage", default=0))
    if hooks.ability(attacker, "always_crits", defender, default=False):
        crit_stage = len(CRITICAL_CHANCES) - 1
    no_crit = any(_field(defender, "guards_crit")) or hooks.ability(defender, "guards_crit", default=False)
    spent = hooks.item(attacker, "spent_on", attacker, move, default=None)
    if spent is not None:
        attacker.primed = spent
        _announce(attacker, ItemEffect(turn, side, attacker.combatant.name, spent, "spent"))
    lessening = fixed is None and hooks.ability(defender, "lessens_hit", defender, default=False)
    hit_count = _hit_count(move, attacker, rng)
    rolls_each_hit = (aim.checks and hooks.move(move, "rolls_each_hit", default=False)
                      and not hooks.ability(attacker, "skips_hit_rolls", default=False)
                      and not hooks.item(attacker, "skips_hit_rolls", default=False))
    for hit in range(hit_count):
        if hit > 0 and rolls_each_hit and rng.random() * 100 >= aim.accuracy:
            break
        if fixed is None:
            hit_critical = rng.random() < CRITICAL_CHANCES[min(crit_stage, len(CRITICAL_CHANCES) - 1)] and not no_crit
            damage = _damage(attacker, defender, move, aim.multiplier, hit_critical, weather.kind, rng, hit)
        else:
            hit_critical, damage = False, fixed
        if volley.resisted and hit == 0:
            ripened = hooks.ability(defender, "berry_factor", default=1)
            damage = max(1, int(damage * items.RESIST_BERRY_MULTIPLIER / ripened))
            use_berry(defender)
        current = _lands(attacker, defender, move, damage, hit_critical, lessening, rng, volley)
        result.hits.append(current)
        _answer_hit(_hit(side, turn, attacker, defender, move, result, current, aim.multiplier, rng), volley)
        if defender.hp == 0 or attacker.hp == 0:
            break
        held = defender.item
        if (current.reached and current.blocked_by is None and hit < hit_count - 1
                and hooks.item(defender, "between_hits", defender, default=False)):
            volley.berry = held
    if spent is not None:
        attacker.primed = None
    if result.total_damage > 0:
        defender.hurt = Hurt(move.physical, result.total_damage, makes_contact(attacker, move))
    return volley


def _lands(attacker: _Fighter, defender: _Fighter, move: Move, damage: int, critical: bool, lessening: bool,
           rng: random.Random, volley: _Volley) -> HitResult:
    """One hit lands on the defender's Substitute, on an ability that takes it for no HP (Disguise) or on the
    defender."""
    shielded = _field(defender, "takes_hit", damage, attacker, defender, move)
    if shielded:
        return HitResult(absorbed=sum(shielded), on_substitute=True, critical=critical)
    blocker = defender.ability
    if hooks.ability(defender, "takes_hit", damage, attacker, defender, move, default=False):
        return HitResult(blocked_by=blocker, critical=critical)
    damage = min(defender.hp, damage)
    if lessening and defender.hp == defender.max_hp > 1:
        volley.lessened = defender.ability
    damage = _endured(defender, move, damage, rng, volley)
    defender.hp -= damage
    defender.times_hit += 1
    defender.hit_by_foe = defender.hit_by_foe or damage > 0
    return HitResult(damage=damage, critical=critical)


def _answer_hit(hit: "Hit", volley: _Volley) -> None:
    """What one hit sets off, in Showdown's order: the first hit's changes to the user's own stats, then on a
    Substitute its answers (AfterSubDamage); otherwise the move's added effects, the answers to a damaging hit
    (DamagingHit) and the move's own after-hit effects."""
    attacker, defender, move, current = hit.user, hit.target, hit.move, hit.current
    added = not volley.result.sheer_forced
    if move.stat_on_user and added and len(volley.result.hits) == 1:
        volley.changes.extend(_stat_changes(hit.side, move, attacker, defender, hit.rng))
    if current.on_substitute:
        if added:
            volley.changes.extend(_answers(hooks.move(move, "after_sub_damage", attacker, defender, current)))
        hooks.item(defender, "after_sub_damage", hit)
        return
    if defender.hp > 0:
        changes, blocked_by = _secondary_effects(hit.side, move, attacker, defender, hit.rng, added)
        volley.changes.extend(changes)
        volley.blocked_by = volley.blocked_by or blocked_by
        _announce(attacker, hooks.ability(attacker, "adds_secondary", hit))
        _announce(attacker, hooks.item(attacker, "adds_secondary", hit))
    with _answering(defender):
        _damaging_hit(hit, volley)
    if attacker.hp > 0 and added:
        volley.changes.extend(_answers(hooks.move(move, "after_hit", attacker, defender, current)))


@contextmanager
def _answering(defender: _Fighter) -> Iterator[None]:
    """The defender's ability answers a hit even when the move leaves it out (Mold Breaker), which it does again for
    the next hit."""
    ignored, defender.ability_ignored = defender.ability_ignored, False
    try:
        yield
    finally:
        defender.ability_ignored = ignored


def _damaging_hit(hit: "Hit", volley: _Volley) -> None:
    """Showdown's DamagingHit: the defender's and the user's answers to a hit that landed, the knockout hit too."""
    attacker, defender, move = hit.user, hit.target, hit.move
    if hit.contact and not _chip_free(attacker):
        barbs = hooks.ability(defender, "on_contact_hit", attacker, default=0)
        volley.barbed = volley.barbed or barbs > 0
        attacker.hp = max(0, attacker.hp - hooks.item(defender, "on_contact_hit", attacker, default=0) - barbs)
    if defender.hp == 0:
        _announce(defender, hooks.ability(defender, "on_fainted_by", defender, attacker, move, hit.current.damage))
    else:
        contact = _contact_effect(hit.side, move, attacker, defender, hit.rng)
        if contact:
            volley.changes.append(contact)
            volley.contact = defender.ability
    _announce(defender, hooks.ability(defender, "damaging_hit", hit))
    held = defender.item
    if hooks.item(defender, "damaging_hit", hit, default=False):
        volley.answered = volley.answered or held
    _announce(attacker, hooks.ability(attacker, "source_damaging_hit", hit))


def _endured(defender: _Fighter, move: Move, damage: int, rng: random.Random, volley: _Volley) -> int:
    """A hit that would knock the defender out leaves it at 1 HP when the move spares it (False Swipe), or a state,
    its ability (Sturdy) or its item (Focus Sash) holds it on."""
    lethal, from_full, held = damage >= defender.hp, defender.hp == defender.max_hp > 1, defender.item
    if lethal and hooks.move(move, "spares", default=False):
        return defender.hp - 1
    if lethal and any(_field(defender, "endures", defender, from_full, rng)):
        return defender.hp - 1
    if lethal and hooks.ability(defender, "endures", defender, from_full, rng, default=False):
        volley.sturdy = True
        return defender.hp - 1
    if lethal and hooks.item(defender, "endures", defender, from_full, rng, default=False):
        volley.endured = held
        return defender.hp - 1
    return damage


def _after_hits(turn: int, side: int, attacker: _Fighter, defender: _Fighter, move: Move,
                volley: _Volley) -> tuple[tuple[Change, ...], str | None]:
    """What the hits left: a knocked-out defender's last answers (Destiny Bond), then the changes the move made and the
    ability the Action names."""
    if defender.hp == 0:
        _field(defender, "on_knocked_out", attacker, move, turn, side)
    named = defender.ability if volley.sturdy or volley.barbed else volley.lessened
    return tuple(volley.changes), volley.contact or named or volley.blocked_by


def _recoil_or_drain(turn: int, side: int, attacker: _Fighter, defender: _Fighter, move: Move,
                     dealt: int) -> tuple[bool, bool]:
    """Struggle's or the move's recoil, or the HP it drains, which the defender's ability may turn into damage
    (Liquid Ooze). `dealt` counts what a Substitute took. Returns whether the user took recoil and whether it
    drained."""
    recoil, drained = move is STRUGGLE, move.drain > 0 and dealt > 0
    if recoil:
        attacker.hp = max(0, attacker.hp - max(1, attacker.max_hp // STRUGGLE_RECOIL_FRACTION))
    elif move.drain < 0 and dealt > 0 and not _recoil_free(attacker):
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
    return recoil, drained


def _hit(side: int, turn: int, attacker: _Fighter, defender: _Fighter, move: Move, result: MoveResult,
         current: HitResult, multiplier: float, rng: random.Random) -> "Hit":
    """`current` as its answers see it: an ability that took it (Disguise) leaves it neutral, so it is not super
    effective (Weakness Policy)."""
    return Hit(side, turn, attacker, defender, move, result, current, 1.0 if current.blocked_by else multiplier, rng)


@dataclass(frozen=True)
class Hit:
    """A damaging move's hit as the abilities and items that answer it see it: `side` is the user's, `result` the
    move's hits and `current` the one answered, the last for the answers once the move is over."""

    side: int
    turn: int
    user: "_Fighter"
    target: "_Fighter"
    move: Move
    result: MoveResult
    current: HitResult
    multiplier: float
    rng: random.Random

    @property
    def contact(self) -> bool:
        return makes_contact(self.user, self.move)

    @property
    def on_substitute(self) -> bool:
        return self.current.on_substitute

    @property
    def reached(self) -> bool:
        return self.current.reached

    @property
    def critical(self) -> bool:
        return self.current.critical


def use_berry(fighter: "_Fighter") -> None:
    """The fighter uses up the berry it holds, and its ability may answer (Cheek Pouch)."""
    berry = fighter.item
    fighter.item, fighter.ate_berry = None, True
    _announce(fighter, hooks.ability(fighter, "on_berry_eaten", fighter, berry))


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


def _crash(attacker: _Fighter, move: Move) -> tuple[Change, ...]:
    crash = hooks.move(move, "crashes", attacker)
    return () if crash is None else (crash,)


def _weather_of(fighter: "_Fighter") -> str | None:
    """The weather as it acts on the fighter's ability."""
    return _sheltered(fighter, fighter.arena.weather.kind if fighter.arena is not None else None)


def _weight(fighter: "_Fighter") -> float:
    return (fighter.combatant.weight * hooks.ability(fighter, "modify_weight", default=1.0)
            * hooks.item(fighter, "modify_weight", default=1.0))


def _retyped(attacker: _Fighter, move: Move) -> Move:
    """A state that changes the type of the user's move (Electrify, Ion Deluge)."""
    kind = next(iter(_field(attacker, "retypes_move", move)), None)
    return move if kind is None else replace(move, type=kind)


def _attacker_item_effect(attacker: _Fighter, defender: _Fighter, result: MoveResult, drained: bool) -> str:
    """The user's item that acted after its damaging move landed, also on a Substitute or Disguise (Life Orb, Shell
    Bell), or that added to what it drained (Big Root), or ""."""
    item, move = attacker.item, result.move
    if not result.landed or not move.damaging or move is STRUGGLE or item is None:
        return ""
    rooted = hooks.item(attacker, "modify_drain", 0) is not None and drained and attacker.hp > 0
    acted = rooted or not result.sheer_forced and hooks.item(attacker, "after_move_secondary_self", attacker, defender,
                                                             result, default=False)
    return item if acted else ""


def _defender_item_effect(hit: Hit) -> str:
    """The target's item that answered the move once its hits were over (Kee Berry), or ""."""
    item = hit.target.item
    return item if hooks.item(hit.target, "after_move_secondary", hit, default=False) else ""


def makes_contact(attacker: _Fighter, move: Move) -> bool:
    """The move touches its target (Showdown's contact flag), unless the user's ability or item says it does not."""
    return (move.flagged("contact") and not hooks.ability(attacker, "drops_contact", default=False)
            and not hooks.item(attacker, "drops_contact", move, default=False))


def _start_of_action(attacker: _Fighter, move: Move, rng: random.Random) -> tuple[tuple[str, ...], str]:
    """What ended before the Pokémon acts, and what stops it from using its move ("" if nothing)."""
    recovered: list[str] = []
    if attacker.status == "sleep":
        attacker.sleep_left = max(0, attacker.sleep_left - hooks.ability(attacker, "wakes_early", default=0))
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
        _announce(attacker, hooks.ability(attacker, "after_banned", banned, attacker))
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
    if counted is None:
        counted = hooks.item(attacker, "hit_count", move, rng)
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
        damage * _stab(attacker, move) * multiplier * _weather_boost(move, _move_weather(attacker, weather), defender)
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


def _secondary_effects(side: int, move: Move, attacker: _Fighter, defender: _Fighter, rng: random.Random,
                       added: bool) -> tuple[tuple[Change, ...], str | None]:
    """One hit's effects on the defender, and the defender's ability if it stopped the move's ailment. Without its
    `added` effects (Sheer Force) a hit only thaws the defender. Changes to the user's own stats come once, with the
    first hit."""
    changes: list[Change] = []
    blocked_by = None
    if added and _ailment_lands(move, attacker, defender, rng):
        if _blocks_ailment(defender, move.ailment):
            blocked_by = defender.ability
        else:
            changes.append(_inflict(move.ailment, defender, 1 - side, rng, attacker))
    if defender.status == "freeze" and (move.type == "fire" or hooks.move(move, "thaws_user", default=False)):
        defender.status = None
        changes.append(Change(1 - side, defender.combatant.name, "thaw"))
    if added:
        if not move.stat_on_user:
            changes.extend(_stat_changes(side, move, attacker, defender, rng))
        changes.extend(hooks.move(move, "secondary", attacker, defender, side, rng, default=()))
    return tuple(changes), blocked_by


def _stat_changes(side: int, move: Move, attacker: _Fighter, defender: _Fighter, rng: random.Random) -> list[Change]:
    if not move.stat_changes or rng.random() * 100 >= move.stat_chance * _chance_scale(
            move, attacker, None if move.stat_on_user else defender):
        return []
    target, target_side = (attacker, side) if move.stat_on_user else (defender, 1 - side)
    guarded = not move.stat_on_user and _stats_guarded(defender, not _infiltrates(attacker))
    changes = (shift_stage(target, target_side, key, stages, guarded=guarded, by=None if move.stat_on_user else attacker)
               for key, stages in move.stat_changes)
    return [change for change in changes if change is not None]


def shift_stage(fighter: _Fighter, side: int, key: str, stages: int, *, guarded: bool = False,
                by: "_Fighter | None" = None, copied: bool = False) -> Change | None:
    """Moves one stat stage within ±6 after its holder's ability scales it (Contrary, Simple); the `Change` that
    landed, None when none did. A drop is stopped when `guarded` (Mist); `by` is the foe lowering it, and the holder's
    ability may keep the stat (Clear Body), bounce the drop back at `by` (Mirror Armor) or answer it (Defiant). A
    raise that is not itself `copied` lets the foe's ability copy it (Opportunist)."""
    stages *= hooks.ability(fighter, "stage_factor", default=1)
    if guarded and stages < 0:
        return None
    by_foe = by is not None and by is not fighter and stages < 0
    if by_foe and hooks.ability(fighter, "guards_stat", key, fighter, default=False):
        _ability_act(fighter, effect="guard")
        return None
    if by_foe and hooks.item(fighter, "keeps_stats", default=False):
        _announce(fighter, ItemEffect(fighter.arena.turn if fighter.arena else 0, side, fighter.combatant.name,
                                      fighter.item, "guard"))
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
    foe = fighter.arena.foe_of(fighter) if fighter.arena is not None else None
    if change.stages > 0 and not copied and foe is not None and foe is not fighter and foe.hp > 0:
        _announce(foe, hooks.ability(foe, "on_foe_raised", foe, key, change.stages))
        hooks.item(foe, "on_foe_raised", foe, key, change.stages)
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
    return (_open_to(move.ailment, defender, not _infiltrates(attacker), attacker)
            and rng.random() * 100 < move.ailment_chance * _chance_scale(move, attacker, defender))


def _chance_scale(move: Move, attacker: _Fighter, defender: _Fighter | None) -> float:
    """Scales the chance of a move's added effect: the user's ability (Serene Grace, Sheer Force), and the target's
    when the effect lands on it (Shield Dust), or its item (Covert Cloak)."""
    if defender is not None and (hooks.ability(defender, "blocks_secondary", default=False)
                                 or hooks.item(defender, "blocks_secondary", default=False)):
        return 0.0
    return hooks.ability(attacker, "secondary_chance", move, default=1.0)


def _open_to(ailment: str, fighter: _Fighter, by_foe: bool = False, user: "_Fighter | None" = None) -> bool:
    """Whether `fighter` can get `ailment` now. `by_foe`: a foe inflicts it and its side's guards (Safeguard) count.
    `user`: the Pokémon whose move inflicts it, whose ability may reach past the type (Corrosion)."""
    typed = not (user is not None and ailment in abilities.POISONS
                 and hooks.ability(user, "poisons_any_type", default=False))
    if typed and any(kind in fighter.combatant.types for kind in AILMENT_IMMUNE_TYPES[ailment]):
        return False
    if any(_field(fighter, "guards_ailment", ailment, fighter, by_foe)):
        return False
    return fighter.confusion_left == 0 if ailment == "confusion" else fighter.status is None


def _stats_guarded(fighter: _Fighter, by_foe: bool = True) -> bool:
    """Whether a foe cannot lower `fighter`'s stats now (Mist)."""
    return by_foe and any(_field(fighter, "guards_stats"))


def _inflict(ailment: str, defender: _Fighter, side: int, rng: random.Random | None,
             by: "_Fighter | None" = None) -> Change:
    """`by` is the foe giving it, which the defender's ability may give it back to (Synchronize)."""
    if ailment == "confusion":
        defender.confusion_left = rng.randint(*CONFUSION_TURNS)
    else:
        defender.status = ailment
        defender.toxic_ticks = 0
        if ailment == "sleep":
            defender.sleep_left = rng.randint(*SLEEP_TURNS)
    if by is not None and _passed_back(ailment, defender, by):
        _ability_act(defender, changes=(_inflict(ailment, by, by.side, rng),))
    if by is not None:
        _announce(by, hooks.ability(by, "after_inflicting", ailment, by, defender, side, rng))
    return Change(side, defender.combatant.name, ailment)


def _passed_back(ailment: str, holder: _Fighter, foe: _Fighter) -> bool:
    """`holder`'s ability gives `ailment` from `foe` back to it, if it can take it (Synchronize)."""
    return (foe is not holder and foe.hp > 0 and hooks.ability(holder, "passes_ailment", ailment, default=False)
            and _open_to(ailment, foe, True) and not _blocks_ailment(foe, ailment))


def _status_of(fighter: _Fighter) -> str | None:
    """The status `fighter` counts as having: its own, or the one its ability stands for (Comatose's sleep)."""
    return fighter.status or hooks.ability(fighter, "status_as", default=None)


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
    if self_ko is not None and _wasted_on(attacker, defender, attacker.combatant.moves[self_ko]):
        self_ko = None
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
    if weather == STRONG_WINDS or attacker.arena is not None and attacker.arena.weather.held:
        return None
    for index, move in enumerate(attacker.combatant.moves):
        if attacker.pp[index] > 0 and move.weather and weather != move.weather:
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
                or hooks.move(move, "wasted", attacker, defender, default=False) or _sleeps_through(attacker, move)
                or attacker.arena is not None and _doused(move, attacker.arena.weather)):
            return 0.0
        share = hooks.move(move, "score_share", _sheltered(attacker, _move_weather(attacker, weather)), attacker,
                           default=1.0)
        return (_damage_score(attacker, defender, move, weather) * share
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
        * _expected_stab(attacker, move) * multiplier
        * _weather_boost(move, _move_weather(attacker, weather), defender)
        * _damage_taken(attacker, defender, move, multiplier, False)
        * _item_boost(attacker, move, multiplier)
        * accuracy * attack / max(1, defense) * _screen(attacker, defender, move, False) * _exposed(attacker, defender)
    )


def _hp_kept(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None) -> float:
    """The share of its HP the user keeps after the recoil, HP cost and the foe's contact ability it expects the move
    to take (Brave Bird, Steel Beam, Rough Skin)."""
    paid = hooks.move(move, "hp_paid", attacker, default=0)
    if makes_contact(attacker, move) and not _chip_free(attacker):
        paid += hooks.ability(defender, "on_contact_hit", attacker, default=0) * _expected_hits(move, attacker, 100)
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
    if (accuracy < 100 and hooks.move(move, "rolls_each_hit", default=False)
            and not hooks.item(attacker, "skips_hit_rolls", default=False)):
        return sum((accuracy / 100) ** hit for hit in range(move.max_hits))
    expected = hooks.ability(attacker, "expected_hits", move, default=move.expected_hits)
    expected = hooks.item(attacker, "expected_hits", move, expected, default=expected)
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
    return (hooks.item(attacker, "modify_damage", move.type, multiplier, move.physical, punch, default=1.0)
            * hooks.item(attacker, "streak_boost", attacker, move, default=1.0))


def _weather_boost(move: Move, weather: str | None, defender: _Fighter) -> float:
    """Sun and rain scale Fire and Water moves, unless the target's item keeps them off it (Utility Umbrella)."""
    boost = WEATHER_MOVE_BOOST.get(_sheltered(defender, weather), {}).get(move.type, 1.0)
    return hooks.move(move, "modify_weather_boost", weather, boost, default=boost)


def _doused(move: Move, weather: _Weather) -> bool:
    return weather.lasting and move.damaging and move.type == PRIMAL_DOUSED.get(weather.kind)


def _move_weather(attacker: _Fighter, weather: str | None) -> str | None:
    """The weather the attacker's own moves act in: its ability may set its own (Mega Sol)."""
    return hooks.ability(attacker, "own_weather", weather, default=weather)


def _power(attacker: _Fighter, defender: _Fighter, move: Move, weather: str | None, multiplier: float,
           hit: int | None = None) -> float:
    """The move's power in this battle state (`move_power`), then the attacker's ability on that power, the field, and
    a target hiding where the move reaches it (Earthquake on Dig)."""
    if move is STRUGGLE or move is CONFUSION_HIT:
        return move.power
    power = move_power.power(move, attacker, defender, weather, multiplier, hit)
    extra_hit = hooks.ability(attacker, "extra_hit_power", default=1.0) if hit and move.max_hits <= 1 else 1.0
    power *= hooks.call("items", attacker.primed, "primed_power", default=1.0)
    return power * (hooks.ability(attacker, "modify_power", move, power, attacker, defender, weather, default=1.0)
                    * hooks.ability(defender, "modify_foe_power", move, defender, default=1.0)) * math.prod(
        _field(attacker, "field_power", move, attacker, defender)) * (_hidden(defender, move) or 1.0) * extra_hit


def _expected_stab(attacker: _Fighter, move: Move) -> float:
    if hooks.ability(attacker, "retypes_for", move, attacker, default=False):
        return STAB_MULTIPLIER
    return _stab(attacker, move)


def _stab(attacker: _Fighter, move: Move) -> float:
    if move.type not in attacker.combatant.types:
        return 1.0
    return hooks.ability(attacker, "modify_stab", default=STAB_MULTIPLIER)


def _multiplier(move: Move, defender: _Fighter, weather: str | None = None) -> float:
    """Strong winds take away the Flying type's weaknesses. A state that grounds the defender (Gravity) lets a Ground
    move hit it through its Flying type and its airborne ability. Ring Target drops its holder's type immunities, not
    its ability's."""
    if move.type is None:
        return 1.0
    forced_down = move.type == "ground" and (any(_field(defender, "grounds"))
                                             or hooks.item(defender, "grounds", default=False)
                                             or hooks.move(move, "hits_airborne", default=False))
    if not forced_down and hooks.ability(defender, "immune_to", move, defender, default=False):
        return 0.0
    if not forced_down and move.type == "ground" and (any(_field(defender, "lifts"))
                                                      or hooks.item(defender, "floats", default=False)):
        return 0.0
    types = defender.combatant.types
    if forced_down or weather == STRONG_WINDS and effectiveness(move.type, ("flying",)) > 1:
        types = tuple(kind for kind in types if kind != "flying")
    exposed = set(_field(defender, "exposes", move.type))
    if hooks.item(defender, "drops_immunities", default=False):
        exposed |= set(types)
    foe = defender.arena.foe_of(defender) if defender.arena is not None else None
    if foe is not None and foe is not defender:
        exposed |= {hooks.ability(foe, "exposes", move.type)} - {None}
    if exposed:
        types = tuple(kind for kind in types if kind not in exposed or effectiveness(move.type, (kind,)) > 0)
    multiplier = (effectiveness(move.type, types) * hooks.move(move, "type_multiplier", types, default=1.0)
                  * math.prod(_field(defender, "weakens", move.type)))
    if multiplier == 0:
        return multiplier
    return hooks.ability(defender, "caps_effectiveness", multiplier, defender, default=multiplier)


def _grounded(fighter: _Fighter) -> bool:
    """A Flying type, an airborne ability (Levitate) or a lifting state (Magnet Rise) floats unless a state or its item
    grounds it (Gravity, Ingrain, Iron Ball)."""
    if any(_field(fighter, "grounds")) or hooks.item(fighter, "grounds", default=False):
        return True
    return ("flying" not in fighter.combatant.types and not hooks.ability(fighter, "airborne", default=False)
            and not any(_field(fighter, "lifts")) and not hooks.item(fighter, "floats", default=False))


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
            * (hooks.item(attacker, "accuracy_as_user", defender, default=1.0)
               * hooks.item(defender, "accuracy_as_target", default=1.0)
               * hooks.call("items", attacker.primed, "primed_accuracy", default=1.0))
            * math.prod(_field(attacker, "modify_accuracy"))
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
    if move.flagged(abilities.POWDER_FLAG) and hooks.item(defender, "powder_proof", default=False):
        return defender.item
    if hooks.ability(attacker, "fails_against", move, defender, default=False):
        return attacker.ability
    return ""


def _wasted_on(attacker: _Fighter, defender: _Fighter, move: Move) -> bool:
    """The move would fail on the defender or its ability would bounce it back (Magic Bounce), unless the user's
    ability leaves that ability out (Mold Breaker)."""
    with _ability_ignored(attacker, defender, move):
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


