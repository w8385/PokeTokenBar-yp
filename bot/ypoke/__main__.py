"""Run the YPoke bot: Slack Socket Mode plus the LAN party upload server."""

import logging
import os
import threading

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler
from slack_sdk import WebClient
from slack_sdk.webhook import WebhookClient

from ypoke.commands import (
    COMMAND_NAMES,
    REGISTER_ACTION_ID,
    CommandHandler,
    Delivery,
    Reply,
    Where,
    reply_thread_ts,
)
from ypoke.pokeapi import PokeAPIService
from ypoke.store import Store
from ypoke.upload_server import serve

DM_FALLBACK_NOTE = "(대결을 신청한 곳에 올릴 수 없어서 DM으로 보내요)"

def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    store = Store(os.environ.get("YPOKE_DB", "ypoke.sqlite3"))
    pokeapi = PokeAPIService(store)
    app = App(token=os.environ["SLACK_BOT_TOKEN"])
    home_channel = os.environ.get("YPOKE_HOME_CHANNEL") or None
    if home_channel:
        _join(app, home_channel)
    handler = CommandHandler(
        store,
        pokeapi,
        os.environ.get("YPOKE_PUBLIC_URL"),
        bot_user_id=app.client.auth_test()["user_id"],
        home_channel=home_channel,
    )
    serve(
        store,
        os.environ.get("YPOKE_HTTP_HOST", "0.0.0.0"),
        int(os.environ.get("YPOKE_HTTP_PORT", "8790")),
        lambda user_id, party: _after_upload(pokeapi, handler, app.client, user_id, party),
        pokeapi.attacking_moves,
    )
    for name in COMMAND_NAMES:
        app.command(name)(_slash_listener(handler))
    # Slack still sends an interaction for a URL button and shows a warning unless it is acked.
    app.action(REGISTER_ACTION_ID)(lambda ack: ack())
    app.event("app_mention")(_mention_listener(handler))
    SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"]).start()


def _join(app: App, channel: str) -> None:
    try:
        app.client.conversations_join(channel=channel)
    except Exception:
        logging.getLogger(__name__).warning("could not join the home channel")


def _after_upload(
    pokeapi: PokeAPIService, handler: CommandHandler, client: WebClient, user_id: str, party: list[dict]
) -> None:
    threading.Thread(
        target=_run_after_upload, args=(pokeapi, handler, client, user_id, party), daemon=True
    ).start()


def _slash_listener(handler: CommandHandler):
    def listener(ack, body, respond, client) -> None:
        ack()
        where = Where(body["channel_id"], response_url=body.get("response_url"))
        try:
            reply = handler.handle(body["user_id"], body.get("text", ""), body["command"], where)
        except Exception:
            logging.getLogger(__name__).exception("command failed")
            respond(text="대결 봇에서 오류가 났어요. 잠시 뒤 다시 해 주세요.", response_type="ephemeral")
            return
        _send_direct_messages(client, reply)
        respond(text=reply.text, response_type="in_channel" if reply.in_channel else "ephemeral")

    return listener


def _mention_listener(handler: CommandHandler):
    def listener(event, say, client) -> None:
        thread_ts = reply_thread_ts(event)
        try:
            reply = handler.handle_mention(event["user"], event.get("text", ""), Where(event["channel"], thread_ts))
        except Exception:
            logging.getLogger(__name__).exception("mention failed")
            reply = Reply("대결 봇에서 오류가 났어요. 잠시 뒤 다시 해 주세요.")
        _send_direct_messages(client, reply)
        if reply.in_channel:
            say(text=reply.text, thread_ts=thread_ts)
        else:
            client.chat_postEphemeral(
                channel=event["channel"], user=event["user"], text=reply.text, thread_ts=thread_ts
            )

    return listener


def _run_after_upload(
    pokeapi: PokeAPIService, handler: CommandHandler, client: WebClient, user_id: str, party: list[dict]
) -> None:
    _prefetch_lead(pokeapi, party)
    try:
        deliveries = handler.run_pending(user_id)
    except Exception:
        logging.getLogger(__name__).exception("pending battles failed")
        return
    for delivery in deliveries:
        _deliver(client, delivery)


def _send_direct_messages(client: WebClient, reply: Reply) -> None:
    for message in reply.direct_messages:
        try:
            client.chat_postMessage(channel=message.user_id, text=message.text, blocks=message.blocks)
        except Exception:
            logging.getLogger(__name__).warning("could not send a direct message")


def _deliver(client: WebClient, delivery: Delivery) -> None:
    """Post where the challenge was made: the slash command's response URL while fresh, then the channel,
    then a DM to the challenger when the bot cannot post there (a private channel it is not in)."""
    where = delivery.where
    if where.response_url:
        try:
            if WebhookClient(where.response_url).send(text=delivery.text, response_type="in_channel").status_code == 200:
                return
        except Exception:
            pass
    try:
        client.chat_postMessage(channel=where.channel_id, text=delivery.text, thread_ts=where.thread_ts)
        return
    except Exception:
        logging.getLogger(__name__).warning("could not post a pending battle in its channel")
    try:
        client.chat_postMessage(channel=delivery.challenger_id, text=f"{DM_FALLBACK_NOTE}\n{delivery.text}")
    except Exception:
        logging.getLogger(__name__).warning("could not deliver a pending battle")


def _prefetch_lead(pokeapi: PokeAPIService, party: list[dict]) -> None:
    lead = party[0]
    try:
        pokeapi.pokemon(lead["pokemon_id"])
        pokeapi.attacking_moves(lead["pokemon_id"], lead["level"])
    except Exception:
        logging.getLogger(__name__).warning("PokéAPI prefetch failed for %s", lead["pokemon_id"])


if __name__ == "__main__":
    main()
