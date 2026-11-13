"""Run the YPoke bot: Slack Socket Mode plus the LAN party upload server."""

import logging
import os
import threading

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler
from slack_sdk import WebClient

from ypoke.commands import COMMAND_NAMES, REGISTER_ACTION_ID, REMATCH_ACTION_ID, CommandHandler
from ypoke.names import DisplayNames
from ypoke.pokeapi import PokeAPIService
from ypoke.store import Store
from ypoke.trades import ACCEPT_ACTION_ID, DECLINE_ACTION_ID, PICK_ACTION_ID, TradeService
from ypoke.transport import (
    deliver,
    mention_listener,
    post_direct_messages,
    rematch_listener,
    slash_listener,
    trade_listener,
)
from ypoke.upload_server import MAX_ENTRY_SIZE, serve


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
    names = DisplayNames(app.client)
    names.warm(store.linked_user_ids())
    trades = TradeService(store, name_for=names, bot_user_id=handler.bot_user_id)
    serve(
        store,
        os.environ.get("YPOKE_HTTP_HOST", "0.0.0.0"),
        int(os.environ.get("YPOKE_HTTP_PORT", "8790")),
        lambda user_id, party: _after_upload(pokeapi, handler, app.client, user_id, party),
        pokeapi.attacking_moves,
        names,
        trades,
        lambda messages: post_direct_messages(app.client, messages),
    )
    for name in COMMAND_NAMES:
        app.command(name)(slash_listener(handler))
    # Slack still sends an interaction for a URL button and shows a warning unless it is acked.
    app.action(REGISTER_ACTION_ID)(lambda ack: ack())
    app.action(REMATCH_ACTION_ID)(rematch_listener(handler))
    app.action(PICK_ACTION_ID)(trade_listener(trades, "pick"))
    app.action(ACCEPT_ACTION_ID)(trade_listener(trades, "accept"))
    app.action(DECLINE_ACTION_ID)(trade_listener(trades, "decline"))
    app.event("app_mention")(mention_listener(handler))
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


def _run_after_upload(
    pokeapi: PokeAPIService, handler: CommandHandler, client: WebClient, user_id: str, party: list[dict]
) -> None:
    _prefetch_entry(pokeapi, party)
    try:
        deliveries = handler.run_pending(user_id)
    except Exception:
        logging.getLogger(__name__).exception("pending battles failed")
        return
    for delivery in deliveries:
        deliver(client, delivery)


def _prefetch_entry(pokeapi: PokeAPIService, party: list[dict]) -> None:
    for member in party[:MAX_ENTRY_SIZE]:
        try:
            pokeapi.pokemon(member["pokemon_id"])
            pokeapi.attacking_moves(member["pokemon_id"], member["level"])
        except Exception:
            logging.getLogger(__name__).warning("PokéAPI prefetch failed for %s", member["pokemon_id"])


if __name__ == "__main__":
    main()
