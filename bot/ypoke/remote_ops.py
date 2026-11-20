"""Remote ops: changes a user makes in Slack while their app cannot reach the bot.

A Slack command queues an op for the user. What the bot uses for that user (battles, views) is the last upload with
every still-pending op above the upload's `applied_op_id` replayed on top, in id order. The app fetches the pending
ops, applies them, uploads, then acknowledges them. Op kinds register an `OpKind`. Contract: bot/API.md "Remote ops".
"""

import copy
import json
import logging
import re
import sqlite3
from collections.abc import Callable
from contextlib import closing
from dataclasses import dataclass, replace
from datetime import UTC, datetime

from ypoke.messages import DirectMessage
from ypoke.store import Store, StoredParty
from ypoke.trades import TradeService

OLD_APP_REFUSAL = "앱을 업데이트하고 회사에서 한 번 켜 주세요."
UNSUPPORTED = "unsupported"
CANCEL_REASONS = {UNSUPPORTED: "이 앱 버전은 아직 이 작업을 못 해요"}
DEFAULT_CANCEL_REASON = "앱에서 적용하지 못했어요"
RESULT_HEADER = "회사에서 앱이 동기화하며 슬랙에서 한 작업을 처리했어요."
MAX_ACK_IDS = 500
MAX_LISTED_ITEMS = 2000
_REASON = re.compile(r"[a-z][a-z0-9_]{0,39}")

log = logging.getLogger(__name__)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS remote_ops (
    slack_user_id TEXT NOT NULL,
    id INTEGER NOT NULL,
    kind TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'pending',
    reason TEXT,
    resolved_at TEXT,
    PRIMARY KEY (slack_user_id, id)
);
"""


@dataclass(frozen=True)
class Op:
    id: int
    kind: str
    payload: dict
    created_at: str


@dataclass(frozen=True)
class View:
    """The user as the bot sees them now. `pending` are the ops replayed on top of the upload, in order.
    `bag` and `shop` are the app's lists (`{"key", "name", "count"}` and `{"key", "name", "price", …}`)."""

    party: list[dict]
    pool: list[dict]
    bag: list[dict]
    wallet: int | None
    shop: list[dict]
    uploaded_at: str
    remote_ops: bool
    pending: tuple[Op, ...]


@dataclass(frozen=True)
class OpKind:
    """One kind of remote op. `replay` returns the view with the op's effect (the view it gets is a copy it may
    change); it leaves the view as it is when the op's target is not there. `describe` is a short Korean line."""

    name: str
    describe: Callable[[dict], str]
    replay: Callable[[View, dict], View]


OP_KINDS: dict[str, OpKind] = {}


def register(kind: OpKind) -> None:
    OP_KINDS[kind.name] = kind


@dataclass(frozen=True)
class Submitted:
    """A queued op's id, or the one line that says why it was not queued."""

    op_id: int | None = None
    refusal: str | None = None


class RemoteOps:
    def __init__(self, store: Store, now: Callable[[], datetime] = lambda: datetime.now(UTC)):
        self._store = store
        self._pools = TradeService(store, now)
        self._now = now
        with closing(store._connect()) as connection, connection:
            connection.executescript(_SCHEMA)

    def party(self, user_id: str) -> StoredParty | None:
        """The stored party with the pending ops replayed; what battles use."""
        stored = self._store.party(user_id)
        if stored is None or not _unapplied(self.pending(user_id), stored):
            return stored
        return replace(stored, party=self.view(user_id).party)

    def view(self, user_id: str) -> View | None:
        """None while the user has no upload."""
        stored = self._store.party(user_id)
        if stored is None:
            return None
        remote = stored.remote or {}
        pending = _unapplied(self.pending(user_id), stored)
        view = View(
            party=stored.party, pool=self._pools.pool(user_id), bag=remote.get("bag", []), wallet=remote.get("wallet"),
            shop=remote.get("shop", []), uploaded_at=stored.uploaded_at, remote_ops=bool(remote.get("remote_ops")),
            pending=tuple(pending),
        )
        for op in pending:
            view = _replay(view, op)
        return view

    def submit(self, user_id: str, kind: str, payload: dict) -> Submitted:
        """Queue an op of a registered `kind`; its effect shows in the next view and battle."""
        if kind not in OP_KINDS:
            raise ValueError(f"unknown op kind {kind}")
        refusal = self.edit_refusal(user_id)
        if refusal:
            return Submitted(refusal=refusal)
        with closing(self._store._connect()) as connection, connection:
            (op_id,) = connection.execute(
                "INSERT INTO remote_ops (slack_user_id, id, kind, payload_json, created_at) "
                "SELECT ?1, COALESCE(MAX(id), 0) + 1, ?2, ?3, ?4 FROM remote_ops WHERE slack_user_id = ?1 RETURNING id",
                (user_id, kind, json.dumps(payload, ensure_ascii=False), _stamp(self._now())),
            ).fetchone()
        return Submitted(op_id=op_id)

    def edit_refusal(self, user_id: str) -> str | None:
        """Why the user cannot queue an op: their last upload came from an app that cannot apply them (or none came)."""
        stored = self._store.party(user_id)
        return None if stored is not None and (stored.remote or {}).get("remote_ops") else OLD_APP_REFUSAL

    def pending(self, user_id: str) -> list[Op]:
        """Every op the user's app has not acknowledged, oldest first."""
        with closing(self._store._connect()) as connection:
            rows = connection.execute(
                "SELECT id, kind, payload_json, created_at FROM remote_ops "
                "WHERE slack_user_id = ? AND state = 'pending' ORDER BY id",
                (user_id,),
            ).fetchall()
        return [Op(op_id, kind, json.loads(payload), created_at) for op_id, kind, payload, created_at in rows]

    def ack(self, user_id: str, applied: list[int], cancelled: list[tuple[int, str]]) -> DirectMessage | None:
        """Settle pending ops. Only ops this call moved out of pending count, so a repeated ack changes nothing;
        returns the DM listing them, or None when nothing moved."""
        settled: list[tuple[int, str, dict, str | None]] = []
        with closing(self._store._connect()) as connection, connection:
            for op_id in applied[:MAX_ACK_IDS]:
                settled += self._settle(connection, user_id, op_id, "applied", None)
            for op_id, reason in cancelled[:MAX_ACK_IDS]:
                settled += self._settle(connection, user_id, op_id, "cancelled", reason)
        if not settled:
            return None
        lines = [RESULT_HEADER]
        for _, kind, payload, reason in sorted(settled):
            text = describe(kind, payload)
            lines.append(f"✅ {text}" if reason is None else f"❌ {text}: {cancel_text(reason)}")
        return DirectMessage(user_id, "\n".join(lines))

    def _settle(
        self, connection: sqlite3.Connection, user_id: str, op_id: int, state: str, reason: str | None
    ) -> list[tuple[int, str, dict, str | None]]:
        rows = connection.execute(
            "UPDATE remote_ops SET state = ?, reason = ?, resolved_at = ? "
            "WHERE slack_user_id = ? AND id = ? AND state = 'pending' RETURNING id, kind, payload_json",
            (state, reason, _stamp(self._now()), user_id, op_id),
        ).fetchall()
        return [(row_id, kind, json.loads(payload), reason) for row_id, kind, payload in rows]


def _unapplied(pending: list[Op], stored: StoredParty) -> list[Op]:
    applied_up_to = (stored.remote or {}).get("applied_op_id", 0)
    return [op for op in pending if op.id > applied_up_to]


def describe(kind: str, payload: dict) -> str:
    op_kind = OP_KINDS.get(kind)
    return op_kind.describe(payload) if op_kind else f"알 수 없는 작업({kind})"


def cancel_text(reason: str) -> str:
    return CANCEL_REASONS.get(reason, DEFAULT_CANCEL_REASON)


def is_reason(value: object) -> bool:
    return isinstance(value, str) and _REASON.fullmatch(value) is not None


def normalize_remote(payload: dict) -> dict | None:
    """The remote-ops part of an upload, or None from an app that cannot apply ops. Malformed parts are dropped,
    never a 400."""
    if payload.get("remote_ops") != 1:
        return None
    applied = payload.get("applied_op_id")
    wallet = payload.get("wallet")
    return {
        "remote_ops": True,
        "applied_op_id": applied if _is_count(applied) else 0,
        "wallet": wallet if _is_count(wallet) else None,
        "bag": _lines(payload.get("bag"), _bag_line),
        "shop": _lines(payload.get("shop"), _shop_line),
    }


def _replay(view: View, op: Op) -> View:
    op_kind = OP_KINDS.get(op.kind)
    if op_kind is None:
        return view
    try:
        return op_kind.replay(copy.deepcopy(view), op.payload)
    except Exception:
        log.exception("replaying op %s (%s) failed", op.id, op.kind)
        return view


def _lines(raw: object, normalize: Callable[[object], dict | None]) -> list[dict]:
    if not isinstance(raw, list):
        return []
    return [line for line in map(normalize, raw[:MAX_LISTED_ITEMS]) if line is not None]


def _bag_line(raw: object) -> dict | None:
    if not isinstance(raw, dict) or not _is_count(raw.get("count")) or raw["count"] == 0:
        return None
    key, name = _text(raw.get("key"), 80), _text(raw.get("name"), 60)
    return {"key": key, "name": name, "count": raw["count"]} if key and name else None


def _shop_line(raw: object) -> dict | None:
    if not isinstance(raw, dict) or not _is_count(raw.get("price")):
        return None
    key, name = _text(raw.get("key"), 80), _text(raw.get("name"), 60)
    if not (key and name):
        return None
    line = {"key": key, "name": name, "price": raw["price"], "single": raw.get("single") is True}
    category = _text(raw.get("category"), 20)
    if category:
        line["category"] = category
    return line


def _text(value: object, limit: int) -> str | None:
    if not isinstance(value, str) or not value.strip():
        return None
    return value.strip()[:limit]


def _is_count(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _stamp(moment: datetime) -> str:
    return moment.astimezone(UTC).isoformat(timespec="seconds")
