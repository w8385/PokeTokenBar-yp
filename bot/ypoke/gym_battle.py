"""A player's team against a gym trainer: the same simulation as a Slack battle, nothing stored and nothing posted.

The Elite Four and a villain hideout are runs of consecutive battles. The bot keeps no run: the app sends the
team's state from the last battle as `carried` and gets the next one back as `carry`.
"""

import secrets
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
from functools import partial

from ypoke import gyms
from ypoke.battle import (
    CARRIED_STATUSES, Action, BattleResult, Carry, Combatant, FormShift, HazardDamage, ItemEffect, ItemHeal, MegaEvolution,
    SendOut, StatusDamage, WeatherDamage, YawnSleep, simulate,
)
from ypoke.combatants import combatant
from ypoke.gym_data import FINALE_LINE
from ypoke.narration import battle_turns, split_side
from ypoke.pokeapi import PokeAPIService
from ypoke.upload_server import PartyError

WORKERS = 6


class GymBattles:
    def __init__(self, pokeapi: PokeAPIService, new_seed: Callable[[], int] = lambda: secrets.randbits(31)):
        self._pokeapi = pokeapi
        self._new_seed = new_seed

    def catalog(self) -> dict:
        return gyms.catalog()

    def battle(self, battle_id: str, team: list[dict], carried: list[dict | None] | None = None) -> dict | None:
        """`team` is a validated member list and `carried` the validated state of each member going in.
        None for an unknown battle; raises OSError when PokéAPI is down and PartyError when `carried` is sent
        for a battle that is not part of a run.

        A rental member fights at the trainer's level, like a loaner against a player's lead in a Slack battle."""
        opponent = gyms.find(battle_id)
        if opponent is None:
            return None
        if carried is not None and opponent.run is None:
            raise PartyError("carried is only for Elite Four and hideout battles")
        mine = [{**member, "level": opponent.level} if member.get("rental") else member for member in team]
        starts = [None if state is None else Carry(state["hp"], state["status"]) for state in carried or [None] * len(mine)]
        awake = [index for index, start in enumerate(starts) if start is None or start.hp > 0]
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            fighters = list(pool.map(partial(combatant, self._pokeapi), [*mine, *gyms.foe_members(opponent)]))
        player, foes = fighters[:len(mine)], tuple(fighters[len(mine):])
        seed = self._new_seed()
        finale = len(foes) - opponent.finale if opponent.finale else None
        result = simulate((tuple(player[index] for index in awake), foes), seed, [starts[index] for index in awake],
                          finale=finale, unlimited_megas=opponent.kind == "hidden")
        shown, carry = _outcomes(starts, awake, result)
        won = result.winner == 0
        following = gyms.next_in_run(opponent) if won else None
        return {
            "gym_id": opponent.id,
            "kind": opponent.kind,
            "trainer": {"name": opponent.trainer.name, "line": opponent.trainer.line},
            "won": won,
            "turns": result.turns,
            "seed": seed,
            "player_team": _roster(player, shown),
            "foe_team": _roster(foes, result.remaining[1]),
            "log": _log(result, finale),
            "events": _events(result, (awake, list(range(len(foes)))), [starts[index] for index in awake], finale),
            "run": _run(opponent, following),
            "carry": carry if following else None,
        }


def _outcomes(starts: Sequence[Carry | None], awake: list[int], result: BattleResult) -> tuple[list[int | None], list[dict]]:
    """Per team member: the HP share the battle reported (0 for one that was already down, None when it never got
    sent out) and the state to carry on. A member that never got sent out keeps what it came in with."""
    shown: list[int | None] = []
    carry: list[dict] = []
    for index, start in enumerate(starts):
        if index not in awake:
            shown.append(0)
            carry.append({"hp": 0, "status": None})
            continue
        position = awake.index(index)
        share = result.remaining[0][position]
        shown.append(share)
        if share is None:
            carry.append({"hp": 100, "status": None} if start is None else {"hp": start.hp, "status": start.status})
        else:
            carry.append({"hp": share, "status": result.statuses[0][position] if share else None})
    return shown, carry


def _run(opponent: gyms.Opponent, following: str | None) -> dict | None:
    """Where the battle sits in its run. `next` is the battle to send after a win; after a loss it is None and
    the run starts again from `first` with nothing carried."""
    if opponent.run is None:
        return None
    return {
        "id": opponent.run, "step": opponent.step, "steps": opponent.steps,
        "first": gyms.run_of(opponent)[0].id, "next": following,
    }


def _roster(roster: Sequence[Combatant], shares: Sequence[int | None]) -> list[dict]:
    """`hp` is the share of max HP left at the end: 0 fainted, None never sent out."""
    return [
        {"pokemon_id": member.pokemon_id, "name": member.name, "level": member.level, "types": list(member.types),
         "shiny": member.shiny, "hp": shares[index]}
        for index, member in enumerate(roster)
    ]


def _events(result: BattleResult, members: tuple[list[int], list[int]], starts: Sequence[Carry | None],
            finale: int | None = None) -> list[dict]:
    """The battle as the app replays it: who is out, its form, which move, HP shares, faints and statuses. `members` maps each
    side's fighting order to its team index (the player's skips members that came in down); `starts` is how each
    of the player's fighters came in. A `finale` event comes right before the trainer's member `finale` is out."""
    replay = _Replay(members)
    for side in (0, 1):
        start = starts[0] if side == 0 and starts else None
        replay.switch(0, side, start)
    turn = 0
    for event in result.events:
        turn = getattr(event, "turn", turn)
        if isinstance(event, SendOut):
            position = event.member
            replay.active[event.side] = position
            if event.side == 1 and position == finale and not replay.seen(1):
                replay.events.append({"turn": turn, "type": "finale", "side": 1, "member": position,
                                      "text": dict(FINALE_LINE)})
            replay.switch(turn, event.side, starts[position] if event.side == 0 else None)
        elif isinstance(event, Action):
            replay.action(event)
        elif isinstance(event, (StatusDamage, WeatherDamage, ItemHeal, HazardDamage)):
            replay.hp(turn, event.side, event.hp)
        elif isinstance(event, ItemEffect) and event.effect in ("cure", *CARRIED_STATUSES):
            replay.status(turn, event.side, None if event.effect == "cure" else event.effect)
        elif isinstance(event, YawnSleep):
            replay.status(turn, event.side, "sleep")
        elif isinstance(event, (MegaEvolution, FormShift)) and event.form_id is not None:
            replay.form(turn, event.side, event.form_id, event.kind)
    return replay.events


class _Replay:
    """`active[side]` is the fighting position (index into `members[side]`) of the member out on that side."""

    def __init__(self, members: tuple[list[int], list[int]]):
        self.members = members
        self.active = [0, 0]
        self.events: list[dict] = []
        self._hp: dict[tuple[int, int], int] = {}
        self._status: dict[tuple[int, int], str | None] = {}

    def seen(self, side: int) -> bool:
        return self._key(side) in self._hp

    def switch(self, turn: int, side: int, start: Carry | None) -> None:
        """A member coming back after a pivot comes out with the HP and status it left with."""
        key = self._key(side)
        if key not in self._hp:
            self._hp[key] = 100 if start is None else start.hp
            self._status[key] = None if start is None else start.status
        self._emit(turn, "switch", side, hp=self._hp[key], status=self._status[key])

    def form(self, turn: int, side: int, form_id: int, kind: str) -> None:
        self._emit(turn, "form", side, pokemon_id=form_id, kind=kind)

    def action(self, action: Action) -> None:
        if action.move:
            self._emit(action.turn, "move", action.side, move=action.move, move_id=action.move_id)
        for status in action.recovered:
            if status in CARRIED_STATUSES:
                self.status(action.turn, action.side, None)
        self.hp(action.turn, 1 - action.side, action.defender_hp)
        self.hp(action.turn, action.side, action.attacker_hp)
        for change in action.changes:
            if change.kind in CARRIED_STATUSES:
                self.status(action.turn, change.side, change.kind)
            elif change.kind == "thaw":
                self.status(action.turn, change.side, None)

    def hp(self, turn: int, side: int, hp: int) -> None:
        key = self._key(side)
        if self._hp[key] == hp:
            return
        self._hp[key] = hp
        self._emit(turn, "damage", side, hp=hp)
        if hp == 0:
            self._emit(turn, "faint", side)

    def status(self, turn: int, side: int, status: str | None) -> None:
        key = self._key(side)
        if self._status[key] == status or self._hp[key] == 0:
            return
        self._status[key] = status
        self._emit(turn, "status", side, status=status)

    def _key(self, side: int) -> tuple[int, int]:
        return side, self.active[side]

    def _emit(self, turn: int, event_type: str, side: int, **fields) -> None:
        member = self.members[side][self.active[side]]
        self.events.append({"turn": turn, "type": event_type, "side": side, "member": member, **fields})


def _log(result: BattleResult, finale: int | None = None) -> list[dict]:
    """Every turn's lines; the turn the trainer's member `finale` comes out has the finale line before its entrance."""
    turns = [
        {"turn": number, "lines": [dict(zip(("side", "text"), split_side(line))) for line in lines]}
        for number, lines in battle_turns(result)
    ]
    entrance = next((event for event in result.events
                     if isinstance(event, SendOut) and event.side == 1 and event.member == finale), None)
    if finale is None or entrance is None:
        return turns
    for turn in turns:
        if turn["turn"] != entrance.turn:
            continue
        at = next((index for index, line in enumerate(turn["lines"])
                   if line["side"] == 1 and line["text"].startswith("↪") and entrance.pokemon in line["text"]),
                  len(turn["lines"]))
        turn["lines"].insert(at, {"side": 1, "text": FINALE_LINE["ko"]})
    return turns
