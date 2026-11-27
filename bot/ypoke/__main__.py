"""Run the YPoke bot: Slack Socket Mode plus the LAN party upload server."""

import logging
import os
import re
import threading
import time
from pathlib import Path

from slack_bolt import App
from slack_sdk import WebClient

from ypoke.battle_render import MatchupPictures
from ypoke.clock import system_clock
from ypoke.commands import COMMAND_NAMES, REGISTER_ACTION_ID, REMATCH_ACTION_ID, CommandHandler
from ypoke.editor import Route, checked
from ypoke.gym_battle import GymBattles
from ypoke.tower_battle import TowerBattles
from ypoke.lineup_editor import ACTION_PREFIX, ITEM_ACTION, SET_MOVES_ACTION, SWAP_ACTION
from ypoke.miracle import ACCEPT_ACTION_ID as MIRACLE_ACCEPT_ACTION_ID
from ypoke.miracle import CANCEL_ACTION_ID as MIRACLE_CANCEL_ACTION_ID
from ypoke.miracle import PICK_ACTION_ID as MIRACLE_PICK_ACTION_ID
from ypoke.miracle import MiracleService
from ypoke.names import DisplayNames
from ypoke.pokeapi import PokeAPIService
from ypoke.remote_ops import RemoteOps
from ypoke.shop_editor import ACTION_PREFIX as SHOP_ACTION_PREFIX
from ypoke.shop_editor import PICK_ACTION as SHOP_PICK_ACTION
from ypoke.store import Store
from ypoke.trade_editor import ACTION_PREFIX as OFFER_ACTION_PREFIX
from ypoke.trade_editor import PICKER_ACTIONS as OFFER_PICKER_ACTIONS
from ypoke.trades import ACCEPT_ACTION_ID, DECLINE_ACTION_ID, PICK_ACTION_ID, TradeService
from ypoke.training_editor import ACTION_PREFIX as TRAINING_ACTION_PREFIX
from ypoke.training_editor import PICK_ACTION as TRAINING_PICK_ACTION
from ypoke.training_editor import SET_MOVES_ACTION as TRAINING_SET_MOVES_ACTION
from ypoke.transport import (
    SlackBoard,
    deliver,
    editor_listener,
    editor_options_listener,
    mention_listener,
    miracle_listener,
    options_listener,
    post_direct_messages,
    rematch_listener,
    slash_listener,
    socket_handler,
    trade_listener,
)
from ypoke.upload_server import serve

MIRACLE_SWEEP_INTERVAL = 300


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    database = os.environ.get("YPOKE_DB", "ypoke.sqlite3")
    now = system_clock
    store = Store(database, now)
    pokeapi = PokeAPIService(store)
    pictures = MatchupPictures(store, Path(os.environ.get("YPOKE_PICTURE_DIR") or Path(database).parent / "pictures"))
    app = App(token=os.environ["SLACK_BOT_TOKEN"])
    home_channel = os.environ.get("YPOKE_HOME_CHANNEL") or None
    if home_channel:
        _join(app, home_channel)
    remote = RemoteOps(store, now)
    bot_user_id = app.client.auth_test()["user_id"]
    names = DisplayNames(app.client)
    names.warm(store.linked_user_ids())
    trades = TradeService(store, now, name_for=names, bot_user_id=bot_user_id, holds=remote.holds)
    board = SlackBoard(app.client, home_channel) if home_channel else None
    miracle = MiracleService(trades, board, now)
    handler = CommandHandler(
        store,
        pokeapi,
        os.environ.get("YPOKE_PUBLIC_URL"),
        bot_user_id=bot_user_id,
        home_channel=home_channel,
        remote=remote,
        now=now,
        trades=trades,
        miracle=miracle,
    )
    serve(
        store,
        os.environ.get("YPOKE_HTTP_HOST", "0.0.0.0"),
        int(os.environ.get("YPOKE_HTTP_PORT", "8790")),
        lambda user_id, party: _after_upload(pokeapi, handler, app.client, user_id, party, pictures),
        pokeapi.attacking_moves,
        names,
        trades,
        lambda messages: post_direct_messages(app.client, messages),
        GymBattles(pokeapi),
        miracle=miracle,
        remote=remote,
        now=now,
        tower=TowerBattles(store, pokeapi, boast=board.say if board else None),
    )
    threading.Thread(target=_warm_stored_parties, args=(pokeapi, store, remote), daemon=True).start()
    threading.Thread(target=_sweep_miracle_offers, args=(miracle,), daemon=True).start()
    register(app, handler, trades, miracle, pictures)
    socket_handler(app, os.environ["SLACK_APP_TOKEN"]).start()


def register(app: App, handler: CommandHandler, trades: TradeService, miracle: MiracleService,
             pictures: MatchupPictures) -> None:
    for name in COMMAND_NAMES:
        app.command(name)(slash_listener(handler, pictures))
    # Slack still sends an interaction for a URL button and shows a warning unless it is acked.
    app.action(REGISTER_ACTION_ID)(lambda ack: ack())
    app.action(REMATCH_ACTION_ID)(rematch_listener(handler, pictures))
    app.action(PICK_ACTION_ID)(trade_listener(trades, "pick"))
    app.action(ACCEPT_ACTION_ID)(trade_listener(trades, "accept"))
    app.action(DECLINE_ACTION_ID)(trade_listener(trades, "decline"))
    app.action(MIRACLE_ACCEPT_ACTION_ID)(miracle_listener(miracle, "accept"))
    app.action(MIRACLE_CANCEL_ACTION_ID)(miracle_listener(miracle, "cancel"))
    app.action(MIRACLE_PICK_ACTION_ID)(miracle_listener(miracle, "pick"))
    app.options(PICK_ACTION_ID)(options_listener(trades))
    app.options(MIRACLE_PICK_ACTION_ID)(options_listener(trades))
    for route in editor_routes(handler):
        app.action(re.compile(f"^{route.prefix}"))(editor_listener(route.editor))
        for action_id, method in route.menus:
            app.options(action_id)(editor_options_listener(route.editor, getattr(route.editor, method)))
    app.event("app_mention")(mention_listener(handler, pictures))


def editor_routes(handler: CommandHandler) -> list[Route]:
    """`train_open` on the `/파티` screen sits under the training prefix, so the training editor answers it."""
    return checked([
        Route(ACTION_PREFIX, handler.editor,
              ((SWAP_ACTION, "options"), (ITEM_ACTION, "item_options"), (SET_MOVES_ACTION, "move_options"))),
        Route(SHOP_ACTION_PREFIX, handler.shop, ((SHOP_PICK_ACTION, "options"),)),
        Route(TRAINING_ACTION_PREFIX, handler.training,
              ((TRAINING_PICK_ACTION, "options"), (TRAINING_SET_MOVES_ACTION, "move_options"))),
        Route(OFFER_ACTION_PREFIX, handler.trading, tuple((action_id, "options") for action_id in OFFER_PICKER_ACTIONS)),
    ])


def _join(app: App, channel: str) -> None:
    try:
        app.client.conversations_join(channel=channel)
    except Exception:
        logging.getLogger(__name__).warning("could not join the home channel")


def _after_upload(
    pokeapi: PokeAPIService, handler: CommandHandler, client: WebClient, user_id: str, party: list[dict],
    pictures: MatchupPictures,
) -> None:
    threading.Thread(
        target=_run_after_upload, args=(pokeapi, handler, client, user_id, party, pictures), daemon=True
    ).start()


def _run_after_upload(
    pokeapi: PokeAPIService, handler: CommandHandler, client: WebClient, user_id: str, party: list[dict],
    pictures: MatchupPictures | None = None,
) -> None:
    _warm(pokeapi, party)
    try:
        deliveries = handler.run_pending(user_id)
    except Exception:
        logging.getLogger(__name__).exception("pending battles failed")
        return
    for delivery in deliveries:
        deliver(client, delivery, pictures)


def _warm(pokeapi: PokeAPIService, members: list[dict]) -> None:
    started = time.monotonic()
    try:
        count = pokeapi.warm(members)
    except Exception:
        logging.getLogger(__name__).warning("PokéAPI warming failed", exc_info=True)
        return
    logging.getLogger(__name__).info("warmed %d Pokémon in %.1fs", count, time.monotonic() - started)


def _sweep_miracle_offers(miracle: MiracleService) -> None:
    """Expired offers also end when anyone uses the feature; this marks their cards when nobody does."""
    while True:
        try:
            miracle.sweep()
        except Exception:
            logging.getLogger(__name__).exception("miracle sweep failed")
        time.sleep(MIRACLE_SWEEP_INTERVAL)


def _warm_stored_parties(pokeapi: PokeAPIService, store: Store, remote: RemoteOps) -> None:
    """One member at a time so live battles still get request slots."""
    for user_id in store.linked_user_ids():
        stored = remote.party(user_id)
        for member in stored.party if stored else []:
            _warm(pokeapi, [member])


if __name__ == "__main__":
    main()
