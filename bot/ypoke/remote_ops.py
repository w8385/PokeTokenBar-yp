"""Remote ops: changes a user makes in Slack while their app cannot reach the bot.

A Slack command queues an op for the user. What the bot uses for that user (battles, views) is the last upload with
every still-pending op above the upload's `applied_op_id` replayed on top, in id order. The app fetches the pending
ops, applies them, uploads, then acknowledges them. Op kinds register an `OpKind`. Contract: bot/API.md "Remote ops".
"""

import copy
import json
import logging
import re
import secrets
import sqlite3
from collections.abc import Callable, Mapping
from contextlib import closing
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime

from ypoke.messages import DirectMessage
from ypoke.store import Lead, Store, StoredParty
from ypoke.trades import IN_LINEUP, PENDING_CHANGE, TradeService

OLD_APP_REFUSAL = "앱을 업데이트하고 회사에서 한 번 켜 주세요."
UNSUPPORTED = "unsupported"
CANCEL_REASONS = {UNSUPPORTED: "이 앱 버전은 아직 이 작업을 못 해요"}
DEFAULT_CANCEL_REASON = "앱에서 적용하지 못했어요"
RESULT_HEADER = "회사에서 앱이 동기화하며 슬랙에서 한 작업을 처리했어요."
MAX_ACK_IDS = 500
MAX_LISTED_ITEMS = 2000
MAX_KINDS = 20
_REASON = re.compile(r"[a-z][a-z0-9_]{0,39}")
_KIND = re.compile(r"[a-z][a-z0-9_]{0,39}")
_SLUG = re.compile(r"[a-z0-9][a-z0-9-]{0,39}")

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
CREATE TABLE IF NOT EXISTS remote_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
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
    `bag` and `shop` are the app's lists (`{"key", "name", "count"}` and `{"key", "name", "price", …}`).
    `bench` are the party members (with `id`) the user owns outside the party and may put in it: the Box Pokémon
    not tied up in a trade. `kinds` are the op kinds the user's app applies."""

    party: list[dict]
    pool: list[dict]
    bag: list[dict]
    wallet: int | None
    shop: list[dict]
    uploaded_at: str
    remote_ops: bool
    pending: tuple[Op, ...]
    bench: list[dict] = field(default_factory=list)
    kinds: frozenset[str] = frozenset()


@dataclass(frozen=True)
class OpKind:
    """One kind of remote op. `replay` returns the view with the op's effect (the view it gets is a copy it may
    change); it leaves the view as it is when the op's target is not there. `describe` is a short Korean line.
    `reasons` words the cancel codes the app sends for it. With `supersedes`, a new op of the kind replaces the
    user's pending ones (each carries the whole target), so the result DM lists only the last. `changes` names the
    individuals the op edits; they cannot be traded until the app has applied it."""

    name: str
    describe: Callable[[dict], str]
    replay: Callable[[View, dict], View]
    reasons: Mapping[str, str] = field(default_factory=dict)
    supersedes: bool = False
    changes: Callable[[dict], list[str]] = lambda payload: []


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
            connection.execute("INSERT OR IGNORE INTO remote_meta (key, value) VALUES ('epoch', ?)",
                               (secrets.token_hex(8),))
            (self.epoch,) = connection.execute("SELECT value FROM remote_meta WHERE key = 'epoch'").fetchone()

    def leads_except(self, user_id: str, since: datetime, limit: int) -> list[Lead]:
        """`Store.leads_except` with each user's pending ops replayed, so a lineup changed in Slack shows at once."""
        leads = []
        for lead in self._store.leads_except(user_id, since, limit):
            stored = self.party(lead.user_id)
            first = stored.party[0] if stored and stored.party else None
            leads.append(lead if first is None else Lead(lead.user_id, first["pokemon_id"], first["level"],
                                                         first.get("shiny", False)))
        return leads

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
        bench = [entry["member"] for entry in self._pools.free_entries(user_id) if "member" in entry]
        view = View(
            party=stored.party, pool=self._pools.pool(user_id), bag=remote.get("bag", []), wallet=remote.get("wallet"),
            shop=remote.get("shop", []), uploaded_at=stored.uploaded_at, remote_ops=bool(remote.get("remote_ops")),
            pending=tuple(pending), bench=bench, kinds=frozenset(remote.get("kinds", ())),
        )
        for op in pending:
            view = _replay(view, op)
        return view

    def holds(self, user_id: str) -> dict[str, str]:
        """The user's individuals that may not be traded until the app syncs, with the `trades.HOLD_ERRORS` code:
        those in the replayed battle lineup, and those a pending op changes."""
        view = self.view(user_id)
        if view is None:
            return {}
        held = {individual_id: PENDING_CHANGE for op in view.pending if op.kind in OP_KINDS
                for individual_id in OP_KINDS[op.kind].changes(op.payload)}
        return held | {member["id"]: IN_LINEUP for member in view.party if "id" in member}

    def submit(self, user_id: str, kind: str, payload: dict) -> Submitted:
        """Queue an op of a registered `kind`; its effect shows in the next view and battle."""
        if kind not in OP_KINDS:
            raise ValueError(f"unknown op kind {kind}")
        refusal = self.edit_refusal(user_id, kind)
        if refusal:
            return Submitted(refusal=refusal)
        with closing(self._store._connect()) as connection, connection:
            if OP_KINDS[kind].supersedes:
                connection.execute(
                    "UPDATE remote_ops SET state = 'superseded', resolved_at = ? "
                    "WHERE slack_user_id = ? AND kind = ? AND state = 'pending'",
                    (_stamp(self._now()), user_id, kind),
                )
            (op_id,) = connection.execute(
                "INSERT INTO remote_ops (slack_user_id, id, kind, payload_json, created_at) "
                "SELECT ?1, COALESCE(MAX(id), 0) + 1, ?2, ?3, ?4 FROM remote_ops WHERE slack_user_id = ?1 RETURNING id",
                (user_id, kind, json.dumps(payload, ensure_ascii=False), _stamp(self._now())),
            ).fetchone()
        return Submitted(op_id=op_id)

    def edit_refusal(self, user_id: str, kind: str | None = None) -> str | None:
        """Why the user cannot queue an op (of `kind`): their last upload came from an app that cannot apply it, or
        none came."""
        remote = (stored.remote or {}) if (stored := self._store.party(user_id)) is not None else {}
        if not remote.get("remote_ops") or (kind is not None and kind not in remote.get("kinds", ())):
            return OLD_APP_REFUSAL
        return None

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
            lines.append(f"✅ {text}" if reason is None else f"❌ {text}: {cancel_text(reason, kind)}")
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


def cancel_text(reason: str, kind: str | None = None) -> str:
    op_kind = OP_KINDS.get(kind) if kind else None
    return (op_kind.reasons.get(reason) if op_kind else None) or CANCEL_REASONS.get(reason, DEFAULT_CANCEL_REASON)


def is_reason(value: object) -> bool:
    return isinstance(value, str) and _REASON.fullmatch(value) is not None


def normalize_remote(payload: dict, epoch: str | None = None) -> dict | None:
    """The remote-ops part of an upload, or None from an app that cannot apply ops. Malformed parts are dropped,
    never a 400. An `applied_op_id` counted against another bot database (`ops_epoch` other than `epoch`) is 0."""
    if payload.get("remote_ops") != 1:
        return None
    applied = payload.get("applied_op_id")
    wallet = payload.get("wallet")
    kinds = payload.get("remote_ops_kinds")
    same_epoch = epoch is None or payload.get("ops_epoch") in (None, epoch)
    return {
        "remote_ops": True,
        "applied_op_id": applied if _is_count(applied) and same_epoch else 0,
        "wallet": wallet if _is_count(wallet) else None,
        "bag": _lines(payload.get("bag"), _bag_line),
        "shop": _lines(payload.get("shop"), _shop_line),
        "kinds": sorted({kind for kind in kinds[:MAX_KINDS] if isinstance(kind, str) and _KIND.fullmatch(kind)})
        if isinstance(kinds, list) else [],
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
    if not (key and name):
        return None
    return {"key": key, "name": name, "count": raw["count"]} | _equip(raw)


def _shop_line(raw: object) -> dict | None:
    if not isinstance(raw, dict) or not _is_count(raw.get("price")):
        return None
    key, name = _text(raw.get("key"), 80), _text(raw.get("name"), 60)
    if not (key and name):
        return None
    line = {"key": key, "name": name, "price": raw["price"], "single": raw.get("single") is True}
    for field_name in ("category", "category_name"):
        if value := _text(raw.get(field_name), 20):
            line[field_name] = value
    return line | _equip(raw)


def _equip(raw: dict) -> dict:
    if raw.get("equip") is not True:
        return {}
    slug = raw.get("held_item")
    return {"equip": True, "held_item": slug} if isinstance(slug, str) and _SLUG.fullmatch(slug) else {"equip": True}


def _text(value: object, limit: int) -> str | None:
    if not isinstance(value, str) or not value.strip():
        return None
    return value.strip()[:limit]


def _is_count(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _stamp(moment: datetime) -> str:
    return moment.astimezone(UTC).isoformat(timespec="seconds")
