"""Trades of graduated Pokémon between two linked users.

The app uploads a `trade_pool` (its tradable individuals); one user offers one of theirs to another in the
app, the other picks one back in a Slack DM, and both press accept. A completed trade stays in each side's
delivery list until that app acknowledges it. Contract: bot/API.md.
"""

import json
import sqlite3
import uuid
from collections.abc import Callable
from contextlib import closing
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from ypoke.messages import DirectMessage
from ypoke.store import Store

TRADE_LIFETIME = timedelta(hours=24)
HISTORY_WINDOW = timedelta(days=3)
MAX_POOL = 100
MAX_ENTRY_BYTES = 4096
MAX_OPEN_OFFERS = 3
PICK_ACTION_ID = "trade_pick"
ACCEPT_ACTION_ID = "trade_accept"
DECLINE_ACTION_ID = "trade_decline"
OPEN_STATUSES = ("offered", "countered")
DEFAULT_PARTNER = "동료"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS trade_pools (
    slack_user_id TEXT PRIMARY KEY,
    pool_json TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS trades (
    id TEXT PRIMARY KEY,
    proposer_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    give_id TEXT NOT NULL,
    give_json TEXT NOT NULL,
    back_id TEXT,
    back_json TEXT,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    proposer_applied INTEGER NOT NULL DEFAULT 0,
    target_applied INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS trades_proposer ON trades (proposer_id);
CREATE INDEX IF NOT EXISTS trades_target ON trades (target_id);
"""

_NOT_YOURS = "이 교환은 당신 차례가 아니에요."
_NOT_TRADABLE = "그 포켓몬은 지금 교환할 수 없어요. 앱에서 키우는 포켓몬이나 대결에 내보낸 포켓몬은 먼저 바꿔 주세요."

NameFor = Callable[[str], str | None]

PROPOSE_ERRORS = {
    "self": "자기 자신과는 교환할 수 없어요.",
    "unknown_user": "그 사람은 아직 교환할 수 있는 포켓몬을 올리지 않았어요.",
    "unknown_individual": "그 포켓몬은 교환할 수 없어요. 키우는 포켓몬이나 대결에 내보낸 포켓몬은 먼저 바꿔 주세요.",
    "locked": "그 포켓몬은 이미 다른 교환에 걸려 있어요.",
    "too_many": "진행 중인 교환 제안이 너무 많아요. 끝난 뒤에 다시 해 주세요.",
}


@dataclass(frozen=True)
class Trade:
    id: str
    proposer_id: str
    target_id: str
    give_id: str
    give: dict
    back_id: str | None
    back: dict | None
    status: str
    created_at: datetime
    proposer_applied: bool
    target_applied: bool


@dataclass(frozen=True)
class TradeReply:
    """What a Slack button press answers. `final` replaces the DM that held the buttons; a refusal keeps them."""

    text: str
    ok: bool = True
    final: bool = False
    direct_messages: tuple[DirectMessage, ...] = ()


@dataclass(frozen=True)
class ProposeResult:
    trade_id: str | None = None
    error: str | None = None
    direct_messages: tuple[DirectMessage, ...] = ()


class TradeService:
    def __init__(
        self,
        store: Store,
        now: Callable[[], datetime] = lambda: datetime.now(UTC),
        name_for: NameFor = lambda user_id: None,
        bot_user_id: str | None = None,
    ):
        self._store = store
        self._now = now
        self._name_for = name_for
        self._bot_user_id = bot_user_id
        with closing(self._connect()) as connection, connection:
            connection.executescript(_SCHEMA)

    def save_pool(self, user_id: str, raw_pool: object) -> None:
        """Keep the user's tradable individuals; a pool that is not a list is ignored so a bad pool never blocks an upload."""
        pool = normalize_pool(raw_pool)
        if pool is None:
            return
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT INTO trade_pools (slack_user_id, pool_json, updated_at) VALUES (?1, ?2, ?3) "
                "ON CONFLICT (slack_user_id) DO UPDATE SET pool_json = ?2, updated_at = ?3",
                (user_id, json.dumps(pool, ensure_ascii=False), _stamp(self._now())),
            )

    def coworkers(self, user_id: str) -> list[dict]:
        """Everyone else with something to trade."""
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT slack_user_id, pool_json FROM trade_pools WHERE slack_user_id != ?", (user_id,)
            ).fetchall()
        return [
            {"id": other, "name": self._name(other)}
            for other, pool_json in rows
            if other != self._bot_user_id and json.loads(pool_json)
        ]

    def propose(self, user_id: str, to_id: str, give_id: str) -> ProposeResult:
        """An offer of the user's `give_id` to `to_id`, who gets a DM to pick one back."""
        self._expire()
        error = self._proposal_error(user_id, to_id, give_id)
        if error:
            return ProposeResult(error=error)
        give = self._pool_entry(user_id, give_id)
        trade = Trade(uuid.uuid4().hex, user_id, to_id, give_id, give, None, None, "offered", self._now(), False, False)
        self._insert(trade)
        return ProposeResult(trade.id, direct_messages=(self._offer_dm(trade),))

    def pick(self, user_id: str, trade_id: str, individual_id: str) -> TradeReply:
        """The target chooses which of their Pokémon to give back."""
        self._expire()
        trade = self._get(trade_id)
        refusal = self._refusal(trade, user_id, "offered", target_side=True)
        if refusal:
            return refusal
        back = self._pool_entry(user_id, individual_id)
        if back is None:
            return TradeReply(_NOT_TRADABLE, ok=False)
        if individual_id in self._locked_ids(user_id, except_trade=trade_id):
            return TradeReply(PROPOSE_ERRORS["locked"], ok=False)
        self._update(trade_id, "UPDATE trades SET back_id = ?, back_json = ? WHERE id = ? AND status = 'offered'",
                     (individual_id, json.dumps(back, ensure_ascii=False), trade_id))
        return TradeReply(f"{_label(back)}을(를) 골랐어요. 수락을 누르면 상대 확인을 기다려요.")

    def accept(self, user_id: str, trade_id: str) -> TradeReply:
        """The target accepts with their pick, then the proposer confirms; the second accept completes the trade."""
        self._expire()
        trade = self._get(trade_id)
        if trade is not None and user_id == trade.target_id and trade.status == "offered":
            return self._counter(trade)
        if trade is not None and user_id == trade.proposer_id and trade.status == "countered":
            return self._complete(trade)
        return self._refusal(trade, user_id, "offered", target_side=True) or TradeReply(_NOT_YOURS, ok=False)

    def decline(self, user_id: str, trade_id: str) -> TradeReply:
        """Either side ends an open offer."""
        self._expire()
        trade = self._get(trade_id)
        if trade is None or user_id not in (trade.proposer_id, trade.target_id):
            return TradeReply(_NOT_YOURS, ok=False)
        if trade.status not in OPEN_STATUSES:
            return TradeReply(_status_text(trade.status), ok=False, final=True)
        self._update(trade_id, "UPDATE trades SET status = 'declined' WHERE id = ? AND status IN ('offered', 'countered')", (trade_id,))
        other = trade.target_id if user_id == trade.proposer_id else trade.proposer_id
        notice = DirectMessage(other, f"<@{user_id}>님이 교환 {_label(trade.give)} 건을 거절했어요.")
        return TradeReply("교환을 거절했어요.", final=True, direct_messages=(notice,))

    def deliveries(self, user_id: str) -> list[dict]:
        """Completed trades this user's app has not acknowledged yet."""
        self._expire()
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT * FROM trades WHERE status = 'completed' AND "
                "((proposer_id = ?1 AND proposer_applied = 0) OR (target_id = ?1 AND target_applied = 0)) "
                "ORDER BY created_at",
                (user_id,),
            ).fetchall()
        return [self._delivery(_trade(row), user_id) for row in rows]

    def ack(self, user_id: str, trade_ids: list[str]) -> None:
        with closing(self._connect()) as connection, connection:
            for trade_id in trade_ids:
                connection.execute("UPDATE trades SET proposer_applied = 1 WHERE id = ? AND proposer_id = ?", (trade_id, user_id))
                connection.execute("UPDATE trades SET target_applied = 1 WHERE id = ? AND target_id = ?", (trade_id, user_id))

    def history(self, user_id: str) -> list[dict]:
        """The user's open trades and the recently ended ones, newest first."""
        self._expire()
        since = _stamp(self._now() - HISTORY_WINDOW)
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT * FROM trades WHERE (proposer_id = ?1 OR target_id = ?1) AND created_at >= ?2 "
                "ORDER BY created_at DESC LIMIT 20",
                (user_id, since),
            ).fetchall()
        return [self._summary(_trade(row), user_id) for row in rows]

    def _counter(self, trade: Trade) -> TradeReply:
        if trade.back is None:
            return TradeReply("먼저 내놓을 포켓몬을 골라 주세요.", ok=False)
        if self._pool_entry(trade.target_id, trade.back_id) is None:
            return TradeReply(_NOT_TRADABLE, ok=False)
        self._update(trade.id, "UPDATE trades SET status = 'countered' WHERE id = ? AND status = 'offered'", (trade.id,))
        confirm = DirectMessage(trade.proposer_id, _confirm_text(trade, self._name(trade.target_id)), _confirm_blocks(trade, self._name(trade.target_id)))
        return TradeReply("수락했어요. 상대가 확인하면 교환이 끝나요.", final=True, direct_messages=(confirm,))

    def _complete(self, trade: Trade) -> TradeReply:
        if self._pool_entry(trade.proposer_id, trade.give_id) is None:
            return TradeReply(f"{_label(trade.give)}은(는) 지금 교환할 수 없어요. 앱에서 대결·육성에 쓰고 있지 않은지 확인해 주세요.", ok=False)
        if self._pool_entry(trade.target_id, trade.back_id) is None:
            return TradeReply(f"상대의 {_label(trade.back)}은(는) 지금 교환할 수 없어요. 상대가 앱에서 바꾸면 다시 눌러 주세요.", ok=False)
        done = self._update(trade.id, "UPDATE trades SET status = 'completed' WHERE id = ? AND status = 'countered'", (trade.id,))
        if not done:
            return TradeReply(_status_text(self._get(trade.id).status), ok=False, final=True)
        text = f"교환이 끝났어요! {_label(trade.give)} ↔ {_label(trade.back)}. 앱을 켜 두면 곧 도착해요."
        notice = DirectMessage(trade.target_id, text)
        return TradeReply(text, final=True, direct_messages=(notice,))

    def _refusal(self, trade: Trade | None, user_id: str, status: str, target_side: bool) -> TradeReply | None:
        if trade is None or user_id != (trade.target_id if target_side else trade.proposer_id):
            return TradeReply(_NOT_YOURS, ok=False)
        if trade.status != status:
            return TradeReply(_status_text(trade.status), ok=False, final=trade.status not in OPEN_STATUSES)
        return None

    def _proposal_error(self, user_id: str, to_id: str, give_id: str) -> str | None:
        if to_id == user_id:
            return "self"
        if to_id == self._bot_user_id or not self._pool(to_id):
            return "unknown_user"
        if self._pool_entry(user_id, give_id) is None:
            return "unknown_individual"
        if give_id in self._locked_ids(user_id):
            return "locked"
        if self._open_offers(user_id) >= MAX_OPEN_OFFERS:
            return "too_many"
        return None

    def _offer_dm(self, trade: Trade) -> DirectMessage:
        locked = self._locked_ids(trade.target_id)
        options = [_option(trade.id, entry) for entry in self._pool(trade.target_id) if entry["id"] not in locked]
        proposer = self._name(trade.proposer_id)
        text = f"<@{trade.proposer_id}>님이 {_label(trade.give)}을(를) 내놓고 교환을 제안했어요. 24시간 안에 답해 주세요."
        blocks: list[dict] = [{"type": "section", "text": {"type": "mrkdwn", "text": f"*교환 제안*\n{text}"}}]
        buttons = [{"type": "button", "action_id": DECLINE_ACTION_ID, "value": trade.id,
                    "text": {"type": "plain_text", "text": "거절"}}]
        if options:
            blocks.append({"type": "actions", "elements": [{
                "type": "static_select", "action_id": PICK_ACTION_ID,
                "placeholder": {"type": "plain_text", "text": "내가 내놓을 포켓몬 고르기"},
                "options": options,
            }]})
            buttons.insert(0, {"type": "button", "style": "primary", "action_id": ACCEPT_ACTION_ID, "value": trade.id,
                               "text": {"type": "plain_text", "text": "수락"}})
        else:
            blocks.append({"type": "context", "elements": [{"type": "mrkdwn", "text": "지금 내놓을 수 있는 포켓몬이 없어서 거절만 할 수 있어요."}]})
        blocks.append({"type": "actions", "elements": buttons})
        blocks.append({"type": "context", "elements": [{"type": "mrkdwn", "text": f"{proposer}님의 앱과 내 앱이 켜져 있어야 포켓몬이 오가요."}]})
        return DirectMessage(trade.target_id, text, blocks)

    def _delivery(self, trade: Trade, user_id: str) -> dict:
        mine = user_id == trade.proposer_id
        received, given_id = (trade.back, trade.give_id) if mine else (trade.give, trade.back_id)
        sender = trade.target_id if mine else trade.proposer_id
        return {"trade_id": trade.id, "give_id": given_id, "from_name": self._name(sender), "receive": received}

    def _summary(self, trade: Trade, user_id: str) -> dict:
        mine = user_id == trade.proposer_id
        other = trade.target_id if mine else trade.proposer_id
        return {
            "trade_id": trade.id,
            "status": trade.status,
            "direction": "outgoing" if mine else "incoming",
            "with_name": self._name(other),
            "give": _brief(trade.give if mine else trade.back),
            "want": _brief(trade.back if mine else trade.give),
            "expires_at": _stamp(trade.created_at + TRADE_LIFETIME),
        }

    def _locked_ids(self, user_id: str, except_trade: str | None = None) -> set[str]:
        """The user's individuals tied up in open trades: what they offered, and what they picked back."""
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT give_id FROM trades WHERE status IN ('offered', 'countered') AND proposer_id = ?1 AND id != ?2 "
                "UNION SELECT back_id FROM trades WHERE status IN ('offered', 'countered') AND target_id = ?1 "
                "AND back_id IS NOT NULL AND id != ?2",
                (user_id, except_trade or ""),
            ).fetchall()
        return {row[0] for row in rows}

    def _open_offers(self, user_id: str) -> int:
        with closing(self._connect()) as connection:
            return connection.execute(
                "SELECT COUNT(*) FROM trades WHERE proposer_id = ? AND status IN ('offered', 'countered')", (user_id,)
            ).fetchone()[0]

    def _pool(self, user_id: str) -> list[dict]:
        with closing(self._connect()) as connection:
            row = connection.execute("SELECT pool_json FROM trade_pools WHERE slack_user_id = ?", (user_id,)).fetchone()
        return json.loads(row[0]) if row else []

    def _pool_entry(self, user_id: str, individual_id: str | None) -> dict | None:
        return next((entry for entry in self._pool(user_id) if entry["id"] == individual_id), None)

    def _name(self, user_id: str) -> str:
        return self._name_for(user_id) or DEFAULT_PARTNER

    def _expire(self) -> None:
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "UPDATE trades SET status = 'expired' WHERE status IN ('offered', 'countered') AND created_at < ?",
                (_stamp(self._now() - TRADE_LIFETIME),),
            )

    def _insert(self, trade: Trade) -> None:
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT INTO trades (id, proposer_id, target_id, give_id, give_json, status, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (trade.id, trade.proposer_id, trade.target_id, trade.give_id,
                 json.dumps(trade.give, ensure_ascii=False), trade.status, _stamp(trade.created_at)),
            )

    def _get(self, trade_id: str) -> Trade | None:
        with closing(self._connect()) as connection:
            row = connection.execute("SELECT * FROM trades WHERE id = ?", (trade_id,)).fetchone()
        return _trade(row) if row else None

    def _update(self, trade_id: str, sql: str, params: tuple) -> bool:
        with closing(self._connect()) as connection, connection:
            return connection.execute(sql, params).rowcount == 1

    def _connect(self) -> sqlite3.Connection:
        return self._store._connect()


def normalize_pool(raw: object) -> list[dict] | None:
    """The valid entries of an uploaded `trade_pool` (at most MAX_POOL), or None when it is not a list."""
    if not isinstance(raw, list):
        return None
    pool, seen = [], set()
    for item in raw:
        entry = _normalize_entry(item)
        if entry is not None and entry["id"] not in seen:
            seen.add(entry["id"])
            pool.append(entry)
    return pool[:MAX_POOL]


def _normalize_entry(item: object) -> dict | None:
    if not isinstance(item, dict):
        return None
    individual_id, pokemon_id, level = item.get("id"), item.get("pokemon_id"), item.get("level")
    detail = item.get("entry")
    if not (isinstance(individual_id, str) and 0 < len(individual_id) <= 64 and "|" not in individual_id):
        return None
    if not (_is_int(pokemon_id) and (1 <= pokemon_id <= 1025 or 10001 <= pokemon_id <= 10999)):
        return None
    if not (_is_int(level) and 1 <= level <= 100):
        return None
    if not isinstance(detail, dict) or len(json.dumps(detail, ensure_ascii=False)) > MAX_ENTRY_BYTES:
        return None
    name = item.get("name")
    return {
        "id": individual_id,
        "pokemon_id": pokemon_id,
        "level": level,
        "shiny": item.get("shiny") is True,
        "name": name.strip()[:40] if isinstance(name, str) and name.strip() else f"#{pokemon_id}",
        "entry": detail,
    }


def _status_text(status: str) -> str:
    return {
        "declined": "이미 거절된 교환이에요.",
        "expired": "24시간이 지나 끝난 교환이에요.",
        "completed": "이미 끝난 교환이에요.",
        "countered": "이미 수락해서 상대 확인을 기다리는 중이에요.",
        "offered": "아직 수락 전인 교환이에요.",
    }.get(status, "이 교환은 더 이상 열려 있지 않아요.")


def _confirm_blocks(trade: Trade, target_name: str) -> list[dict]:
    return [
        {"type": "section", "text": {"type": "mrkdwn", "text": f"*교환 확인*\n{_confirm_text(trade, target_name)}"}},
        {"type": "actions", "elements": [
            {"type": "button", "style": "primary", "action_id": ACCEPT_ACTION_ID, "value": trade.id,
             "text": {"type": "plain_text", "text": "교환하기"}},
            {"type": "button", "action_id": DECLINE_ACTION_ID, "value": trade.id,
             "text": {"type": "plain_text", "text": "거절"}},
        ]},
    ]


def _confirm_text(trade: Trade, target_name: str) -> str:
    return (f"<@{trade.target_id}>님이 {_label(trade.back)}을(를) 내놓고 수락했어요. "
            f"내 {_label(trade.give)}과(와) 바꿀까요?")


def _option(trade_id: str, entry: dict) -> dict:
    return {"text": {"type": "plain_text", "text": _label(entry)[:75]}, "value": f"{trade_id}|{entry['id']}"}


def _label(entry: dict | None) -> str:
    if entry is None:
        return "?"
    return f"{entry['name']} Lv.{entry['level']}{' ✨' if entry['shiny'] else ''}"


def _brief(entry: dict | None) -> dict | None:
    if entry is None:
        return None
    return {key: entry[key] for key in ("id", "pokemon_id", "level", "shiny", "name")}


def _trade(row: tuple) -> Trade:
    (trade_id, proposer_id, target_id, give_id, give_json, back_id, back_json, status, created_at,
     proposer_applied, target_applied) = row
    return Trade(trade_id, proposer_id, target_id, give_id, json.loads(give_json), back_id,
                 json.loads(back_json) if back_json else None, status, datetime.fromisoformat(created_at),
                 bool(proposer_applied), bool(target_applied))


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _stamp(moment: datetime) -> str:
    return moment.astimezone(UTC).isoformat(timespec="seconds")
