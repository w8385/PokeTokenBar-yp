"""Slack listeners: turn a handler Reply into messages, and log who ran which command."""

import json
import logging
import time
from collections.abc import Callable
from functools import partial

from slack_bolt.adapter.socket_mode import SocketModeHandler
from slack_sdk import WebClient
from slack_sdk.webhook import WebhookClient

from ypoke import blocks as kit
from ypoke.battle_render import MatchupPictures
from ypoke.editor import pressed_value, split_value
from ypoke.commands import (
    CommandHandler,
    Delivery,
    Reply,
    Where,
    fallback_text,
    log_messages,
    message_blocks,
    parse_mention,
    reply_thread_ts,
    result_blocks,
)
from ypoke.lineup_editor import LineupEditor
from ypoke.miracle import MiracleService
from ypoke.shop_editor import ShopEditor
from ypoke.trade_editor import TradeEditor
from ypoke.trades import TradeService
from ypoke.training_editor import TrainingEditor

DM_FALLBACK_NOTE = "(대결을 신청한 곳에 올릴 수 없어서 DM으로 보내요)"
ERROR_TEXT = "대결 봇에서 오류가 났어요. 잠시 뒤 다시 해 주세요."
LOG_ARGS_LIMIT = 200
ANSWER_LIMIT = 30
SOCKET_PING_INTERVAL = 2

log = logging.getLogger(__name__)


def log_command(source: str, user_id: str, command: str, args: str) -> None:
    """One INFO line: who, which command, its text. Never the request body, so no tokens or response URLs."""
    log.info("%s user=%s command=%s args=%s", source, user_id, command,
             json.dumps(args[:LOG_ARGS_LIMIT], ensure_ascii=False))


def slash_listener(handler: CommandHandler, pictures: MatchupPictures | None = None):
    def listener(ack, body, respond, client) -> None:
        ack()
        user_id, command, text = body["user_id"], body["command"], body.get("text", "")
        log_command("slash", user_id, command, text)
        where = Where(body["channel_id"], response_url=body.get("response_url"))
        try:
            reply = handler.handle(user_id, text, command, where, echo=True)
        except Exception:
            log.exception("command failed")
            kit.send(respond, "slash error", text=ERROR_TEXT, response_type="ephemeral")
            return
        send_direct_messages(client, reply)
        _publish_slash(client, respond, where.channel_id, reply, pictures)

    return listener


def mention_listener(handler: CommandHandler, pictures: MatchupPictures | None = None):
    def listener(event, client) -> None:
        text = event.get("text", "")
        command, args = parse_mention(text, handler.bot_user_id)
        log_command("mention", event["user"], command or "(help)", args)
        thread_ts = reply_thread_ts(event)
        try:
            reply = handler.handle_mention(event["user"], text, Where(event["channel"], thread_ts))
        except Exception:
            log.exception("mention failed")
            reply = Reply(ERROR_TEXT)
        send_direct_messages(client, reply)
        publish_in_thread(client, event["channel"], event["user"], thread_ts, reply, pictures=pictures)

    return listener


def rematch_listener(handler: CommandHandler, pictures: MatchupPictures | None = None):
    def listener(ack, body, action, respond, client) -> None:
        ack()
        user_id, channel_id = body["user"]["id"], body["channel"]["id"]
        message = body["message"]
        thread_ts = card_thread(message)
        log_command("button", user_id, "rematch", action["value"])
        try:
            reply = handler.rematch(user_id, action["value"], Where(channel_id, thread_ts), message["ts"])
        except Exception:
            log.exception("rematch failed")
            reply = Reply(ERROR_TEXT)
        if reply.spent_card:
            _drop_buttons(client, channel_id, message)
        send_direct_messages(client, reply)
        publish_in_thread(client, channel_id, user_id, thread_ts, reply, respond, pictures)

    return listener


def card_thread(message: dict) -> str | None:
    """The thread a card sits in, so a rematch posts its card in the same place: None for a card in the channel
    itself, which Slack marks with its own ts once its log has started a thread."""
    thread_ts = message.get("thread_ts")
    return None if thread_ts == message["ts"] else thread_ts


def _drop_buttons(client: WebClient, channel_id: str, message: dict) -> None:
    blocks = [block for block in message.get("blocks", []) if block["type"] != "actions"]
    try:
        kit.send(client.chat_update, "rematch card", channel=channel_id, ts=message["ts"], text=message.get("text", ""),
                 blocks=blocks)
    except Exception:
        log.warning("could not remove the rematch button from the result card")


def trade_listener(trades: TradeService, kind: str):
    """A trade button or select: `kind` is `pick`, `accept` or `decline`. A refusal answers privately and keeps the buttons."""

    def listener(ack, body, action, respond, client) -> None:
        ack()
        user_id = body["user"]["id"]
        trade_id, individual_id = split_value(pressed_value(action))
        log_command("button", user_id, f"trade_{kind}", trade_id)
        try:
            if kind == "pick":
                reply = trades.pick(user_id, trade_id, individual_id)
            else:
                reply = (trades.accept if kind == "accept" else trades.decline)(user_id, trade_id)
        except Exception:
            log.exception("trade button failed")
            kit.send(respond, f"trade_{kind}", text=ERROR_TEXT, response_type="ephemeral", replace_original=False)
            return
        post_direct_messages(client, reply.direct_messages)
        if reply.final:
            kit.send(respond, f"trade_{kind}", text=reply.text, replace_original=True)
        else:
            kit.send(respond, f"trade_{kind}", text=reply.text, response_type="ephemeral", replace_original=False)

    return listener


def options_listener(trades: TradeService):
    """Loads a typed-ahead picker (trade or miracle): the block id is the trade or offer the options are for."""

    def listener(ack, body, payload) -> None:
        block_id = payload.get("block_id") or ""
        try:
            options = trades.suggest(body["user"]["id"], block_id, payload.get("value") or "")
        except Exception:
            log.exception("picker options failed block=%s", block_id)
            options = []
        options = options[:ANSWER_LIMIT]
        ack(options=options)
        log.info("options action=%s block=%s -> %d options", payload.get("action_id"), block_id, len(options))

    return listener


def editor_listener(editor: LineupEditor | ShopEditor | TrainingEditor | TradeEditor):
    """A `/파티`, `/상점`, `/트레이닝`, `/교환` or `/미라클` control. The new screen replaces the private message the
    press came from; a refusal is a private note under it."""

    def listener(ack, body, action, respond, client=None) -> None:
        ack()
        user_id = body["user"]["id"]
        value = pressed_value(action) or action.get("block_id") or ""
        selected = [option["value"] for option in action.get("selected_options") or []]
        log_command("button", user_id, action["action_id"], value)
        try:
            reply = editor.act(user_id, action["action_id"], value, selected)
        except Exception:
            log.exception("edit failed")
            kit.send(respond, action["action_id"], text=ERROR_TEXT, response_type="ephemeral", replace_original=False)
            return
        if client is not None:
            post_direct_messages(client, reply.direct_messages)
        kit.send(respond, action["action_id"], text=reply.screen.text, blocks=reply.screen.blocks,
                 response_type="ephemeral", replace_original=reply.replace)

    return listener


def editor_options_listener(
    editor: LineupEditor | ShopEditor | TrainingEditor | TradeEditor, options_for: Callable | None = None
):
    """Loads a typed-search menu: the block id is the lineup slot's individual id, the shop category or the picker's
    owner. `options_for` is the editor's method for a menu other than its main one."""
    fetch = options_for or editor.options

    def listener(ack, body, payload) -> None:
        started = time.monotonic()
        block_id, query = payload.get("block_id") or "", payload.get("value") or ""
        try:
            options = fetch(body["user"]["id"], block_id, query)
        except Exception:
            log.exception("editor options failed block=%s", block_id)
            options = []
        options = options[:ANSWER_LIMIT]
        ack(options=options)
        log.info("options action=%s block=%s query_length=%d -> %d options in %d ms", payload.get("action_id"),
                 block_id, len(query), len(options), (time.monotonic() - started) * 1000)

    return listener


def miracle_listener(miracle: MiracleService, kind: str):
    """A miracle card button or the private picker: `kind` is `accept`, `cancel` or `pick`. Answers are private;
    only a final pick replaces the picker it came from. The card itself is edited through the board."""

    def listener(ack, body, action, respond, client) -> None:
        ack()
        user_id = body["user"]["id"]
        offer_id, individual_id = split_value(pressed_value(action))
        log_command("button", user_id, f"miracle_{kind}", offer_id)
        try:
            if kind == "pick":
                reply = miracle.pick(user_id, offer_id, individual_id)
            elif kind == "accept":
                reply = miracle.open_picker(user_id, offer_id)
            else:
                reply = miracle.take_down(user_id, offer_id)
        except Exception:
            log.exception("miracle button failed")
            kit.send(respond, f"miracle_{kind}", text=ERROR_TEXT, response_type="ephemeral", replace_original=False)
            return
        post_direct_messages(client, reply.direct_messages)
        if kind == "pick" and reply.final:
            kit.send(respond, f"miracle_{kind}", text=reply.text, replace_original=True)
        else:
            kit.send(respond, f"miracle_{kind}", text=reply.text, blocks=reply.blocks, response_type="ephemeral",
                     replace_original=False)

    return listener


class SlackBoard:
    """The battle channel where miracle cards are posted and edited."""

    def __init__(self, client: WebClient, channel: str):
        self._client = client
        self._channel = channel

    def post(self, text: str, blocks: list[dict]) -> str | None:
        try:
            return kit.send(self._client.chat_postMessage, "miracle card", channel=self._channel, text=text,
                            blocks=blocks)["ts"]
        except Exception:
            log.warning("could not post a miracle card")
            return None

    def update(self, ts: str, text: str, blocks: list[dict]) -> None:
        try:
            kit.send(self._client.chat_update, "miracle card", channel=self._channel, ts=ts, text=text, blocks=blocks)
        except Exception:
            log.warning("could not edit a miracle card")


def send_direct_messages(client: WebClient, reply: Reply) -> None:
    post_direct_messages(client, reply.direct_messages)


def post_direct_messages(client: WebClient, messages) -> None:
    for message in messages:
        try:
            kit.send(client.chat_postMessage, "direct message", channel=message.user_id, text=message.text,
                     blocks=message.blocks)
        except Exception:
            log.warning("could not send a direct message")


def post_result(
    client: WebClient, channel: str, thread_ts: str | None, reply: Reply, pictures: MatchupPictures | None = None
) -> None:
    """The card in `thread_ts` (None: the channel itself), then the turn log in the card's thread, or in the same
    thread when the card is already a reply. Raises only when the card cannot be posted."""
    card = kit.send(client.chat_postMessage, "result card", channel=channel, thread_ts=thread_ts, **_card_message(reply))
    log_thread = thread_ts or card["ts"]
    post_log(partial(client.chat_postMessage, channel=channel, thread_ts=log_thread), client, reply, pictures)


def post_log(send: Callable, client: WebClient, reply: Reply, pictures: MatchupPictures | None) -> None:
    """Each log message through `send`, in order. Slack refuses a whole message over one image it cannot show, and
    a fresh upload can still be processing, so a refused message with pictures is sent again after a pause, then
    with small-sprite lines instead. Never raises."""
    matchups = [matchup for matchup in reply.card.log_matchups if matchup is not None]
    drawn = {}
    if pictures is not None and matchups:
        try:
            drawn = pictures.image_blocks(client, matchups)
        except Exception:
            log.warning("could not draw the matchup pictures", exc_info=True)
    for message in log_messages(reply, drawn):
        if _sent(send, message.text, message.blocks):
            continue
        if message.drawn:
            pictures.settle()
            if _sent(send, message.text, message.blocks):
                continue
            pictures.forget(message.drawn)
            if _sent(send, message.text, message.plain):
                continue
        log.warning("could not post the turn log")


def _sent(send: Callable, text: str, blocks: list[dict]) -> bool:
    try:
        response = kit.send(send, "turn log", text=text, blocks=blocks)
    except Exception:
        return False
    return getattr(response, "status_code", 200) in (None, 200)


def deliver(client: WebClient, delivery: Delivery, pictures: MatchupPictures | None = None) -> None:
    """Post a pending battle where it was asked for: the channel (thread), the slash command's still-fresh
    response URL, then a DM to the challenger when the bot cannot post there."""
    where, reply = delivery.where, delivery.reply
    try:
        post_result(client, where.channel_id, where.thread_ts, reply, pictures)
        return
    except Exception:
        log.warning("could not post a pending battle in its channel")
    if where.response_url:
        try:
            send = partial(WebhookClient(where.response_url).send, response_type="in_channel")
            if kit.send(send, "pending battle", **_card_message(reply)).status_code == 200:
                post_log(send, client, reply, pictures)
                return
        except Exception:
            log.warning("could not post a pending battle by response url")
    try:
        kit.send(client.chat_postMessage, "pending battle", channel=delivery.challenger_id, text=DM_FALLBACK_NOTE)
        post_result(client, delivery.challenger_id, None, reply, pictures)
    except Exception:
        log.warning("could not deliver a pending battle")


def _card_message(reply: Reply) -> dict:
    return {"text": fallback_text(reply), "blocks": result_blocks(reply)}


def publish_in_thread(
    client: WebClient, channel: str, user_id: str, thread_ts: str | None, reply: Reply,
    respond: Callable | None = None, pictures: MatchupPictures | None = None,
) -> None:
    """Visible replies go in the thread (None: the channel); private ones are ephemeral. `respond` (a button's
    response URL) is the fallback where the bot cannot post, such as a conversation it is not in."""
    visible = {"thread_ts": thread_ts, "response_type": "in_channel", "replace_original": False}
    if reply.summary is not None:
        try:
            post_result(client, channel, thread_ts, reply, pictures)
        except Exception:
            _respond_result(respond, client, reply, pictures, **visible)
    elif reply.in_channel:
        text = "\n".join(filter(None, (reply.echo, reply.text)))
        _post_line(client, channel, thread_ts, text, respond, message_blocks(reply, True))
    else:
        _private(client, channel, user_id, thread_ts, reply.text, respond, message_blocks(reply, False))
    if reply.public:
        _post_line(client, channel, thread_ts, "\n".join(filter(None, (reply.echo, reply.public))), respond)


def _respond_result(
    respond: Callable | None, client: WebClient, reply: Reply, pictures: MatchupPictures | None, **message
) -> None:
    """Where the bot cannot post (a response URL, which cannot start a thread): the card, then the log as the next
    messages."""
    if respond is None:
        log.warning("could not post a battle result")
        return
    try:
        kit.send(respond, "result card", **_card_message(reply), **message)
    except Exception:
        log.warning("could not post a battle result by response url")
        return
    post_log(partial(respond, **message), client, reply, pictures)


def _post_line(
    client: WebClient, channel: str, thread_ts: str | None, text: str, respond: Callable | None, blocks: list[dict] | None = None
) -> None:
    try:
        kit.send(client.chat_postMessage, "reply", channel=channel, thread_ts=thread_ts, text=text, blocks=blocks)
    except Exception:
        _fallback(respond, text=text, blocks=blocks, thread_ts=thread_ts, response_type="in_channel", replace_original=False)


def _private(
    client: WebClient, channel: str, user_id: str, thread_ts: str, text: str, respond: Callable | None,
    blocks: list[dict] | None = None,
) -> None:
    if respond is not None:
        kit.send(respond, "private reply", text=text, blocks=blocks, response_type="ephemeral", replace_original=False)
        return
    try:
        kit.send(client.chat_postEphemeral, "private reply", channel=channel, user=user_id, text=text,
                 thread_ts=thread_ts, blocks=blocks)
    except Exception:
        log.warning("could not post an ephemeral reply")


def _fallback(respond: Callable | None, **message) -> None:
    if respond is None:
        log.warning("could not post a reply")
        return
    try:
        kit.send(respond, "reply", **message)
    except Exception:
        log.warning("could not post a reply by response url")


def _publish_slash(
    client: WebClient, respond: Callable, channel: str, reply: Reply, pictures: MatchupPictures | None
) -> None:
    if reply.summary is not None:
        try:
            post_result(client, channel, None, reply, pictures)
        except Exception:
            log.info("bot cannot post in the channel; answering through the response url")
            _respond_result(respond, client, reply, pictures, response_type="in_channel")
        return
    if reply.public:
        kit.send(respond, "slash public", text="\n".join(filter(None, (reply.echo, reply.public))),
                 response_type="in_channel")
    visible = reply.in_channel
    text = "\n".join(filter(None, (reply.echo, reply.text))) if visible else reply.text
    kit.send(respond, "slash", text=text, blocks=message_blocks(reply, visible),
             response_type="in_channel" if visible else "ephemeral")


def socket_handler(app, app_token: str, web_client: WebClient | None = None) -> SocketModeHandler:
    """The Socket Mode handler: a dead link is noticed within seconds instead of 40–50, and every drop says why."""
    handler = SocketModeHandler(app, app_token, web_client=web_client, ping_interval=SOCKET_PING_INTERVAL)
    handler.client.on_message_listeners.append(_log_disconnect)
    handler.client.on_close_listeners.append(_log_close)
    return handler


def _log_disconnect(message: str) -> None:
    if "disconnect" not in message:
        return
    try:
        frame = json.loads(message)
    except ValueError:
        return
    if frame.get("type") == "disconnect":
        log.warning("slack asked to disconnect reason=%s", frame.get("reason"))


def _log_close(code: int, reason: str | None) -> None:
    log.warning("socket closed code=%s reason=%s", code, reason)
