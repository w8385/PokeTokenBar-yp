"""The `/교환` and `/미라클` screens: pick a tradable Box Pokémon, then offer it to a coworker with
`TradeService.propose` or post it with `MiracleService.post`, the calls the app's own offers use. The list is
`TradeService.free_entries`, which leaves out what pending Slack edits hold (`RemoteOps.holds`). The rest of a trade
(the coworker's pick, accept, confirm) happens in the existing DMs. Values carry individual ids and coworker handles,
so a press on an older message still names its Pokémon."""

import re

from ypoke import blocks as kit
from ypoke.editor import join_value, split_value
from ypoke.lineup_editor import EditorReply
from ypoke.miracle import POST_ERRORS, MiracleService
from ypoke.remote_ops import RemoteOps, View
from ypoke.remote_views import MIRACLE_COMMAND, RemoteViews, Screen, sync_line, text_screen
from ypoke.trades import (
    HOLD_ERRORS,
    OPEN_STATUSES,
    PICKER_LIMIT,
    PROPOSE_ERRORS,
    TradeService,
    entry_label,
    matching_options,
    option_labels,
    pick_options,
    picker_block,
)

ACTION_PREFIX = "offer_"
GIVE_ACTION = "offer_give"
TO_ACTION = "offer_to"
SEND_ACTION = "offer_send"
CANCEL_ACTION = "offer_cancel"
BACK_ACTION = "offer_back"
MIRACLE_PICK_ACTION = "offer_miracle_pick"
MIRACLE_POST_ACTION = "offer_miracle_post"
MIRACLE_DOWN_ACTION = "offer_miracle_down"
MIRACLE_BACK_ACTION = "offer_miracle_back"
PICKER_ACTIONS = (GIVE_ACTION, MIRACLE_PICK_ACTION)
TO_PREFIX = "to:"
MIRACLE_OWNER = "miracle"
TRADE_TITLE = "*교환*"
MIRACLE_TITLE = "*미라클 교환*"
TRADE_PROMPT = ("내놓을 박스 포켓몬을 고르세요. 졸업했고, 키우는 자리·대결 라인업에 없고, 다른 교환에 걸리지 않은 "
                "포켓몬만 나와요.")
MIRACLE_PROMPT = "미라클 교환에 올릴 박스 포켓몬을 고르세요. 대결 채널에 카드가 올라가요."
TRADE_NOTE = ("상대가 DM에서 돌려줄 포켓몬을 고르고 수락하면 나에게 확인 DM이 와요. 제안은 24시간 뒤 사라지고, "
              "받은 포켓몬은 앱이 회사에서 동기화할 때 들어와요.")
MIRACLE_NOTE = ("먼저 카드의 교환하기를 누르고 자기 포켓몬을 고른 동료와 바로 바뀌어요. 한 번에 한 마리, 24시간 동안 "
                "열려 있어요. 받은 포켓몬은 앱이 회사에서 동기화할 때 들어와요.")
NONE_TRADABLE = "지금 내놓을 수 있는 포켓몬이 없어요. 앱에서 졸업한 포켓몬을 키우는 자리와 대결에서 빼고 회사에서 앱을 한 번 켜 주세요."
NO_MATCH = "'{query}'에 맞는, 내놓을 수 있는 포켓몬이 없어요."
NO_COWORKERS = "교환할 포켓몬을 올린 동료가 아직 없어요."
NOT_TRADABLE = "그 포켓몬은 지금 교환할 수 없어요. 명령을 다시 열어 주세요."
MIRACLE_UNAVAILABLE = "지금은 미라클 교환을 쓸 수 없어요."
NONE_POSTED = "미라클 교환에 올린 포켓몬이 없어요."
OPEN_TITLE = "*진행 중인 교환*"
_MENTION = re.compile(r"<@([UW][A-Z0-9]+)(?:\|[^>]*)?>")


class TradeEditor:
    def __init__(self, remote: RemoteOps, views: RemoteViews, trades: TradeService, miracle: MiracleService,
                 bot_user_id: str | None = None):
        self._remote = remote
        self._views = views
        self._trades = trades
        self._miracle = miracle
        self._bot_user_id = bot_user_id

    def handle(self, user_id: str, command: str, text: str) -> Screen:
        """`/교환 [@상대] [이름]` or `/미라클 [이름]`. A name that matches one Pokémon (with a coworker for
        `/교환`) opens its confirm screen."""
        view = self._remote.view(user_id)
        if view is None:
            return self._views.handle(user_id, command, text)
        if command == MIRACLE_COMMAND:
            return self._miracle_screen(user_id, view, text.strip())
        mention = _MENTION.search(text)
        query = _MENTION.sub("", text).strip()
        to = ""
        if mention:
            error = self._target_error(user_id, mention.group(1))
            if error:
                return self._trade_screen(user_id, view, query, note=PROPOSE_ERRORS[error])
            to = self._trades.handle(mention.group(1))
        entries = self._matching(user_id, query)
        if to and query and len(entries) == 1:
            return self._confirm(view, to, entries[0])
        return self._trade_screen(user_id, view, query, to)

    def act(self, user_id: str, action_id: str, value: str, selected: list[str]) -> EditorReply:
        """Trade values are `to:<handle>|<individual id>` (an empty handle until a coworker is picked); `offer_cancel`
        sends a trade id, the Miracle controls an individual or offer id."""
        view = self._remote.view(user_id)
        if view is None:
            return _note(NOT_TRADABLE)
        if action_id.startswith(f"{ACTION_PREFIX}{MIRACLE_OWNER}_"):
            return self._miracle_act(user_id, view, action_id, value)
        if action_id == CANCEL_ACTION:
            return self._cancel(user_id, view, value)
        owner, give_id = split_value(value)
        to = owner.removeprefix(TO_PREFIX)
        if action_id == BACK_ACTION:
            return EditorReply(self._trade_screen(user_id, view, "", to))
        if action_id == SEND_ACTION:
            return self._send(user_id, view, to, give_id)
        entry = self._tradable(user_id, give_id)
        if entry is None:
            return _note(self._refusal(user_id, give_id))
        if action_id == TO_ACTION or (action_id == GIVE_ACTION and to):
            return EditorReply(self._confirm(view, to, entry))
        if action_id == GIVE_ACTION:
            return EditorReply(self._coworkers(user_id, view, entry))
        return _note(NOT_TRADABLE)

    def options(self, user_id: str, block_id: str, query: str) -> list[dict]:
        """A picker's options past Slack's 100; the block id is the picker's owner."""
        if not (block_id.startswith(TO_PREFIX) or block_id == MIRACLE_OWNER):
            return []
        return matching_options(block_id, self._trades.free_entries(user_id), query)

    def _miracle_screen(self, user_id: str, view: View, query: str, done: str | None = None) -> Screen:
        if not self._miracle.available:
            return text_screen([MIRACLE_TITLE, MIRACLE_UNAVAILABLE], view)
        status = self._miracle.status(user_id)
        blocks = [kit.section(done)] if done else []
        if status:
            posted = self._trades.pool_entry(user_id, status["give_id"])
            label = option_labels([posted])[0] if posted else status["name"]
            blocks += [
                kit.section(f"{MIRACLE_TITLE}\n지금 올린 포켓몬: {label}\n"
                         "한 번에 한 마리만 올릴 수 있어요. 다른 포켓몬을 올리려면 먼저 내려 주세요."),
                kit.actions([kit.button("내리기", MIRACLE_DOWN_ACTION, status["offer_id"])]),
            ]
            return _screen(MIRACLE_TITLE, blocks, view, MIRACLE_NOTE)
        entries = self._matching(user_id, query)
        if query and len(entries) == 1 and not done:
            return self._miracle_confirm(view, entries[0])
        blocks.append(kit.section(f"{MIRACLE_TITLE}\n{MIRACLE_PROMPT}"))
        blocks.append(self._picker(MIRACLE_PICK_ACTION, MIRACLE_OWNER, entries, user_id, query))
        return _screen(MIRACLE_TITLE, blocks, view, MIRACLE_NOTE)

    def _target_error(self, user_id: str, target_id: str) -> str | None:
        if target_id == user_id:
            return "self"
        coworkers = {coworker["id"] for coworker in self._trades.coworkers(user_id)}
        return None if self._trades.handle(target_id) in coworkers else "unknown_user"

    def _trade_screen(self, user_id: str, view: View, query: str, to: str = "", done: str | None = None,
                      note: str | None = None) -> Screen:
        head = f"{TRADE_TITLE} · {self._coworker_name(to)}님에게" if to else TRADE_TITLE
        blocks = [kit.section(text) for text in (done, note) if text]
        blocks.append(kit.section(f"{head}\n{TRADE_PROMPT}"))
        blocks.append(self._picker(GIVE_ACTION, f"{TO_PREFIX}{to}", self._matching(user_id, query), user_id, query))
        blocks += self._open_trades(user_id)
        return _screen(head, blocks, view, TRADE_NOTE)

    def _matching(self, user_id: str, query: str) -> list[dict]:
        entries = self._trades.free_entries(user_id)
        return [entry for entry in entries if query.casefold() in entry["name"].casefold()] if query else entries

    def _confirm(self, view: View, to: str, entry: dict) -> Screen:
        name = self._coworker_name(to)
        label = option_labels([entry])[0]
        value = join_value(f"{TO_PREFIX}{to}", entry["id"])
        blocks = [
            kit.section(f"*교환 제안*\n내 {label}을(를) {name}님에게 내놓고 교환을 제안할까요?\n"
                     f"{name}님이 DM에서 돌려줄 포켓몬을 고르고 수락하면, 나에게 확인 DM이 와요."),
            kit.actions([kit.button("제안하기", SEND_ACTION, value, style="primary"),
                         kit.button("다른 포켓몬", BACK_ACTION, join_value(f"{TO_PREFIX}{to}", ""))]),
        ]
        return _screen(f"{label} 교환 제안", blocks, view, TRADE_NOTE)

    def _picker(self, action_id: str, owner: str, entries: list[dict], user_id: str, query: str) -> dict:
        if entries:
            return picker_block(action_id, owner, pick_options(owner, entries))
        empty = NO_MATCH.format(query=query) if query and self._trades.free_entries(user_id) else NONE_TRADABLE
        return kit.context(empty)

    def _open_trades(self, user_id: str) -> list[dict]:
        open_trades = [trade for trade in self._trades.history(user_id) if trade["status"] in OPEN_STATUSES]
        if not open_trades:
            return []
        blocks = [kit.section(OPEN_TITLE)]
        for trade in open_trades:
            word = "취소" if trade["direction"] == "outgoing" else "거절"
            blocks.append(kit.section(_trade_line(trade), accessory=kit.button(word, CANCEL_ACTION, trade["trade_id"])))
        return blocks

    def _coworker_name(self, handle: str) -> str:
        return self._trades.name(self._trades.user_for(handle))

    def _miracle_act(self, user_id: str, view: View, action_id: str, value: str) -> EditorReply:
        if action_id == MIRACLE_BACK_ACTION:
            return EditorReply(self._miracle_screen(user_id, view, ""))
        if not self._miracle.available:
            return _note(MIRACLE_UNAVAILABLE)
        if action_id == MIRACLE_DOWN_ACTION:
            reply = self._miracle.take_down(user_id, value)
            if not reply.ok:
                return _note(reply.text)
            return EditorReply(self._miracle_screen(user_id, view, "", done=f"✅ {reply.text}"))
        give_id = split_value(value)[1] if action_id == MIRACLE_PICK_ACTION else value
        entry = self._tradable(user_id, give_id)
        if entry is None:
            return _note(self._refusal(user_id, give_id))
        if action_id == MIRACLE_PICK_ACTION:
            return EditorReply(self._miracle_confirm(view, entry))
        result = self._miracle.post(user_id, give_id)
        if result.error:
            return _note(POST_ERRORS[result.error])
        done = f"✅ {option_labels([entry])[0]}을(를) 미라클 교환에 올렸어요."
        return EditorReply(self._miracle_screen(user_id, view, "", done=done))

    def _cancel(self, user_id: str, view: View, trade_id: str) -> EditorReply:
        reply = self._trades.decline(user_id, trade_id)
        if not reply.ok:
            return _note(reply.text)
        return EditorReply(self._trade_screen(user_id, view, "", done=f"✅ {reply.text}"),
                           direct_messages=reply.direct_messages)

    def _send(self, user_id: str, view: View, to: str, give_id: str) -> EditorReply:
        result = self._trades.propose(user_id, to, give_id)
        if result.error:
            return _note(PROPOSE_ERRORS[result.error])
        entry = self._trades.pool_entry(user_id, give_id)
        done = (f"✅ {self._coworker_name(to)}님에게 {entry_label(entry)}을(를) 내놓고 교환을 제안했어요. "
                "상대가 고르고 수락하면 DM이 와요.")
        return EditorReply(self._trade_screen(user_id, view, "", done=done), direct_messages=result.direct_messages)

    def _tradable(self, user_id: str, individual_id: str) -> dict | None:
        return next((entry for entry in self._trades.free_entries(user_id) if entry["id"] == individual_id), None)

    def _refusal(self, user_id: str, individual_id: str) -> str:
        held = self._trades.hold(user_id, individual_id)
        return HOLD_ERRORS[held] if held else NOT_TRADABLE

    def _coworkers(self, user_id: str, view: View, entry: dict) -> Screen:
        label = option_labels([entry])[0]
        coworkers = self._trades.coworkers(user_id)[:PICKER_LIMIT]
        back = kit.button("다른 포켓몬", BACK_ACTION, join_value(TO_PREFIX, ""))
        if not coworkers:
            return _screen(TRADE_TITLE, [kit.section(f"{TRADE_TITLE} · {label}\n{NO_COWORKERS}"), kit.actions([back])],
                           view, TRADE_NOTE)
        select = kit.static_select(TO_ACTION, "제안할 동료 고르기", [
            kit.option(coworker["name"], join_value(f"{TO_PREFIX}{coworker['id']}", entry["id"])) for coworker in coworkers])
        blocks = [kit.section(f"{TRADE_TITLE} · {label}\n누구에게 제안할까요? 박스 포켓몬을 올린 동료만 나와요."),
                  kit.actions([select, back])]
        return _screen(f"{label} 교환", blocks, view, TRADE_NOTE)

    def _miracle_confirm(self, view: View, entry: dict) -> Screen:
        label = option_labels([entry])[0]
        blocks = [
            kit.section(f"{MIRACLE_TITLE}\n{label}을(를) 미라클 교환에 올릴까요?\n"
                     "대결 채널에 카드가 올라가고, 먼저 고른 동료의 포켓몬과 바로 바뀌어요. 되돌릴 수 없어요."),
            kit.actions([kit.button("올리기", MIRACLE_POST_ACTION, entry["id"], style="primary"),
                         kit.button("다른 포켓몬", MIRACLE_BACK_ACTION, MIRACLE_OWNER)]),
        ]
        return _screen(f"{label} 미라클 교환", blocks, view, MIRACLE_NOTE)


def _trade_line(trade: dict) -> str:
    mine, theirs, partner = entry_label(trade["give"]), entry_label(trade["want"]), trade["with_name"]
    if trade["direction"] == "outgoing":
        if trade["status"] == "offered":
            return f"내 {mine} → {partner}님 · 상대가 고르는 중이에요"
        return f"내 {mine} ↔ {partner}님의 {theirs} · DM에서 확인해 주세요"
    if trade["status"] == "offered":
        return f"{partner}님의 {theirs} → 나 · DM에서 내놓을 포켓몬을 골라 주세요"
    return f"{partner}님의 {theirs} ↔ 내 {mine} · 상대 확인을 기다려요"


def _note(text: str) -> EditorReply:
    return EditorReply(Screen(text, [kit.section(text)]), replace=False)


def _screen(head: str, blocks: list[dict], view: View, note: str) -> Screen:
    return Screen(head, [*blocks, kit.context(note, sync_line(view))])
