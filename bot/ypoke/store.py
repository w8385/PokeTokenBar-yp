"""SQLite storage: upload tokens, latest party per user, battle records and the PokéAPI caches."""

import hashlib
import json
import secrets
import sqlite3
from contextlib import closing
from dataclasses import dataclass
from datetime import UTC, datetime

_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    slack_user_id TEXT PRIMARY KEY,
    token_hash TEXT UNIQUE NOT NULL,
    party_json TEXT,
    uploaded_at TEXT
);
CREATE TABLE IF NOT EXISTS battles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    challenger_id TEXT NOT NULL,
    opponent_id TEXT NOT NULL,
    winner_id TEXT NOT NULL,
    seed INTEGER NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS battles_challenger ON battles (challenger_id);
CREATE INDEX IF NOT EXISTS battles_opponent ON battles (opponent_id);
CREATE TABLE IF NOT EXISTS pokemon_cache (
    pokemon_id INTEGER PRIMARY KEY,
    data_json TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS api_cache (
    cache_key TEXT PRIMARY KEY,
    data_json TEXT NOT NULL
);
"""


@dataclass(frozen=True)
class StoredParty:
    party: list[dict]
    uploaded_at: str


@dataclass(frozen=True)
class Record:
    wins: int
    losses: int


class Store:
    def __init__(self, path: str):
        self._path = path
        with closing(self._connect()) as connection, connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.executescript(_SCHEMA)

    def issue_token(self, slack_user_id: str) -> str:
        """Create a new upload token for the user, revoking any previous one."""
        token = secrets.token_urlsafe(24)
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT INTO users (slack_user_id, token_hash) VALUES (?, ?) "
                "ON CONFLICT (slack_user_id) DO UPDATE SET token_hash = excluded.token_hash",
                (slack_user_id, _hash_token(token)),
            )
        return token

    def user_for_token(self, token: str) -> str | None:
        with closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT slack_user_id FROM users WHERE token_hash = ?", (_hash_token(token),)
            ).fetchone()
        return row[0] if row else None

    def is_linked(self, slack_user_id: str) -> bool:
        with closing(self._connect()) as connection:
            row = connection.execute("SELECT 1 FROM users WHERE slack_user_id = ?", (slack_user_id,)).fetchone()
        return row is not None

    def save_party(self, slack_user_id: str, party: list[dict]) -> None:
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "UPDATE users SET party_json = ?, uploaded_at = ? WHERE slack_user_id = ?",
                (json.dumps(party, ensure_ascii=False), _now(), slack_user_id),
            )

    def party(self, slack_user_id: str) -> StoredParty | None:
        with closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT party_json, uploaded_at FROM users WHERE slack_user_id = ? AND party_json IS NOT NULL",
                (slack_user_id,),
            ).fetchone()
        return StoredParty(party=json.loads(row[0]), uploaded_at=row[1]) if row else None

    def record_battle(
        self, challenger_id: str, opponent_id: str, winner_id: str, seed: int, at: datetime | None = None
    ) -> None:
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT INTO battles (challenger_id, opponent_id, winner_id, seed, created_at) VALUES (?, ?, ?, ?, ?)",
                (challenger_id, opponent_id, winner_id, seed, _timestamp(at or datetime.now(UTC))),
            )

    def records_since(self, since: datetime) -> dict[str, Record]:
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT challenger_id, opponent_id, winner_id FROM battles WHERE created_at >= ?",
                (_timestamp(since),),
            ).fetchall()
        wins: dict[str, int] = {}
        totals: dict[str, int] = {}
        for challenger_id, opponent_id, winner_id in rows:
            for user_id in (challenger_id, opponent_id):
                totals[user_id] = totals.get(user_id, 0) + 1
                wins[user_id] = wins.get(user_id, 0) + (user_id == winner_id)
        return {user_id: Record(wins=wins[user_id], losses=total - wins[user_id]) for user_id, total in totals.items()}

    def record(self, slack_user_id: str) -> Record:
        with closing(self._connect()) as connection:
            wins, total = connection.execute(
                "SELECT COALESCE(SUM(winner_id = ?), 0), COUNT(*) FROM battles "
                "WHERE challenger_id = ? OR opponent_id = ?",
                (slack_user_id, slack_user_id, slack_user_id),
            ).fetchone()
        return Record(wins=wins, losses=total - wins)

    def cached_pokemon(self, pokemon_id: int) -> dict | None:
        with closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT data_json FROM pokemon_cache WHERE pokemon_id = ?", (pokemon_id,)
            ).fetchone()
        return json.loads(row[0]) if row else None

    def cache_pokemon(self, pokemon_id: int, data: dict) -> None:
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT OR REPLACE INTO pokemon_cache (pokemon_id, data_json) VALUES (?, ?)",
                (pokemon_id, json.dumps(data, ensure_ascii=False)),
            )

    def cached(self, cache_key: str) -> object | None:
        with closing(self._connect()) as connection:
            row = connection.execute("SELECT data_json FROM api_cache WHERE cache_key = ?", (cache_key,)).fetchone()
        return json.loads(row[0]) if row else None

    def cache(self, cache_key: str, data: object) -> None:
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT OR REPLACE INTO api_cache (cache_key, data_json) VALUES (?, ?)",
                (cache_key, json.dumps(data, ensure_ascii=False)),
            )

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self._path, timeout=10)


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _now() -> str:
    return _timestamp(datetime.now(UTC))


def _timestamp(moment: datetime) -> str:
    return moment.astimezone(UTC).isoformat(timespec="seconds")
