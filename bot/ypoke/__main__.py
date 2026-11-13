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
from ypoke.transport import deliver, mention_listener, rematch_listener, slash_listener
from ypoke.upload_server import serve


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
    serve(
        store,
        os.environ.get("YPOKE_HTTP_HOST", "0.0.0.0"),
        int(os.environ.get("YPOKE_HTTP_PORT", "8790")),
        lambda user_id, party: _after_upload(pokeapi, handler, app.client, user_id, party),
        pokeapi.attacking_moves,
        names,
    )
    for name in COMMAND_NAMES:
        app.command(name)(slash_listener(handler))
    # Slack still sends an interaction for a URL button and shows a warning unless it is acked.
    app.action(REGISTER_ACTION_ID)(lambda ack: ack())
    app.action(REMATCH_ACTION_ID)(rematch_listener(handler))
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
    _prefetch_lead(pokeapi, party)
    try:
        deliveries = handler.run_pending(user_id)
    except Exception:
        logging.getLogger(__name__).exception("pending battles failed")
        return
    for delivery in deliveries:
        deliver(client, delivery)


def _prefetch_lead(pokeapi: PokeAPIService, party: list[dict]) -> None:
    lead = party[0]
    try:
        pokeapi.pokemon(lead["pokemon_id"])
        pokeapi.attacking_moves(lead["pokemon_id"], lead["level"])
    except Exception:
        logging.getLogger(__name__).warning("PokéAPI prefetch failed for %s", lead["pokemon_id"])


if __name__ == "__main__":
    main()
