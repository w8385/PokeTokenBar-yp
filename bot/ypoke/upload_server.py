"""LAN HTTP endpoint the app posts its battle entry to. Contract: bot/API.md."""

import json
import logging
import re
import threading
from datetime import UTC, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable
from urllib.parse import parse_qs, urlsplit

from ypoke.dex import normalize_dex
from ypoke.moves import MAX_MOVES, default_move_ids
from ypoke.store import Store

MAX_BODY_BYTES = 64 * 1024
MAX_PARTY_SIZE = 6
MAX_ENTRY_SIZE = 3
RECENT_BATTLE_LIMIT = 5
COWORKER_LIMIT = 30
COWORKER_WINDOW = timedelta(days=30)
ABILITY_NAME = re.compile(r"[a-z][a-z-]{0,39}")
IV_KEYS = ("hp", "attack", "defense", "special_attack", "special_defense", "speed")

MovesFor = Callable[[int, int], list[dict]]
OnUpload = Callable[[str, list[dict]], None]
NameFor = Callable[[str], str | None]


class PartyError(ValueError):
    pass


def serve(
    store: Store, host: str, port: int, on_upload: OnUpload, moves_for: MovesFor, name_for: NameFor = lambda user_id: None
) -> ThreadingHTTPServer:
    """Start the upload server on a daemon thread and return it.

    `on_upload(user_id, party)` runs after each stored upload, before the reply.
    `moves_for(pokemon_id, level)` returns the attacking moves learnable at that level and raises OSError when offline.
    `name_for(user_id)` returns a Slack display name, or None when it cannot be found.
    """
    handler = type("BoundUploadHandler", (_UploadHandler,), {
        "store": store, "on_upload": staticmethod(on_upload), "moves_for": staticmethod(moves_for),
        "name_for": staticmethod(name_for),
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
    party = payload.get("party")
    if not isinstance(party, list) or not 1 <= len(party) <= MAX_PARTY_SIZE:
        raise PartyError(f"party must be a list of 1 to {MAX_PARTY_SIZE} entries")
    return [_validate_member(index, member) for index, member in enumerate(party)]


def check_moves(party: list[dict], moves_for: MovesFor) -> None:
    """Raise PartyError if a chosen move is not an attacking move learnable at the member's level."""
    for index, member in enumerate(party):
        if "moves" not in member:
            continue
        learnable = {move["id"] for move in moves_for(member["pokemon_id"], member["level"])}
        for move_id in member["moves"]:
            if move_id not in learnable:
                raise PartyError(f"party[{index}].moves: {move_id} is not an attacking move learnable at level {member['level']}")


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

    def do_GET(self) -> None:
        url = urlsplit(self.path)
        if url.path == "/v1/health":
            self._reply(200, {"ok": True})
            return
        if url.path not in ("/v1/party", "/v1/moves"):
            self._reply(404, {"ok": False, "error": "not_found"})
            return
        user_id = self._authenticated_user()
        if user_id is None:
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
        if self.path != "/v1/party":
            self._reply(404, {"ok": False, "error": "not_found"})
            return
        user_id = self._authenticated_user()
        if user_id is None:
            return
        try:
            length = max(0, int(self.headers.get("Content-Length") or 0))
        except ValueError:
            length = 0
        if length > MAX_BODY_BYTES:
            self._reply(413, {"ok": False, "error": "too_large"})
            return
        try:
            payload = json.loads(self.rfile.read(length) or b"null")
            party = validate_party(payload)
            check_moves(party, self.moves_for)
        except json.JSONDecodeError:
            self._reply(400, {"ok": False, "error": "invalid JSON"})
            return
        except PartyError as error:
            self._reply(400, {"ok": False, "error": str(error)})
            return
        except OSError:
            self._reply(503, {"ok": False, "error": "pokeapi_unavailable"})
            return
        self.store.save_party(user_id, party, normalize_dex(payload))
        self.on_upload(user_id, party)
        self._reply(200, {"ok": True, "party_size": len(party), **battle_overview(self.store, user_id, self.name_for)})

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
            moves = self.moves_for(pokemon_id, level)
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

    def _reply(self, status: int, body: dict) -> None:
        encoded = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def _validate_member(index: int, member: object) -> dict:
    where = f"party[{index}]"
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
    nature = member.get("nature")
    if isinstance(nature, str) and 0 < len(nature.strip()) <= 20:
        normalized["nature"] = nature.strip().lower()
    ability = member.get("ability")
    if isinstance(ability, str) and ABILITY_NAME.fullmatch(ability.strip().lower()):
        normalized["ability"] = ability.strip().lower()
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


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)
