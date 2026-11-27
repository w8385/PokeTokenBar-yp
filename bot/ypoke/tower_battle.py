"""A player's run in the battle tower. The bot owns each run: the streak, the locked entry, the rentals offered, picked
and last beaten, so the record and the ranking cannot run ahead of the battles fought. The app mirrors the replies."""

import secrets
import threading
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from functools import partial

from ypoke import entry_rules, tower
from ypoke.battle import BATTLE_LEVEL, simulate
from ypoke.combatants import combatant
from ypoke.gym_battle import WORKERS, _events, _log, _roster
from ypoke.pokeapi import PokeAPIService
from ypoke.store import Store
from ypoke.upload_server import PartyError, TowerConflict


class TowerBattles:
    def __init__(self, store: Store, pokeapi: PokeAPIService,
                 new_seed: Callable[[], int] = lambda: secrets.randbits(31)):
        self._store = store
        self._pokeapi = pokeapi
        self._new_seed = new_seed
        self._locks: dict[str, threading.Lock] = {}
        self._guard = threading.Lock()

    def battle(self, user_id: str, mode: str, team: list[dict] | None) -> dict:
        """The next battle of the user's run in `mode`. `team` is the validated entry (entry mode; ignored for
        rental). Raises PartyError for an entry the tower does not take, TowerConflict when the run does not allow
        the battle, OSError when PokéAPI is down."""
        with self._lock(user_id):
            state = self._state(user_id, mode)
            battle = state["streak"] + 1
            mine = self._team(state, mode, team, battle)
            opponent = tower.opponent(state["run"], battle)
            with ThreadPoolExecutor(max_workers=WORKERS) as pool:
                fighters = list(pool.map(partial(combatant, self._pokeapi),
                                         [*mine, *(member.battle_member() for member in opponent.members)]))
            player, foes = fighters[:len(mine)], tuple(fighters[len(mine):])
            seed = self._new_seed()
            result = simulate((tuple(player), foes), seed, [None] * len(player))
            won = result.winner == 0
            trophy = self._settle(state, mode, battle, won, opponent)
            self._store.save_tower_run(user_id, mode, state)
            positions = list(range(len(player))), list(range(len(foes)))
            return {
                "gym_id": opponent.sprite,
                "kind": opponent.kind,
                "trainer": {"name": opponent.trainer.name, "line": opponent.trainer.line},
                "won": won,
                "turns": result.turns,
                "seed": seed,
                "player_team": _roster(player, result.remaining[0]),
                "foe_team": _roster(foes, result.remaining[1]),
                "log": _log(result),
                "events": _events(result, positions, [None] * len(player)),
                "run": None,
                "opponent": _opponent_json(opponent),
                "tower": {**_record_json(mode, state), "battle": battle, "set": tower.set_of(battle),
                          "bp": tower.bp_for(battle) if won else 0, "trophy": trophy},
            }

    def rental(self, user_id: str, pick: list[int] | None = None, swap: tuple[int, int] | None = None) -> dict:
        """The rental run as it stands, after picking three of the offer or swapping one member (`give`, `take`) for
        one of the trainer just beaten. With neither, a run without a team gets its offer of six (kept until picked).
        Raises PartyError for indexes out of range or a swap that repeats a species, TowerConflict when the run does
        not allow the change."""
        with self._lock(user_id):
            state = self._state(user_id, "rental")
            if pick is not None:
                if state["rental"] or not state["offer"]:
                    raise TowerConflict("no_offer")
                if len(set(pick)) != tower.TEAM_SIZE or not all(0 <= index < len(state["offer"]) for index in pick):
                    raise PartyError(f"pick must be {tower.TEAM_SIZE} different indexes of the offer")
                state["rental"] = [state["offer"][index] for index in pick]
                state["offer"] = None
            elif swap is not None:
                give, take = swap
                if not state["beaten"]:
                    raise TowerConflict("nothing_to_swap")
                if not (0 <= give < len(state["rental"]) and 0 <= take < len(state["beaten"])):
                    raise PartyError("give and take must index the team and the beaten trainer's members")
                team = [*state["rental"]]
                team[give] = state["beaten"][take]
                if len({entry_rules.species_id(member["pokemon_id"]) for member in team}) != len(team):
                    raise PartyError("the team already has that species")
                state["rental"] = team
                state["beaten"] = None
            elif not state["rental"] and not state["offer"]:
                state["run"] = self._new_seed()
                state["offer"] = [member.to_json() for member in tower.offer(state["run"], state["streak"] + 1)]
            self._store.save_tower_run(user_id, "rental", state)
            return _record_json("rental", state)

    def quit(self, user_id: str, mode: str) -> dict:
        """Ends the run in `mode`: the streak goes back to 0 and the entry or rentals are let go."""
        with self._lock(user_id):
            state = self._state(user_id, mode)
            _end_run(state)
            self._store.save_tower_run(user_id, mode, state)
            return _record_json(mode, state)

    def record(self, user_id: str) -> dict:
        """The user's run and record in each mode."""
        return {mode: _record_json(mode, self._state(user_id, mode)) for mode in tower.MODES}

    def ranking(self, mode: str, limit: int) -> list[tuple[str, int]]:
        return self._store.tower_bests(mode, limit)

    def _team(self, state: dict, mode: str, team: list[dict] | None, battle: int) -> list[dict]:
        """The members fighting battle `battle`, at Lv50 with the item clause applied."""
        if mode == "rental":
            if not state["rental"]:
                raise TowerConflict("no_rental")
            state["beaten"] = None
            members = [tower.rental_member(member["pokemon_id"], battle, tuple(member["moves"]), member["held_item"])
                       .battle_member() for member in state["rental"]]
        else:
            if team is None:
                raise PartyError("team is required in entry mode")
            if len(team) != tower.TEAM_SIZE or len({entry_rules.species_id(m["pokemon_id"]) for m in team}) != len(team):
                raise PartyError(f"team must be {tower.TEAM_SIZE} Pokémon of different species")
            key = tower.team_key(team)
            if state["streak"] == 0:
                state["run"] = self._new_seed()
                state["team"] = key
            elif state["team"] != key:
                raise TowerConflict("team_locked")
            members = [{**member, "level": BATTLE_LEVEL} for member in team]
        return list(entry_rules.lineup(members).members)

    def _settle(self, state: dict, mode: str, battle: int, won: bool, opponent: tower.Opponent) -> str | None:
        """Applies the outcome to the run; the trophy the win earned for the first time, if any."""
        if not won:
            _end_run(state)
            return None
        state["streak"] = battle
        state["best"] = max(state["best"], battle)
        if mode == "rental":
            state["beaten"] = [member.to_json() for member in opponent.members]
        if opponent.trophy and opponent.trophy not in state["trophies"]:
            state["trophies"].append(opponent.trophy)
            return opponent.trophy
        return None

    def _state(self, user_id: str, mode: str) -> dict:
        stored = self._store.tower_run(user_id, mode) or {}
        return {"streak": 0, "best": 0, "run": 0, "team": None, "rental": None, "offer": None, "beaten": None,
                "trophies": [], **stored}

    def _lock(self, user_id: str) -> threading.Lock:
        with self._guard:
            return self._locks.setdefault(user_id, threading.Lock())


def _end_run(state: dict) -> None:
    state.update(streak=0, team=None, rental=None, offer=None, beaten=None)


def _record_json(mode: str, state: dict) -> dict:
    record = {"mode": mode, "streak": state["streak"], "best": state["best"], "trophies": list(state["trophies"]),
              "next": _next(state["streak"] + 1)}
    if mode == "rental":
        record |= {"offer": state["offer"], "team": state["rental"], "beaten": state["beaten"]}
    return record


def _next(battle: int) -> dict:
    return {"battle": battle, "set": tower.set_of(battle), "owner": battle in tower.OWNER_BATTLES}


def _opponent_json(opponent: tower.Opponent) -> dict:
    """Shaped like a `GET /v1/gyms` opponent, so the app shows it with the gym views."""
    return {
        "id": opponent.sprite, "kind": opponent.kind, "index": opponent.battle, "types": [], "level": BATTLE_LEVEL,
        "trainer": {"name": opponent.trainer.name, "line": opponent.trainer.line},
        "team": [member.pokemon_id for member in opponent.members], "finale": 0, "run": None,
    }
