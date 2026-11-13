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
CREATE TABLE IF NOT EXISTS extra_tokens (
    token_hash TEXT PRIMARY KEY,
    slack_user_id TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS pending_challenges (
    challenger_id TEXT NOT NULL,
    opponent_id TEXT NOT NULL,
    channel_id TEXT NOT NULL,
    thread_ts TEXT,
    response_url TEXT,
    created_at TEXT NOT NULL,
    echo TEXT,
    PRIMARY KEY (challenger_id, opponent_id)
);
CREATE TABLE IF NOT EXISTS link_prompts (
    slack_user_id TEXT PRIMARY KEY,
    prompted_at TEXT NOT NULL
);
"""


@dataclass(frozen=True)
class StoredParty:
    party: list[dict]
    uploaded_at: str


@dataclass(frozen=True)
class PendingChallenge:
    """A challenge waiting for a side's first upload. `thread_ts` and `response_url` are None when absent."""

    challenger_id: str
    opponent_id: str
    channel_id: str
    thread_ts: str | None
    response_url: str | None
    created_at: datetime
    echo: str | None = None


@dataclass(frozen=True)
class Record:
    wins: int
    losses: int


@dataclass(frozen=True)
class BattleSummary:
    """One finished battle from a user's side. Species and turns are None for battles stored before they were kept."""

    opponent_id: str
    won: bool
    my_pokemon_id: int | None
    opponent_pokemon_id: int | None
    turns: int | None
    at: str


@dataclass(frozen=True)
class Lead:
    user_id: str
    pokemon_id: int
    level: int
    shiny: bool


class Store:
    def __init__(self, path: str):
        self._path = path
        with closing(self._connect()) as connection, connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.executescript(_SCHEMA)
            columns = {row[1] for row in connection.execute("PRAGMA table_info(pending_challenges)")}
            if "echo" not in columns:
                connection.execute("ALTER TABLE pending_challenges ADD COLUMN echo TEXT")
            battle_columns = {row[1] for row in connection.execute("PRAGMA table_info(battles)")}
            for column in ("challenger_pokemon", "opponent_pokemon", "turns"):
                if column not in battle_columns:
                    connection.execute(f"ALTER TABLE battles ADD COLUMN {column} INTEGER")

    def issue_token(self, slack_user_id: str, keep_existing: bool = False) -> str:
        """Create a new upload token for the user. Unless `keep_existing`, every previous token is revoked."""
        token = secrets.token_urlsafe(24)
        with closing(self._connect()) as connection, connection:
            linked = connection.execute(
                "SELECT 1 FROM users WHERE slack_user_id = ?", (slack_user_id,)
            ).fetchone()
            if keep_existing and linked:
                connection.execute(
                    "INSERT INTO extra_tokens (token_hash, slack_user_id) VALUES (?, ?)",
                    (_hash_token(token), slack_user_id),
                )
                return token
            connection.execute("DELETE FROM extra_tokens WHERE slack_user_id = ?", (slack_user_id,))
            connection.execute(
                "INSERT INTO users (slack_user_id, token_hash) VALUES (?, ?) "
                "ON CONFLICT (slack_user_id) DO UPDATE SET token_hash = excluded.token_hash",
                (slack_user_id, _hash_token(token)),
            )
        return token

    def user_for_token(self, token: str) -> str | None:
        with closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT slack_user_id FROM users WHERE token_hash = ?1 "
                "UNION SELECT slack_user_id FROM extra_tokens WHERE token_hash = ?1",
                (_hash_token(token),),
            ).fetchone()
        return row[0] if row else None

    def save_party(self, slack_user_id: str, party: list[dict]) -> None:
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "UPDATE users SET party_json = ?, uploaded_at = ? WHERE slack_user_id = ?",
                (json.dumps(party, ensure_ascii=False), _now(), slack_user_id),
            )

    def linked_user_ids(self) -> list[str]:
        with closing(self._connect()) as connection:
            return [row[0] for row in connection.execute("SELECT slack_user_id FROM users")]

    def party(self, slack_user_id: str) -> StoredParty | None:
        with closing(self._connect()) as connection:
            row = connection.execute(
                "SELECT party_json, uploaded_at FROM users WHERE slack_user_id = ? AND party_json IS NOT NULL",
                (slack_user_id,),
            ).fetchone()
        return StoredParty(party=json.loads(row[0]), uploaded_at=row[1]) if row else None

    def record_battle(
        self,
        challenger_id: str,
        opponent_id: str,
        winner_id: str,
        seed: int,
        at: datetime | None = None,
        pokemon: tuple[int, int] | None = None,
        turns: int | None = None,
    ) -> None:
        """`pokemon` is the (challenger, opponent) lead species ids."""
        challenger_pokemon, opponent_pokemon = pokemon or (None, None)
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT INTO battles (challenger_id, opponent_id, winner_id, seed, created_at, "
                "challenger_pokemon, opponent_pokemon, turns) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (challenger_id, opponent_id, winner_id, seed, _timestamp(at or datetime.now(UTC)),
                 challenger_pokemon, opponent_pokemon, turns),
            )

    def recent_battles(self, slack_user_id: str, limit: int) -> list[BattleSummary]:
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT challenger_id, opponent_id, winner_id, challenger_pokemon, opponent_pokemon, turns, created_at "
                "FROM battles WHERE challenger_id = ?1 OR opponent_id = ?1 ORDER BY created_at DESC, id DESC LIMIT ?2",
                (slack_user_id, limit),
            ).fetchall()
        summaries = []
        for challenger_id, opponent_id, winner_id, challenger_pokemon, opponent_pokemon, turns, created_at in rows:
            mine = challenger_id == slack_user_id
            summaries.append(BattleSummary(
                opponent_id=opponent_id if mine else challenger_id,
                won=winner_id == slack_user_id,
                my_pokemon_id=challenger_pokemon if mine else opponent_pokemon,
                opponent_pokemon_id=opponent_pokemon if mine else challenger_pokemon,
                turns=turns,
                at=created_at,
            ))
        return summaries

    def leads_except(self, slack_user_id: str, since: datetime, limit: int) -> list[Lead]:
        """The first Pokémon of every other user's latest upload since `since`, newest upload first."""
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT slack_user_id, party_json FROM users WHERE party_json IS NOT NULL AND slack_user_id != ? "
                "AND uploaded_at >= ? ORDER BY uploaded_at DESC LIMIT ?",
                (slack_user_id, _timestamp(since), limit),
            ).fetchall()
        leads = []
        for user_id, party_json in rows:
            lead = json.loads(party_json)[0]
            leads.append(Lead(user_id, lead["pokemon_id"], lead["level"], lead.get("shiny", False)))
        return leads

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

    def save_pending(self, challenge: PendingChallenge) -> None:
        """Keep one pending challenge per (challenger, opponent); a new one replaces the old."""
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT OR REPLACE INTO pending_challenges "
                "(challenger_id, opponent_id, channel_id, thread_ts, response_url, created_at, echo) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (challenge.challenger_id, challenge.opponent_id, challenge.channel_id, challenge.thread_ts,
                 challenge.response_url, _timestamp(challenge.created_at), challenge.echo),
            )

    def pending_for(self, slack_user_id: str, since: datetime) -> list[PendingChallenge]:
        """Pending challenges the user is part of, after dropping every one created before `since`."""
        with closing(self._connect()) as connection, connection:
            connection.execute("DELETE FROM pending_challenges WHERE created_at < ?", (_timestamp(since),))
            rows = connection.execute(
                "SELECT challenger_id, opponent_id, channel_id, thread_ts, response_url, created_at, echo "
                "FROM pending_challenges WHERE challenger_id = ?1 OR opponent_id = ?1 ORDER BY created_at",
                (slack_user_id,),
            ).fetchall()
        return [PendingChallenge(*row[:5], created_at=datetime.fromisoformat(row[5]), echo=row[6]) for row in rows]

    def claim_pending(self, challenge: PendingChallenge) -> bool:
        """Delete the challenge; True only for the one caller that removed it."""
        with closing(self._connect()) as connection, connection:
            cursor = connection.execute(
                "DELETE FROM pending_challenges WHERE challenger_id = ? AND opponent_id = ? AND created_at = ?",
                (challenge.challenger_id, challenge.opponent_id, _timestamp(challenge.created_at)),
            )
        return cursor.rowcount == 1

    def mark_prompted(self, slack_user_id: str, since: datetime, at: datetime) -> bool:
        """Record a link prompt at `at` unless one was sent at or after `since`; True when recorded."""
        with closing(self._connect()) as connection, connection:
            cursor = connection.execute(
                "INSERT INTO link_prompts (slack_user_id, prompted_at) VALUES (?1, ?2) "
                "ON CONFLICT (slack_user_id) DO UPDATE SET prompted_at = ?2 WHERE prompted_at < ?3",
                (slack_user_id, _timestamp(at), _timestamp(since)),
            )
        return cursor.rowcount == 1

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
