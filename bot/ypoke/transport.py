"""Slack listeners: turn a handler Reply into messages, and log who ran which command."""

import json
import logging
from collections.abc import Callable

from slack_sdk import WebClient
from slack_sdk.webhook import WebhookClient

from ypoke.commands import (
    CommandHandler,
    Delivery,
    Reply,
    Where,
    fallback_text,
    fit,
    parse_mention,
    reply_thread_ts,
    result_blocks,
)

DM_FALLBACK_NOTE = "(대결을 신청한 곳에 올릴 수 없어서 DM으로 보내요)"
ERROR_TEXT = "대결 봇에서 오류가 났어요. 잠시 뒤 다시 해 주세요."
LOG_TEXT_LIMIT = 3900
LOG_ARGS_LIMIT = 200

log = logging.getLogger(__name__)


def log_command(source: str, user_id: str, command: str, args: str) -> None:
    """One INFO line: who, which command, its text. Never the request body, so no tokens or response URLs."""
    log.info("%s user=%s command=%s args=%s", source, user_id, command,
             json.dumps(args[:LOG_ARGS_LIMIT], ensure_ascii=False))


def slash_listener(handler: CommandHandler):
    def listener(ack, body, respond, client) -> None:
        ack()
        user_id, command, text = body["user_id"], body["command"], body.get("text", "")
        log_command("slash", user_id, command, text)
        where = Where(body["channel_id"], response_url=body.get("response_url"))
        try:
            reply = handler.handle(user_id, text, command, where, echo=True)
        except Exception:
            log.exception("command failed")
            respond(text=ERROR_TEXT, response_type="ephemeral")
            return
        send_direct_messages(client, reply)
        _publish_slash(client, respond, where.channel_id, reply)

    return listener


def mention_listener(handler: CommandHandler):
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
        publish_in_thread(client, event["channel"], event["user"], thread_ts, reply)

    return listener


def rematch_listener(handler: CommandHandler):
    def listener(ack, body, action, respond, client) -> None:
        ack()
        user_id, channel_id = body["user"]["id"], body["channel"]["id"]
        message = body["message"]
        thread_ts = message.get("thread_ts") or message["ts"]
        log_command("button", user_id, "rematch", action["value"])
        try:
            reply = handler.rematch(user_id, action["value"], Where(channel_id, thread_ts))
        except Exception:
            log.exception("rematch failed")
            reply = Reply(ERROR_TEXT)
        send_direct_messages(client, reply)
        publish_in_thread(client, channel_id, user_id, thread_ts, reply, respond)

    return listener


def send_direct_messages(client: WebClient, reply: Reply) -> None:
    for message in reply.direct_messages:
        try:
            client.chat_postMessage(channel=message.user_id, text=message.text, blocks=message.blocks)
        except Exception:
            log.warning("could not send a direct message")


def post_result(client: WebClient, channel: str, thread_ts: str | None, reply: Reply) -> None:
    """The summary with its button, then the turn log as the first reply in that message's thread."""
    root = client.chat_postMessage(
        channel=channel, thread_ts=thread_ts, text=fallback_text(reply), blocks=result_blocks(reply)
    )
    try:
        client.chat_postMessage(channel=channel, thread_ts=thread_ts or root["ts"], text=fit(reply.text, LOG_TEXT_LIMIT))
    except Exception:
        log.warning("could not post the turn log")


def deliver(client: WebClient, delivery: Delivery) -> None:
    """Post a pending battle where it was asked for: the channel (thread), the slash command's still-fresh
    response URL with the log inline, then a DM to the challenger when the bot cannot post there."""
    where, reply = delivery.where, delivery.reply
    try:
        post_result(client, where.channel_id, where.thread_ts, reply)
        return
    except Exception:
        log.warning("could not post a pending battle in its channel")
    if where.response_url:
        try:
            sent = WebhookClient(where.response_url).send(
                text=fallback_text(reply), blocks=result_blocks(reply, with_log=True), response_type="in_channel"
            )
            if sent.status_code == 200:
                return
        except Exception:
            log.warning("could not post a pending battle by response url")
    try:
        client.chat_postMessage(
            channel=delivery.challenger_id, text=f"{DM_FALLBACK_NOTE}\n{fallback_text(reply)}\n{reply.text}"
        )
    except Exception:
        log.warning("could not deliver a pending battle")


def publish_in_thread(
    client: WebClient, channel: str, user_id: str, thread_ts: str, reply: Reply, respond: Callable | None = None
) -> None:
    """Visible replies go in the thread; private ones are ephemeral. `respond` (a button's response URL) is the
    fallback where the bot cannot post, such as a conversation it is not in."""
    visible = {"thread_ts": thread_ts, "response_type": "in_channel", "replace_original": False}
    if reply.summary is not None:
        try:
            post_result(client, channel, thread_ts, reply)
        except Exception:
            _fallback(respond, text=fallback_text(reply), blocks=result_blocks(reply, with_log=True), **visible)
    elif reply.in_channel:
        _post_line(client, channel, thread_ts, "\n".join(filter(None, (reply.echo, reply.text))), respond)
    else:
        _private(client, channel, user_id, thread_ts, reply.text, respond)
    if reply.public:
        _post_line(client, channel, thread_ts, "\n".join(filter(None, (reply.echo, reply.public))), respond)


def _post_line(client: WebClient, channel: str, thread_ts: str, text: str, respond: Callable | None) -> None:
    try:
        client.chat_postMessage(channel=channel, thread_ts=thread_ts, text=text)
    except Exception:
        _fallback(respond, text=text, thread_ts=thread_ts, response_type="in_channel", replace_original=False)


def _private(client: WebClient, channel: str, user_id: str, thread_ts: str, text: str, respond: Callable | None) -> None:
    if respond is not None:
        respond(text=text, response_type="ephemeral", replace_original=False)
        return
    try:
        client.chat_postEphemeral(channel=channel, user=user_id, text=text, thread_ts=thread_ts)
    except Exception:
        log.warning("could not post an ephemeral reply")


def _fallback(respond: Callable | None, **message) -> None:
    if respond is None:
        log.warning("could not post a reply")
        return
    try:
        response = respond(**message)
        log.info("response url answered %s %s", getattr(response, "status_code", None), str(getattr(response, "body", ""))[:80])
    except Exception:
        log.warning("could not post a reply by response url")


def _publish_slash(client: WebClient, respond: Callable, channel: str, reply: Reply) -> None:
    if reply.summary is not None:
        try:
            post_result(client, channel, None, reply)
        except Exception:
            log.info("bot cannot post in the channel; answering through the response url")
            respond(text=fallback_text(reply), blocks=result_blocks(reply, with_log=True), response_type="in_channel")
        return
    if reply.public:
        respond(text="\n".join(filter(None, (reply.echo, reply.public))), response_type="in_channel")
    visible = reply.in_channel
    text = "\n".join(filter(None, (reply.echo, reply.text))) if visible else reply.text
    respond(text=text, response_type="in_channel" if visible else "ephemeral")
