"""Run the YPoke bot: Slack Socket Mode plus the LAN party upload server."""

import logging
import os
import threading

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

from ypoke.commands import COMMAND_NAMES, REGISTER_ACTION_ID, CommandHandler, Reply, reply_thread_ts
from ypoke.pokeapi import PokeAPIService
from ypoke.store import Store
from ypoke.upload_server import serve

def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    store = Store(os.environ.get("YPOKE_DB", "ypoke.sqlite3"))
    pokeapi = PokeAPIService(store)
    port = int(os.environ.get("YPOKE_HTTP_PORT", "8790"))
    serve(store, os.environ.get("YPOKE_HTTP_HOST", "0.0.0.0"), port, lambda party: _warm_cache(pokeapi, party))
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


def _warm_cache(pokeapi: PokeAPIService, party: list[dict]) -> None:
    threading.Thread(target=_fetch_all, args=(pokeapi, party), daemon=True).start()


def _slash_listener(handler: CommandHandler):
    def listener(ack, body, respond, client) -> None:
        ack()
        try:
            reply = handler.handle(body["user_id"], body.get("text", ""), body["command"])
        except Exception:
            logging.getLogger(__name__).exception("command failed")
            respond(text="대결 봇에서 오류가 났어요. 잠시 뒤 다시 해 주세요.", response_type="ephemeral")
            return
        if reply.direct_message is not None:
            client.chat_postMessage(
                channel=body["user_id"], text=reply.direct_message, blocks=reply.direct_message_blocks
            )
        respond(text=reply.text, response_type="in_channel" if reply.in_channel else "ephemeral")

    return listener


def _mention_listener(handler: CommandHandler):
    def listener(event, say, client) -> None:
        thread_ts = reply_thread_ts(event)
        try:
            reply = handler.handle_mention(event["user"], event.get("text", ""))
        except Exception:
            logging.getLogger(__name__).exception("mention failed")
            reply = Reply("대결 봇에서 오류가 났어요. 잠시 뒤 다시 해 주세요.")
        if reply.direct_message is not None:
            client.chat_postMessage(
                channel=event["user"], text=reply.direct_message, blocks=reply.direct_message_blocks
            )
        if reply.in_channel:
            say(text=reply.text, thread_ts=thread_ts)
        else:
            client.chat_postEphemeral(
                channel=event["channel"], user=event["user"], text=reply.text, thread_ts=thread_ts
            )

    return listener


def _fetch_all(pokeapi: PokeAPIService, party: list[dict]) -> None:
    for member in party:
        try:
            pokeapi.pokemon(member["pokemon_id"])
        except Exception:
            logging.getLogger(__name__).warning("PokéAPI prefetch failed for %s", member["pokemon_id"])


if __name__ == "__main__":
    main()
