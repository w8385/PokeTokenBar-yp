"""LAN HTTP endpoint the app posts its party to. Contract: bot/API.md."""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable

from ypoke.store import Store

MAX_BODY_BYTES = 64 * 1024
MAX_PARTY_SIZE = 6
IV_KEYS = ("hp", "attack", "defense", "special_attack", "special_defense", "speed")


class PartyError(ValueError):
    pass


def serve(store: Store, host: str, port: int, on_upload: Callable[[list[dict]], None]) -> ThreadingHTTPServer:
    """Start the upload server on a daemon thread and return it."""
    handler = type("BoundUploadHandler", (_UploadHandler,), {"store": store, "on_upload": staticmethod(on_upload)})
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


class _UploadHandler(BaseHTTPRequestHandler):
    store: Store
    on_upload: Callable[[list[dict]], None]

    def do_GET(self) -> None:
        if self.path == "/v1/health":
            self._reply(200, {"ok": True})
            return
        if self.path != "/v1/party":
            self._reply(404, {"ok": False, "error": "not_found"})
            return
        user_id = self._authenticated_user()
        if user_id is None:
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
            party = validate_party(json.loads(self.rfile.read(length) or b"null"))
        except json.JSONDecodeError:
            self._reply(400, {"ok": False, "error": "invalid JSON"})
            return
        except PartyError as error:
            self._reply(400, {"ok": False, "error": str(error)})
            return
        self.store.save_party(user_id, party)
        self.on_upload(party)
        self._reply(200, {"ok": True, "party_size": len(party)})

    def log_message(self, format: str, *args: object) -> None:
        pass

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
    if not _is_int(pokemon_id) or not (1 <= pokemon_id <= 1025 or 10001 <= pokemon_id <= 10999):
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
    ivs = member.get("ivs", {})
    if not isinstance(ivs, dict):
        raise PartyError(f"{where}.ivs must be an object")
    for key in IV_KEYS:
        if key in ivs:
            if not _is_int(ivs[key]) or not 0 <= ivs[key] <= 31:
                raise PartyError(f"{where}.ivs.{key} must be 0..31")
            normalized["ivs"][key] = ivs[key]
    return normalized


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)
