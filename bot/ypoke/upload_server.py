"""LAN HTTP endpoint the app posts its battle entry to. Contract: bot/API.md."""

import json
import logging
import math
import re
import threading
import time
from datetime import UTC, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from collections.abc import Collection
from typing import Callable, Protocol
from urllib.parse import parse_qs, urlsplit

from ypoke import entry_rules
from ypoke.battle import CARRIED_STATUSES
from ypoke.dex import normalize_dex
from ypoke.move_effects import wants_status_moves
from ypoke.moves import MAX_MOVES, default_move_ids
from ypoke.messages import DirectMessage
from ypoke.miracle import POST_ERRORS as MIRACLE_POST_ERRORS
from ypoke.miracle import MiracleService
from ypoke.remote_ops import MAX_ACK_IDS, RemoteOps, is_reason, normalize_remote
from ypoke.store import Store
from ypoke.trades import PROPOSE_ERRORS, TradeService

MAX_BODY_BYTES = 5 * 1024 * 1024
MAX_PARTY_SIZE = 6
RECENT_BATTLE_LIMIT = 5
COWORKER_LIMIT = 30
COWORKER_WINDOW = timedelta(days=30)
GYM_BATTLE_INTERVAL = 3.0
ABILITY_NAME = re.compile(r"[a-z][a-z-]{0,39}")
IV_KEYS = ("hp", "attack", "defense", "special_attack", "special_defense", "speed")

MovesFor = Callable[..., list[dict]]
OnUpload = Callable[[str, list[dict]], None]
NameFor = Callable[[str], str | None]
Notify = Callable[[tuple[DirectMessage, ...]], None]


class PartyError(ValueError):
    pass


class GymApi(Protocol):
    def catalog(self) -> dict: ...

    def battle(self, gym_id: str, team: list[dict], carried: list[dict | None] | None) -> dict | None:
        """The battle result body, or None for an unknown gym. Raises OSError when PokéAPI is down and PartyError
        for a request the battle cannot take."""


class RateLimit:
    """At most one call per key every `interval` seconds."""

    def __init__(self, interval: float, clock: Callable[[], float] = time.monotonic):
        self._interval = interval
        self._clock = clock
        self._last: dict[str, float] = {}
        self._lock = threading.Lock()

    def retry_after(self, key: str) -> float:
        """0 when the call may go ahead (and is counted), else the seconds to wait."""
        with self._lock:
            now = self._clock()
            wait = self._last.get(key, -self._interval) + self._interval - now
            if wait > 0:
                return wait
            self._last[key] = now
            return 0.0


_REPLIED = object()


def serve(
    store: Store, host: str, port: int, on_upload: OnUpload, moves_for: MovesFor,
    name_for: NameFor = lambda user_id: None,
    trades: TradeService | None = None, notify: Notify = lambda messages: None,
    gyms: GymApi | None = None, clock: Callable[[], float] = time.monotonic,
    miracle: MiracleService | None = None, remote: RemoteOps | None = None,
) -> ThreadingHTTPServer:
    """Start the upload server on a daemon thread and return it.

    `on_upload(user_id, party)` runs after each stored upload, before the reply.
    `moves_for(pokemon_id, level, machine_ids, status=..., egg=...)` returns the attacking moves usable at that level (`machine_ids` is `None` for every machine move), with `egg` also the attacking egg moves, with `status` also the battle's status moves, and raises OSError when offline.
    `name_for(user_id)` returns a Slack display name, or None when it cannot be found.
    With `trades`, the trade endpoints are served and `notify` sends the DMs a new offer produces.
    With `gyms`, the gym endpoints are served; `clock` times their rate limit.
    With an available `miracle`, the miracle trade endpoints are served; otherwise they answer `unavailable`.
    The remote-ops endpoints are always served; `notify` sends the DM an ack produces.
    """
    handler = type("BoundUploadHandler", (_UploadHandler,), {
        "store": store, "on_upload": staticmethod(on_upload), "moves_for": staticmethod(moves_for),
        "name_for": staticmethod(name_for), "trades": trades, "notify": staticmethod(notify),
        "gyms": gyms, "gym_limit": RateLimit(GYM_BATTLE_INTERVAL, clock), "miracle": miracle,
        "remote": remote or RemoteOps(store),
    })
    server = ThreadingHTTPServer((host, port), handler)
    threading.Thread(target=server.serve_forever, name="upload-server", daemon=True).start()
    return server


def validate_party(payload: object) -> list[dict]:
    """Return the normalized party, or raise PartyError naming the first broken rule."""
    if not isinstance(payload, dict):
        raise PartyError("body must be a JSON object")
    app_version = payload.get("app_version")
    if app_version is not None and not (isinstance(app_version, str) and len(app_version) <= 32):
        raise PartyError("app_version must be a string of at most 32 chars")
    return validate_members(payload.get("party"), "party")


def validate_members(members: object, field: str) -> list[dict]:
    """The normalized members of the list at `field` (its name in error messages), or PartyError."""
    if not isinstance(members, list) or not 1 <= len(members) <= MAX_PARTY_SIZE:
        raise PartyError(f"{field} must be a list of 1 to {MAX_PARTY_SIZE} entries")
    validated = [_validate_member(field, index, member) for index, member in enumerate(members)]
    return list(entry_rules.lineup(validated).members)


def check_moves(party: list[dict], moves_for: MovesFor, field: str = "party") -> None:
    """Raise PartyError if a chosen move is not a move the member can use: an attacking move learned by level-up at or
    below its level or by machine, an attacking egg move when the member has a Mirror Herb, or one of the battle's
    status moves."""
    for index, member in enumerate(party):
        if "moves" not in member:
            continue
        opt_ins = {"status": True} if wants_status_moves(member["moves"]) else {}
        if member.get("mirror_herb"):
            opt_ins["egg"] = True
        learnable = {move["id"] for move in moves_for(member["pokemon_id"], member["level"], member["moves"], **opt_ins)}
        for move_id in member["moves"]:
            if move_id not in learnable:
                raise PartyError(f"{field}[{index}].moves: {move_id} is not an attacking move learnable at level {member['level']}")


def validate_carried(carried: object, size: int) -> list[dict | None] | None:
    """The HP and status the team brings from the previous battle of a run (None entries: untouched), or PartyError."""
    if carried is None:
        return None
    if not isinstance(carried, list) or len(carried) != size:
        raise PartyError(f"carried must be a list with one entry per team member ({size})")
    states: list[dict | None] = []
    for index, entry in enumerate(carried):
        if entry is None:
            states.append(None)
            continue
        if not isinstance(entry, dict) or not _is_int(entry.get("hp")) or not 0 <= entry["hp"] <= 100:
            raise PartyError(f"carried[{index}].hp must be 0..100")
        status = entry.get("status")
        if status is not None and status not in CARRIED_STATUSES:
            raise PartyError(f"carried[{index}].status must be null or one of {', '.join(CARRIED_STATUSES)}")
        states.append({"hp": entry["hp"], "status": status})
    if all(state is not None and state["hp"] == 0 for state in states):
        raise PartyError("carried: no member can still fight")
    return states


def battle_overview(store: Store, user_id: str, name_for: NameFor) -> dict:
    """The uploader's last battles and the other users' current lead Pokémon, with display names and no Slack ids."""
    recent = [
        {
            "opponent_name": name_for(battle.opponent_id),
            "my_pokemon_id": battle.my_pokemon_id,
            "opponent_pokemon_id": battle.opponent_pokemon_id,
            "result": "win" if battle.won else "loss",
            "turns": battle.turns,
            "at": battle.at,
        }
        for battle in store.recent_battles(user_id, RECENT_BATTLE_LIMIT)
    ]
    coworkers = [
        {"name": name_for(lead.user_id), "pokemon_id": lead.pokemon_id, "level": lead.level, "shiny": lead.shiny}
        for lead in store.leads_except(user_id, datetime.now(UTC) - COWORKER_WINDOW, COWORKER_LIMIT)
    ]
    return {"recent_battles": recent, "coworkers": coworkers}


class _UploadHandler(BaseHTTPRequestHandler):
    store: Store
    on_upload: OnUpload
    moves_for: MovesFor
    name_for: NameFor
    trades: TradeService | None
    notify: Notify
    gyms: GymApi | None
    gym_limit: RateLimit
    miracle: MiracleService | None

    def do_GET(self) -> None:
        url = urlsplit(self.path)
        if url.path == "/v1/health":
            self._reply(200, {"ok": True})
            return
        if url.path not in ("/v1/party", "/v1/moves", "/v1/coworkers", "/v1/trades", "/v1/gyms", "/v1/miracle",
                            "/v1/ops"):
            self._reply(404, {"ok": False, "error": "not_found"})
            return
        user_id = self._authenticated_user()
        if user_id is None:
            return
        if url.path == "/v1/ops":
            ops = [{"id": op.id, "kind": op.kind, "payload": op.payload, "created_at": op.created_at}
                   for op in self.remote.pending(user_id)]
            self._reply(200, {"ok": True, "ops": ops})
            return
        if url.path == "/v1/miracle":
            if self._miracle_available():
                self._reply(200, {"ok": True, "offer": self.miracle.status(user_id)})
            return
        if url.path == "/v1/gyms":
            if self.gyms is None:
                self._reply(404, {"ok": False, "error": "not_found"})
            else:
                self._reply(200, {"ok": True, **self.gyms.catalog()})
            return
        if url.path in ("/v1/coworkers", "/v1/trades"):
            self._trade_read(url.path, user_id)
            return
        if url.path == "/v1/moves":
            self._learnable_moves(parse_qs(url.query))
            return
        stored = self.store.party(user_id)
        if stored is None:
            self._reply(404, {"ok": False, "error": "no_party"})
            return
        self._reply(200, {"ok": True, "party": stored.party, "uploaded_at": stored.uploaded_at})

    def do_POST(self) -> None:
        if self.path not in ("/v1/party", "/v1/trades", "/v1/trades/ack", "/v1/gym/battle", "/v1/miracle",
                             "/v1/miracle/cancel", "/v1/ops/ack"):
            self._reply(404, {"ok": False, "error": "not_found"})
            return
        user_id = self._authenticated_user()
        if user_id is None:
            return
        payload = self._read_json()
        if payload is _REPLIED:
            return
        if self.path == "/v1/miracle":
            self._post_miracle(user_id, payload)
        elif self.path == "/v1/miracle/cancel":
            self._cancel_miracle(user_id)
        elif self.path == "/v1/gym/battle":
            self._gym_battle(user_id, payload)
        elif self.path == "/v1/trades":
            self._propose(user_id, payload)
        elif self.path == "/v1/trades/ack":
            self._acknowledge(user_id, payload)
        elif self.path == "/v1/ops/ack":
            self._acknowledge_ops(user_id, payload)
        else:
            self._store_party(user_id, payload)

    def _read_json(self) -> object:
        try:
            length = max(0, int(self.headers.get("Content-Length") or 0))
        except ValueError:
            length = 0
        if length > MAX_BODY_BYTES:
            self._reply(413, {"ok": False, "error": "too_large"})
            return _REPLIED
        try:
            return json.loads(self.rfile.read(length) or b"null")
        except json.JSONDecodeError:
            self._reply(400, {"ok": False, "error": "invalid JSON"})
            return _REPLIED

    def _store_party(self, user_id: str, payload: object) -> None:
        try:
            party = validate_party(payload)
            check_moves(party, self.moves_for)
        except PartyError as error:
            self._reply(400, {"ok": False, "error": str(error)})
            return
        except OSError:
            self._reply(503, {"ok": False, "error": "pokeapi_unavailable"})
            return
        self.store.save_party(user_id, party, normalize_dex(payload), normalize_remote(payload))
        body = {"ok": True, "party_size": len(party)}
        if self.trades is not None:
            if "trade_pool" in payload:
                self.trades.save_pool(user_id, payload["trade_pool"])
                if self.miracle is not None:
                    self.miracle.pool_changed(user_id)
            body["trades"] = {"deliveries": self.trades.deliveries(user_id), "locked_ids": self.trades.locked_ids(user_id)}
        self.on_upload(user_id, party)
        self._reply(200, {**body, **battle_overview(self.store, user_id, self.name_for)})

    def _gym_battle(self, user_id: str, payload: object) -> None:
        """A practice-style fight: nothing is stored, nothing is posted, and the stored party stays as it is."""
        if self.gyms is None:
            self._reply(404, {"ok": False, "error": "not_found"})
            return
        wait = self.gym_limit.retry_after(user_id)
        if wait > 0:
            self._reply(429, {"ok": False, "error": "rate_limited", "retry_after": round(wait, 1)},
                        {"Retry-After": str(math.ceil(wait))})
            return
        gym_id = payload.get("gym_id") if isinstance(payload, dict) else None
        if not isinstance(gym_id, str):
            self._reply(400, {"ok": False, "error": "gym_id must be a string"})
            return
        try:
            team = validate_members(payload.get("team"), "team")
            check_moves(team, self.moves_for, "team")
            body = self.gyms.battle(gym_id, team, validate_carried(payload.get("carried"), len(team)))
        except PartyError as error:
            self._reply(400, {"ok": False, "error": str(error)})
            return
        except OSError:
            self._reply(503, {"ok": False, "error": "pokeapi_unavailable"})
            return
        if body is None:
            self._reply(404, {"ok": False, "error": "unknown_gym"})
            return
        self._reply(200, {"ok": True, **body})

    def _trade_read(self, path: str, user_id: str) -> None:
        if self.trades is None:
            self._reply(404, {"ok": False, "error": "not_found"})
        elif path == "/v1/coworkers":
            self._reply(200, {"ok": True, "coworkers": self.trades.coworkers(user_id)})
        else:
            self._reply(200, {"ok": True, "trades": {
                "deliveries": self.trades.deliveries(user_id), "history": self.trades.history(user_id),
                "locked_ids": self.trades.locked_ids(user_id),
            }})

    def _propose(self, user_id: str, payload: object) -> None:
        to_id, give_id = (payload.get("to"), payload.get("give")) if isinstance(payload, dict) else (None, None)
        if self.trades is None or not (isinstance(to_id, str) and isinstance(give_id, str)):
            self._reply(400, {"ok": False, "error": "to and give are required strings"})
            return
        result = self.trades.propose(user_id, to_id, give_id)
        if result.error:
            self._reply(400, {"ok": False, "error": result.error, "message": PROPOSE_ERRORS[result.error]})
            return
        self.notify(result.direct_messages)
        self._reply(200, {"ok": True, "trade_id": result.trade_id})

    def _post_miracle(self, user_id: str, payload: object) -> None:
        if not self._miracle_available():
            return
        give_id = payload.get("give") if isinstance(payload, dict) else None
        if not isinstance(give_id, str):
            self._reply(400, {"ok": False, "error": "give is a required string"})
            return
        result = self.miracle.post(user_id, give_id)
        if result.error:
            self._reply(400, {"ok": False, "error": result.error, "message": MIRACLE_POST_ERRORS[result.error]})
            return
        self._reply(200, {"ok": True, "offer": result.offer})

    def _cancel_miracle(self, user_id: str) -> None:
        if not self._miracle_available():
            return
        if self.miracle.cancel_mine(user_id):
            self._reply(200, {"ok": True})
        else:
            self._reply(400, {"ok": False, "error": "none_open", "message": "미라클 교환에 올린 포켓몬이 없어요."})

    def _miracle_available(self) -> bool:
        """Answers 404 `unavailable` when there is no battle channel to post in; the app then hides the feature."""
        if self.miracle is None or not self.miracle.available:
            self._reply(404, {"ok": False, "error": "unavailable"})
            return False
        return True

    def _acknowledge(self, user_id: str, payload: object) -> None:
        trade_ids = payload.get("trade_ids") if isinstance(payload, dict) else None
        if self.trades is None or not (isinstance(trade_ids, list) and all(isinstance(item, str) for item in trade_ids)):
            self._reply(400, {"ok": False, "error": "trade_ids must be a list of strings"})
            return
        self.trades.ack(user_id, trade_ids[:100])
        self._reply(200, {"ok": True})

    def _acknowledge_ops(self, user_id: str, payload: object) -> None:
        applied = payload.get("applied", []) if isinstance(payload, dict) else None
        cancelled = payload.get("cancelled", []) if isinstance(payload, dict) else None
        if not (isinstance(applied, list) and all(_is_op_id(item) for item in applied)):
            self._reply(400, {"ok": False, "error": "applied must be a list of op ids"})
            return
        if not (isinstance(cancelled, list) and all(
            isinstance(item, dict) and _is_op_id(item.get("id")) and is_reason(item.get("reason")) for item in cancelled
        )):
            self._reply(400, {"ok": False, "error": "cancelled must be a list of {id, reason}"})
            return
        if len(applied) + len(cancelled) > MAX_ACK_IDS:
            self._reply(400, {"ok": False, "error": f"at most {MAX_ACK_IDS} ops per ack"})
            return
        message = self.remote.ack(user_id, applied, [(item["id"], item["reason"]) for item in cancelled])
        self._reply(200, {"ok": True})
        if message is not None:
            self.notify((message,))

    def log_request(self, code: int | str = "-", size: int | str = "-") -> None:
        if urlsplit(self.path).path != "/v1/health":
            logging.getLogger(__name__).info("%s %s -> %s", self.command, urlsplit(self.path).path, code)

    def log_message(self, format: str, *args: object) -> None:
        pass

    def _learnable_moves(self, query: dict[str, list[str]]) -> None:
        try:
            pokemon_id = int(query["pokemon_id"][0])
            level = int(query["level"][0])
        except (KeyError, ValueError):
            self._reply(400, {"ok": False, "error": "pokemon_id and level are required integers"})
            return
        if not (_valid_pokemon_id(pokemon_id) and 1 <= level <= 100):
            self._reply(400, {"ok": False, "error": "pokemon_id or level out of range"})
            return
        try:
            opt_ins = {"status": True} if query.get("status") == ["1"] else {}
            if query.get("egg") == ["1"]:
                opt_ins["egg"] = True
            moves = self.moves_for(pokemon_id, level, None if query.get("machine") == ["1"] else (), **opt_ins)
        except OSError:
            self._reply(503, {"ok": False, "error": "pokeapi_unavailable"})
            return
        self._reply(200, {"ok": True, "moves": moves, "default": default_move_ids(moves)})

    def _authenticated_user(self) -> str | None:
        header = self.headers.get("Authorization", "")
        token = header.removeprefix("Bearer ").strip() if header.startswith("Bearer ") else ""
        user_id = self.store.user_for_token(token) if token else None
        if user_id is None:
            self._reply(401, {"ok": False, "error": "unauthorized"})
        return user_id

    def _reply(self, status: int, body: dict, headers: dict[str, str] | None = None) -> None:
        encoded = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(encoded)


def _validate_member(field: str, index: int, member: object) -> dict:
    where = f"{field}[{index}]"
    if not isinstance(member, dict):
        raise PartyError(f"{where} must be an object")
    pokemon_id = member.get("pokemon_id")
    if not _is_int(pokemon_id) or not _valid_pokemon_id(pokemon_id):
        raise PartyError(f"{where}.pokemon_id must be 1..1025 or 10001..10999")
    level = member.get("level")
    if not _is_int(level) or not 1 <= level <= 100:
        raise PartyError(f"{where}.level must be 1..100")
    normalized = {"pokemon_id": pokemon_id, "level": level, "shiny": False, "ivs": {}}
    name = member.get("name")
    if name is not None:
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 40:
            raise PartyError(f"{where}.name must be a string of 1 to 40 chars")
        normalized["name"] = name.strip()
    shiny = member.get("shiny", False)
    if not isinstance(shiny, bool):
        raise PartyError(f"{where}.shiny must be a boolean")
    normalized["shiny"] = shiny
    rental = member.get("rental", False)
    if not isinstance(rental, bool):
        raise PartyError(f"{where}.rental must be a boolean")
    if rental:
        normalized["rental"] = True
    mirror_herb = member.get("mirror_herb", False)
    if not isinstance(mirror_herb, bool):
        raise PartyError(f"{where}.mirror_herb must be a boolean")
    if mirror_herb:
        normalized["mirror_herb"] = True
    nature = member.get("nature")
    if isinstance(nature, str) and 0 < len(nature.strip()) <= 20:
        normalized["nature"] = nature.strip().lower()
    ability = member.get("ability")
    if isinstance(ability, str) and ABILITY_NAME.fullmatch(ability.strip().lower()):
        normalized["ability"] = ability.strip().lower()
    held_item = member.get("held_item")
    if isinstance(held_item, str) and 0 < len(held_item.strip()) <= 40:
        normalized["held_item"] = held_item.strip().lower()
    ivs = member.get("ivs", {})
    if not isinstance(ivs, dict):
        raise PartyError(f"{where}.ivs must be an object")
    for key in IV_KEYS:
        if key in ivs:
            if not _is_int(ivs[key]) or not 0 <= ivs[key] <= 31:
                raise PartyError(f"{where}.ivs.{key} must be 0..31")
            normalized["ivs"][key] = ivs[key]
    moves = member.get("moves")
    if moves is not None:
        if (
            not isinstance(moves, list)
            or len(moves) > MAX_MOVES
            or not all(_is_int(move_id) and move_id > 0 for move_id in moves)
            or len(set(moves)) != len(moves)
        ):
            raise PartyError(f"{where}.moves must be a list of up to {MAX_MOVES} distinct move ids")
        if moves:
            normalized["moves"] = moves
    return normalized


def _valid_pokemon_id(pokemon_id: int) -> bool:
    return 1 <= pokemon_id <= 1025 or 10001 <= pokemon_id <= 10999


def _is_op_id(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)
