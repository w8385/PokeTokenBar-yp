"""Trades of graduated Pokémon between two linked users.

The app uploads a `trade_pool` (its tradable individuals); one user offers one of theirs to another in the
app, the other picks one back in a Slack DM, and both press accept. A completed trade stays in each side's
delivery list until that app acknowledges it. Contract: bot/API.md.
"""

import json
import sqlite3
import uuid
from collections import Counter
from collections.abc import Callable, Mapping
from contextlib import closing
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from ypoke import blocks as kit
from ypoke.clock import Clock
from ypoke.messages import DirectMessage
from ypoke.store import Store

TRADE_LIFETIME = timedelta(hours=24)
HISTORY_WINDOW = timedelta(days=3)
MAX_POOL = 2000
HELD_ITEM_KEY = "tradeHeldItem"
MAX_ENTRY_BYTES = 4096
MAX_OPEN_OFFERS = 3
PICK_ACTION_ID = "trade_pick"
ACCEPT_ACTION_ID = "trade_accept"
DECLINE_ACTION_ID = "trade_decline"
OPEN_STATUSES = ("offered", "countered")
DEFAULT_PARTNER = "동료"
OPTION_TEXT_LIMIT = 75
PICKER_LIMIT = 100
DUPLICATE_SUFFIX_ROOM = len(f" #{MAX_POOL}")
GENDER_SYMBOLS = {"male": "♂", "female": "♀"}
NATURE_NAMES_KO = {
    "hardy": "노력", "lonely": "외로움", "brave": "용감", "adamant": "고집", "naughty": "개구쟁이",
    "bold": "대담", "docile": "온순", "relaxed": "무사태평", "impish": "장난꾸러기", "lax": "촐랑",
    "timid": "겁쟁이", "hasty": "성급", "serious": "성실", "jolly": "명랑", "naive": "천진난만",
    "modest": "조심", "mild": "의젓", "quiet": "냉정", "bashful": "수줍음", "rash": "덜렁",
    "calm": "차분", "gentle": "얌전", "sassy": "건방", "careful": "신중", "quirky": "변덕",
}

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
CREATE TABLE IF NOT EXISTS trade_handles (
    slack_user_id TEXT PRIMARY KEY,
    handle TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS trades_proposer ON trades (proposer_id);
CREATE INDEX IF NOT EXISTS trades_target ON trades (target_id);
CREATE TABLE IF NOT EXISTS miracle_offers (
    id TEXT PRIMARY KEY,
    poster_id TEXT NOT NULL,
    give_id TEXT NOT NULL,
    give_json TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    card_ts TEXT,
    acceptor_id TEXT,
    back_json TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS miracle_one_open ON miracle_offers (poster_id) WHERE status = 'open';
"""

_NOT_YOURS = "이 교환은 당신 차례가 아니에요."
_NOT_TRADABLE = "그 포켓몬은 지금 교환할 수 없어요. 앱에서 키우는 포켓몬이나 대결에 내보낸 포켓몬은 먼저 바꿔 주세요."

UNKNOWN_INDIVIDUAL = "그 포켓몬 정보가 아직 봇에 없어요. 앱을 열어 동기화한 뒤 다시 해 주세요."

NameFor = Callable[[str], str | None]
Holds = Callable[[str], Mapping[str, str]]

IN_LINEUP = "in_lineup"
PENDING_CHANGE = "pending_change"
HOLD_ERRORS = {
    IN_LINEUP: "대결 라인업에 넣은 포켓몬은 교환할 수 없어요. `/파티`에서 빼고 다시 해 주세요.",
    PENDING_CHANGE: "슬랙에서 바꾼 내용이 아직 앱에 들어가지 않은 포켓몬이에요. 회사에서 앱이 한 번 동기화한 뒤 다시 해 주세요.",
}

PROPOSE_ERRORS = {
    "self": "자기 자신과는 교환할 수 없어요.",
    "unknown_user": "그 사람은 아직 교환할 수 있는 포켓몬을 올리지 않았어요.",
    "unknown_individual": UNKNOWN_INDIVIDUAL,
    "locked": "그 포켓몬은 이미 다른 교환에 걸려 있어요.",
    "too_many": "진행 중인 교환 제안이 너무 많아요. 끝난 뒤에 다시 해 주세요.",
    **HOLD_ERRORS,
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
        now: Clock,
        name_for: NameFor = lambda user_id: None,
        bot_user_id: str | None = None,
        holds: Holds = lambda user_id: {},
    ):
        """`holds` names the individuals a user may not trade yet and why (`HOLD_ERRORS`): what their Slack edits,
        not yet applied by the app, put in the battle lineup or changed (`RemoteOps.holds`)."""
        self._store = store
        self._now = now
        self._name_for = name_for
        self._bot_user_id = bot_user_id
        self._holds = holds
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
                "SELECT slack_user_id FROM trade_pools WHERE slack_user_id != ? AND pool_json != '[]'", (user_id,)
            ).fetchall()
        return [{"id": self._handle(other), "name": self._name(other)} for (other,) in rows if other != self._bot_user_id]

    def suggest(self, user_id: str, owner_id: str, query: str) -> list[dict]:
        """A typed-ahead picker's options: the user's own free Pokémon matching `query`, valued for `owner_id`."""
        return matching_options(owner_id, self.free_entries(user_id), query)

    def propose(self, user_id: str, to_id: str, give_id: str) -> ProposeResult:
        """An offer of the user's `give_id` to `to_id`, who gets a DM to pick one back."""
        self._expire()
        to_id = self._user_for(to_id)
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
        if held := self.hold(user_id, individual_id):
            return TradeReply(HOLD_ERRORS[held], ok=False)
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
        give = with_current_item(trade.give, self._pool_entry(trade.proposer_id, trade.give_id))
        back = with_current_item(trade.back, self._pool_entry(trade.target_id, trade.back_id))
        done = self._update(
            trade.id,
            "UPDATE trades SET status = 'completed', give_json = ?, back_json = ? WHERE id = ? AND status = 'countered'",
            (json.dumps(give, ensure_ascii=False), json.dumps(back, ensure_ascii=False), trade.id),
        )
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
        if held := self.hold(user_id, give_id):
            return held
        if self._open_offers(user_id) >= MAX_OPEN_OFFERS:
            return "too_many"
        return None

    def _offer_dm(self, trade: Trade) -> DirectMessage:
        options = pick_options(trade.id, self.free_entries(trade.target_id))
        proposer = self._name(trade.proposer_id)
        text = f"<@{trade.proposer_id}>님이 {_label(trade.give)}을(를) 내놓고 교환을 제안했어요. 24시간 안에 답해 주세요."
        blocks = [kit.section(f"*교환 제안*\n{text}")]
        buttons = [kit.button("거절", DECLINE_ACTION_ID, trade.id)]
        if options:
            blocks.append(picker_block(PICK_ACTION_ID, trade.id, options))
            buttons.insert(0, kit.button("수락", ACCEPT_ACTION_ID, trade.id, style="primary"))
        else:
            blocks.append(kit.context("지금 내놓을 수 있는 포켓몬이 없어서 거절만 할 수 있어요."))
        blocks.append(kit.actions(buttons))
        blocks.append(kit.context(f"{proposer}님의 앱과 내 앱이 켜져 있어야 포켓몬이 오가요."))
        return DirectMessage(trade.target_id, text, blocks)

    def _delivery(self, trade: Trade, user_id: str) -> dict:
        mine = user_id == trade.proposer_id
        received, given_id = (trade.back, trade.give_id) if mine else (trade.give, trade.back_id)
        sender = trade.target_id if mine else trade.proposer_id
        gave = trade.give if mine else trade.back
        receive = {key: value for key, value in received.items() if key != "member"}
        return {"trade_id": trade.id, "give_id": given_id, "from_name": self._name(sender), "receive": receive,
                "give_held_item": gave["entry"].get(HELD_ITEM_KEY)}

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

    def locked_ids(self, user_id: str) -> list[str]:
        """The user's individuals in open trades; the app keeps their held item in place until the trade ends."""
        self._expire()
        return sorted(self._locked_ids(user_id))

    def free_entries(self, user_id: str) -> list[dict]:
        """The user's pool without the individuals already in an open trade or miracle offer, or held (`holds`)."""
        unavailable = self._locked_ids(user_id) | set(self._holds(user_id))
        return [entry for entry in self._pool(user_id) if entry["id"] not in unavailable]

    def hold(self, user_id: str, individual_id: str) -> str | None:
        """Why the user may not trade `individual_id` yet (a `HOLD_ERRORS` code), or None."""
        return self._holds(user_id).get(individual_id)

    def is_locked(self, user_id: str, individual_id: str) -> bool:
        return individual_id in self._locked_ids(user_id)

    def pool_entry(self, user_id: str, individual_id: str | None) -> dict | None:
        return self._pool_entry(user_id, individual_id)

    def pool(self, user_id: str) -> list[dict]:
        """The user's last uploaded pool, newest first; empty when none was sent."""
        return self._pool(user_id)

    def name(self, user_id: str) -> str:
        return self._name(user_id)

    def handle(self, user_id: str) -> str:
        return self._handle(user_id)

    def user_for(self, handle: str) -> str:
        return self._user_for(handle)

    def connect(self) -> sqlite3.Connection:
        return self._connect()

    @staticmethod
    def insert_completed(connection: sqlite3.Connection, trade: Trade) -> None:
        """A trade finished elsewhere (a miracle offer), written as completed so both apps pick it up as a delivery."""
        connection.execute(
            "INSERT INTO trades (id, proposer_id, target_id, give_id, give_json, back_id, back_json, status, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, 'completed', ?)",
            (trade.id, trade.proposer_id, trade.target_id, trade.give_id, json.dumps(trade.give, ensure_ascii=False),
             trade.back_id, json.dumps(trade.back, ensure_ascii=False), _stamp(trade.created_at)),
        )

    def _locked_ids(self, user_id: str, except_trade: str | None = None) -> set[str]:
        """The user's individuals tied up in open trades: what they offered, what they picked back, and their
        open miracle offer."""
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT give_id FROM trades WHERE status IN ('offered', 'countered') AND proposer_id = ?1 AND id != ?2 "
                "UNION SELECT back_id FROM trades WHERE status IN ('offered', 'countered') AND target_id = ?1 "
                "AND back_id IS NOT NULL AND id != ?2 "
                "UNION SELECT give_id FROM miracle_offers WHERE status = 'open' AND poster_id = ?1 AND created_at >= ?3",
                (user_id, except_trade or "", _stamp(self._now() - TRADE_LIFETIME)),
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

    def _handle(self, user_id: str) -> str:
        """The id apps use for a coworker, so Slack ids never leave the bot."""
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT OR IGNORE INTO trade_handles (slack_user_id, handle) VALUES (?, ?)", (user_id, uuid.uuid4().hex[:16])
            )
            return connection.execute("SELECT handle FROM trade_handles WHERE slack_user_id = ?", (user_id,)).fetchone()[0]

    def _user_for(self, handle: str) -> str:
        with closing(self._connect()) as connection:
            row = connection.execute("SELECT slack_user_id FROM trade_handles WHERE handle = ?", (handle,)).fetchone()
        return row[0] if row else handle

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
    normalized = {
        "id": individual_id,
        "pokemon_id": pokemon_id,
        "level": level,
        "shiny": item.get("shiny") is True,
        "name": name.strip()[:40] if isinstance(name, str) and name.strip() else f"#{pokemon_id}",
        "entry": detail,
    }
    member = item.get("member")
    if isinstance(member, dict) and member.get("id") == individual_id:
        normalized["member"] = member
    return normalized


def picker_block(action_id: str, owner_id: str, options: list[dict]) -> dict:
    """A select of `options`. Past Slack's 100 it loads them as the player types (`matching_options`); the block id
    carries `owner_id` for that lookup."""
    if len(options) <= PICKER_LIMIT:
        select = kit.static_select(action_id, "내가 내놓을 포켓몬 고르기", options)
    else:
        select = kit.external_select(action_id, "내가 내놓을 포켓몬 고르기")
    return kit.actions([select], block_id=owner_id)


def matching_options(owner_id: str, entries: list[dict], query: str) -> list[dict]:
    """The options whose label holds every word of `query`, first 100. Labels come from the whole list, so a
    ` #2` stays the same whatever is typed."""
    words = query.casefold().split()
    options = pick_options(owner_id, entries)
    return [option for option in options if all(word in option["text"]["text"].casefold() for word in words)][:PICKER_LIMIT]


def pick_options(owner_id: str, entries: list[dict]) -> list[dict]:
    """Slack select options for `entries`, valued `owner_id|individual id`, each with a distinct label."""
    return [kit.option(text, f"{owner_id}|{entry['id']}") for entry, text in zip(entries, option_labels(entries))]


def option_labels(entries: list[dict]) -> list[str]:
    """Name, sex, level, shiny and nature, so same-species individuals differ; still-equal labels get ` #2`, ` #3`."""
    bases = [_detailed_label(entry)[:OPTION_TEXT_LIMIT - DUPLICATE_SUFFIX_ROOM] for entry in entries]
    totals = Counter(bases)
    seen: Counter[str] = Counter()
    labels = []
    for base in bases:
        seen[base] += 1
        labels.append(base if totals[base] == 1 or seen[base] == 1 else f"{base} #{seen[base]}")
    return labels


def _detailed_label(entry: dict) -> str:
    detail = entry.get("entry") or {}
    profile = detail.get("profile") if isinstance(detail.get("profile"), dict) else {}
    sex = GENDER_SYMBOLS.get(profile.get("gender"), "")
    nature = NATURE_NAMES_KO.get(detail.get("nature"))
    parts = [f"{entry['name']}{sex} Lv.{entry['level']}", "✨" if entry["shiny"] else None, nature]
    return " ".join(part for part in parts if part)


def with_current_item(snapshot: dict, current: dict | None) -> dict:
    """The offered entry carrying the trade item the owner holds now, so an item taken off after the offer is not also delivered."""
    entry = dict(snapshot["entry"])
    item = current["entry"].get(HELD_ITEM_KEY) if current else None
    if item is None:
        entry.pop(HELD_ITEM_KEY, None)
    else:
        entry[HELD_ITEM_KEY] = item
    return {**snapshot, "entry": entry}


def _status_text(status: str) -> str:
    return {
        "declined": "이미 거절된 교환이에요.",
        "expired": "24시간이 지나 끝난 교환이에요.",
        "completed": "이미 끝난 교환이에요.",
        "countered": "이미 수락해서 상대 확인을 기다리는 중이에요.",
        "offered": "아직 수락 전인 교환이에요.",
    }.get(status, "이 교환은 더 이상 열려 있지 않아요.")


def _confirm_blocks(trade: Trade, target_name: str) -> list[dict]:
    return [kit.section(f"*교환 확인*\n{_confirm_text(trade, target_name)}"),
            kit.actions([kit.button("교환하기", ACCEPT_ACTION_ID, trade.id, style="primary"),
                         kit.button("거절", DECLINE_ACTION_ID, trade.id)])]


def _confirm_text(trade: Trade, target_name: str) -> str:
    return (f"<@{trade.target_id}>님이 {_label(trade.back)}을(를) 내놓고 수락했어요. "
            f"내 {_label(trade.give)}과(와) 바꿀까요?")


def entry_label(entry: dict | None) -> str:
    return _label(entry)


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
