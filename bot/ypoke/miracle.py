"""Miracle trades: a user puts one Pokémon up on a card in the battle channel, and the first coworker to pick one of
theirs from the card's private picker gets it in exchange. The finished swap is stored as a completed trade, so both
apps receive it through the trade deliveries. Contract: bot/API.md.
"""

import json
import sqlite3
import uuid
from collections.abc import Callable
from contextlib import closing
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from ypoke.dex import sprite_url
from ypoke.messages import DirectMessage
from ypoke.trades import (
    HOLD_ERRORS,
    TRADE_LIFETIME,
    UNKNOWN_INDIVIDUAL,
    Trade,
    TradeService,
    entry_label,
    pick_options,
    picker_block,
    with_current_item,
)

ACCEPT_ACTION_ID = "miracle_accept"
CANCEL_ACTION_ID = "miracle_cancel"
PICK_ACTION_ID = "miracle_pick"
ACCEPT_LABEL = "교환하기"
CANCEL_LABEL = "내리기"

POST_ERRORS = {
    "unknown_individual": UNKNOWN_INDIVIDUAL,
    "locked": "그 포켓몬은 이미 다른 교환에 걸려 있어요.",
    "already_open": "미라클 교환에는 한 번에 한 마리만 올릴 수 있어요. 먼저 올린 포켓몬을 내려 주세요.",
    "post_failed": "대결 채널에 올리지 못했어요. 잠시 뒤 다시 해 주세요.",
    **HOLD_ERRORS,
}
ENDED_TEXT = {
    "completed": "이미 교환됐어요.",
    "cancelled": "올린 사람이 내린 미라클 교환이에요.",
    "closed": "올린 포켓몬을 지금 교환할 수 없어서 닫힌 미라클 교환이에요.",
    "expired": "24시간이 지나 끝난 미라클 교환이에요.",
}
OWN_OFFER = "내가 올린 미라클 교환에는 내 포켓몬을 낼 수 없어요."
POSTER_ONLY = "올린 사람만 내릴 수 있어요."
NOT_FOUND = "이 미라클 교환을 찾을 수 없어요."
NOTHING_TO_GIVE = ("지금 낼 수 있는 포켓몬이 없어요. 앱을 YPoke에 연결하고, 졸업한 포켓몬을 키우는 자리와 대결에서 빼 두면 "
                   "여기에 나와요.")
NOT_TRADABLE = "그 포켓몬은 지금 교환할 수 없어요. 앱에서 키우거나 대결에 내보냈는지 확인하고 다른 포켓몬을 골라 주세요."
OPEN_NOTE = "먼저 고른 사람과 바로 교환돼요. 24시간 동안 열려 있어요."


class Board(Protocol):
    """The battle channel the cards live in."""

    def post(self, text: str, blocks: list[dict]) -> str | None:
        """The new message's ts, or None when it could not be posted."""

    def update(self, ts: str, text: str, blocks: list[dict]) -> None: ...


@dataclass(frozen=True)
class Offer:
    id: str
    poster_id: str
    give_id: str
    give: dict
    status: str
    created_at: datetime
    card_ts: str | None = None


@dataclass(frozen=True)
class MiracleReply:
    """A private answer to a card button or the picker. `final` replaces the picker it was chosen from."""

    text: str
    ok: bool = True
    blocks: list[dict] | None = None
    final: bool = False
    direct_messages: tuple[DirectMessage, ...] = ()


@dataclass(frozen=True)
class PostResult:
    offer: dict | None = None
    error: str | None = None


class MiracleService:
    """Without a `board` (no battle channel set) the feature is unavailable."""

    def __init__(
        self,
        trades: TradeService,
        board: Board | None,
        now: Callable[[], datetime] = lambda: datetime.now(UTC),
    ):
        self._trades = trades
        self._board = board
        self._now = now

    @property
    def available(self) -> bool:
        return self._board is not None

    def status(self, user_id: str) -> dict | None:
        """The user's open offer as the app shows it, or None."""
        self.sweep()
        offer = self._open_offer(user_id)
        return _brief(offer) if offer else None

    def post(self, user_id: str, give_id: str) -> PostResult:
        """Put `give_id` up on a new card; the poster agrees to whatever the first acceptor picks."""
        self.sweep()
        give = self._trades.pool_entry(user_id, give_id)
        if give is None:
            return PostResult(error="unknown_individual")
        if self._open_offer(user_id) is not None:
            return PostResult(error="already_open")
        if self._trades.is_locked(user_id, give_id):
            return PostResult(error="locked")
        if held := self._trades.hold(user_id, give_id):
            return PostResult(error=held)
        offer = Offer(uuid.uuid4().hex, user_id, give_id, give, "open", self._now())
        if not self._insert(offer):
            return PostResult(error="already_open")
        card_ts = self._board.post(*open_card(offer))
        if card_ts is None:
            self._delete(offer.id)
            return PostResult(error="post_failed")
        self._set_card(offer.id, card_ts)
        return PostResult(_brief(offer))

    def cancel_mine(self, user_id: str) -> bool:
        """The app takes the user's open offer down; False when there is none."""
        self.sweep()
        offer = self._open_offer(user_id)
        return offer is not None and self._end(offer, "cancelled")

    def take_down(self, user_id: str, offer_id: str) -> MiracleReply:
        """The card's 내리기 button, for the poster only."""
        self.sweep()
        offer = self._offer(offer_id)
        if offer is None:
            return MiracleReply(NOT_FOUND, ok=False)
        if user_id != offer.poster_id:
            return MiracleReply(POSTER_ONLY, ok=False)
        if offer.status != "open" or not self._end(offer, "cancelled"):
            return MiracleReply(ENDED_TEXT[self._offer(offer_id).status], ok=False)
        return MiracleReply(f"미라클 교환에서 {entry_label(offer.give)}을(를) 내렸어요.")

    def open_picker(self, user_id: str, offer_id: str) -> MiracleReply:
        """The card's 교환하기 button: a private select of the presser's own tradable Pokémon."""
        self.sweep()
        offer = self._offer(offer_id)
        refusal = _refusal(offer, user_id)
        if refusal:
            return refusal
        entries = self._trades.free_entries(user_id)
        if not entries:
            return MiracleReply(NOTHING_TO_GIVE, ok=False)
        text = f"<@{offer.poster_id}>님의 {entry_label(offer.give)}과(와) 바꿀 내 포켓몬을 골라 주세요. 고르면 바로 교환돼요."
        blocks = [
            {"type": "section", "text": {"type": "mrkdwn", "text": text}},
            picker_block(PICK_ACTION_ID, offer.id, pick_options(offer.id, entries)),
        ]
        return MiracleReply(text, blocks=blocks)

    def pick(self, user_id: str, offer_id: str, individual_id: str) -> MiracleReply:
        """The acceptor's pick finishes the trade at once; the first completed pick wins."""
        self.sweep()
        offer = self._offer(offer_id)
        refusal = _refusal(offer, user_id)
        if refusal:
            return refusal
        give_now = self._trades.pool_entry(offer.poster_id, offer.give_id)
        if give_now is None:
            self._end(offer, "closed")
            return MiracleReply(ENDED_TEXT["closed"], ok=False, final=True)
        back = self._trades.pool_entry(user_id, individual_id)
        if back is None or self._trades.is_locked(user_id, individual_id):
            return MiracleReply(NOT_TRADABLE, ok=False)
        if held := self._trades.hold(user_id, individual_id):
            return MiracleReply(HOLD_ERRORS[held], ok=False)
        give = with_current_item(offer.give, give_now)
        if not self._claim(offer, user_id, give, back):
            return MiracleReply(ENDED_TEXT["completed"], ok=False, final=True)
        self._edit_card(offer, *done_card(offer, user_id, back))
        mine, theirs = entry_label(back), entry_label(give)
        return MiracleReply(
            f"교환했어요! 내 {mine} ↔ <@{offer.poster_id}>님의 {theirs}. 앱을 켜 두면 곧 도착해요.",
            final=True,
            direct_messages=(
                DirectMessage(offer.poster_id, f"미라클 교환이 끝났어요! 내 {theirs} ↔ <@{user_id}>님의 {mine}. "
                                               "앱을 켜 두면 곧 도착해요."),
                DirectMessage(user_id, f"미라클 교환이 끝났어요! 내 {mine} ↔ <@{offer.poster_id}>님의 {theirs}. "
                                       "앱을 켜 두면 곧 도착해요."),
            ),
        )

    def pool_changed(self, user_id: str) -> None:
        """After a pool upload: an offered Pokémon that left the pool (raised, sent to battle) closes the offer."""
        offer = self._open_offer(user_id)
        if offer is not None and self._trades.pool_entry(user_id, offer.give_id) is None:
            self._end(offer, "closed")

    def sweep(self) -> None:
        """End every open offer past its lifetime and mark its card expired."""
        cutoff = _stamp(self._now() - TRADE_LIFETIME)
        with closing(self._trades.connect()) as connection:
            rows = connection.execute(
                "SELECT * FROM miracle_offers WHERE status = 'open' AND created_at < ?", (cutoff,)
            ).fetchall()
        for row in rows:
            self._end(_offer(row), "expired")

    def _claim(self, offer: Offer, acceptor_id: str, give: dict, back: dict) -> bool:
        """Close the offer and write the completed trade in one transaction; True only for the first acceptor."""
        with closing(self._trades.connect()) as connection, connection:
            claimed = connection.execute(
                "UPDATE miracle_offers SET status = 'completed', acceptor_id = ?, back_json = ? "
                "WHERE id = ? AND status = 'open'",
                (acceptor_id, json.dumps(back, ensure_ascii=False), offer.id),
            ).rowcount == 1
            if claimed:
                TradeService.insert_completed(connection, Trade(
                    uuid.uuid4().hex, offer.poster_id, acceptor_id, offer.give_id, give, back["id"], back,
                    "completed", self._now(), False, False,
                ))
        return claimed

    def _end(self, offer: Offer, status: str) -> bool:
        with closing(self._trades.connect()) as connection, connection:
            ended = connection.execute(
                "UPDATE miracle_offers SET status = ? WHERE id = ? AND status = 'open'", (status, offer.id)
            ).rowcount == 1
        if ended:
            self._edit_card(offer, *ended_card(offer, status))
        return ended

    def _edit_card(self, offer: Offer, text: str, blocks: list[dict]) -> None:
        if offer.card_ts is not None and self._board is not None:
            self._board.update(offer.card_ts, text, blocks)

    def _open_offer(self, user_id: str) -> Offer | None:
        with closing(self._trades.connect()) as connection:
            row = connection.execute(
                "SELECT * FROM miracle_offers WHERE poster_id = ? AND status = 'open'", (user_id,)
            ).fetchone()
        return _offer(row) if row else None

    def _offer(self, offer_id: str) -> Offer | None:
        with closing(self._trades.connect()) as connection:
            row = connection.execute("SELECT * FROM miracle_offers WHERE id = ?", (offer_id,)).fetchone()
        return _offer(row) if row else None

    def _insert(self, offer: Offer) -> bool:
        try:
            with closing(self._trades.connect()) as connection, connection:
                connection.execute(
                    "INSERT INTO miracle_offers (id, poster_id, give_id, give_json, status, created_at) "
                    "VALUES (?, ?, ?, ?, 'open', ?)",
                    (offer.id, offer.poster_id, offer.give_id, json.dumps(offer.give, ensure_ascii=False),
                     _stamp(offer.created_at)),
                )
        except sqlite3.IntegrityError:
            return False
        return True

    def _delete(self, offer_id: str) -> None:
        with closing(self._trades.connect()) as connection, connection:
            connection.execute("DELETE FROM miracle_offers WHERE id = ?", (offer_id,))

    def _set_card(self, offer_id: str, card_ts: str) -> None:
        with closing(self._trades.connect()) as connection, connection:
            connection.execute("UPDATE miracle_offers SET card_ts = ? WHERE id = ?", (card_ts, offer_id))


def open_card(offer: Offer) -> tuple[str, list[dict]]:
    """The card's text and blocks while it waits for an acceptor: the sprite, 교환하기 and the poster's 내리기."""
    text = f"<@{offer.poster_id}>님이 미라클 교환에 {entry_label(offer.give)}을(를) 올렸어요"
    return text, [
        _sprite_section(text, offer.give),
        {"type": "context", "elements": [{"type": "mrkdwn", "text": OPEN_NOTE}]},
        {"type": "actions", "elements": [
            {"type": "button", "style": "primary", "action_id": ACCEPT_ACTION_ID, "value": offer.id,
             "text": {"type": "plain_text", "text": ACCEPT_LABEL}},
            {"type": "button", "action_id": CANCEL_ACTION_ID, "value": offer.id,
             "text": {"type": "plain_text", "text": CANCEL_LABEL}},
        ]},
    ]


def done_card(offer: Offer, acceptor_id: str, back: dict) -> tuple[str, list[dict]]:
    text = (f"미라클 교환 완료: <@{offer.poster_id}>님의 {entry_label(offer.give)} ↔ "
            f"<@{acceptor_id}>님의 {entry_label(back)}")
    return text, [
        _sprite_section(f"*미라클 교환 완료*\n<@{offer.poster_id}>님의 {entry_label(offer.give)} ↔ "
                        f"<@{acceptor_id}>님의 {entry_label(back)}", offer.give),
        {"type": "context", "elements": [
            {"type": "image", "image_url": sprite_url(back["pokemon_id"], back["shiny"]), "alt_text": back["name"]},
            {"type": "mrkdwn", "text": f"<@{acceptor_id}>님이 {entry_label(back)}을(를) 보냈어요"},
        ]},
    ]


def ended_card(offer: Offer, status: str) -> tuple[str, list[dict]]:
    poster, label = f"<@{offer.poster_id}>", entry_label(offer.give)
    text = {
        "cancelled": f"{poster}님이 미라클 교환에서 {label}을(를) 내렸어요.",
        "closed": f"{poster}님이 올린 {label}을(를) 지금 교환할 수 없어서 미라클 교환이 닫혔어요.",
        "expired": f"{poster}님의 미라클 교환 {label}은(는) 24시간이 지나 끝났어요.",
    }[status]
    return text, [_sprite_section(text, offer.give)]


def _sprite_section(text: str, entry: dict) -> dict:
    return {
        "type": "section", "text": {"type": "mrkdwn", "text": text},
        "accessory": {"type": "image", "image_url": sprite_url(entry["pokemon_id"], entry["shiny"]),
                      "alt_text": entry["name"]},
    }


def _refusal(offer: Offer | None, user_id: str) -> MiracleReply | None:
    if offer is None:
        return MiracleReply(NOT_FOUND, ok=False)
    if user_id == offer.poster_id:
        return MiracleReply(OWN_OFFER, ok=False)
    if offer.status != "open":
        return MiracleReply(ENDED_TEXT[offer.status], ok=False, final=True)
    return None


def _brief(offer: Offer) -> dict:
    return {"offer_id": offer.id, "give_id": offer.give_id, "name": offer.give["name"],
            "expires_at": _stamp(offer.created_at + TRADE_LIFETIME)}


def _offer(row: tuple) -> Offer:
    offer_id, poster_id, give_id, give_json, status, created_at, card_ts, _acceptor_id, _back_json = row
    return Offer(offer_id, poster_id, give_id, json.loads(give_json), status, datetime.fromisoformat(created_at),
                 card_ts)


def _stamp(moment: datetime) -> str:
    return moment.astimezone(UTC).isoformat(timespec="seconds")
