"""A player's team against a gym trainer: the same simulation as a Slack battle, nothing stored and nothing posted.

The Elite Four and a villain hideout are runs of consecutive battles. The bot keeps no run: the app sends the
team's state from the last battle as `carried` and gets the next one back as `carry`.
"""

import secrets
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
from functools import partial

from ypoke import gyms
from ypoke.battle import BattleResult, Carry, Combatant, simulate
from ypoke.combatants import combatant
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
        result = simulate((tuple(player[index] for index in awake), foes), seed, [starts[index] for index in awake])
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
            "log": _log(result),
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


def _log(result: BattleResult) -> list[dict]:
    return [
        {"turn": number, "lines": [dict(zip(("side", "text"), split_side(line))) for line in lines]}
        for number, lines in battle_turns(result)
    ]
