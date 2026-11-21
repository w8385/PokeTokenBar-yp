import sqlite3
from datetime import UTC, datetime, timedelta

import pytest
from test_trades import ALICE, HAUNTER

from ypoke import miracle, remote_ops, store as store_module, trades, upload_server
from ypoke.miracle import MiracleService
from ypoke.remote_ops import RemoteOps
from ypoke.store import Store
from ypoke.trades import TRADE_LIFETIME, TradeService
from ypoke.upload_server import COWORKER_WINDOW, battle_overview

T0 = datetime(2026, 3, 4, 5, 6, 7, tzinfo=UTC)
PARTY = [{"pokemon_id": 25, "level": 30, "moves": [84], "name": "피카츄"}]


class Frozen:
    now = T0

    @classmethod
    def at(cls, moment):
        cls.now = moment


@pytest.fixture
def frozen(monkeypatch):
    class Moment(datetime):
        @classmethod
        def now(cls, tz=None):
            return Frozen.now

    Frozen.now = T0
    for module in (store_module, upload_server, trades, miracle, remote_ops):
        monkeypatch.setattr(module, "datetime", Moment)
    return Frozen


@pytest.fixture
def store(tmp_path):
    return Store(str(tmp_path / "bot.sqlite3"))


def test_a_stored_party_is_stamped_with_the_current_time(frozen, store):
    store.issue_token("UA", keep_existing=True)
    store.save_party("UA", PARTY)

    assert store.party("UA").uploaded_at == "2026-03-04T05:06:07+00:00"


def test_a_rematch_claim_is_stamped_with_the_current_time(frozen, store, tmp_path):
    assert store.claim_rematch("C1", "1.0")

    with sqlite3.connect(tmp_path / "bot.sqlite3") as connection:
        assert connection.execute("SELECT claimed_at FROM rematch_claims").fetchall() == [("2026-03-04T05:06:07+00:00",)]


def test_a_recorded_battle_without_a_time_is_stamped_with_the_current_time(frozen, store):
    store.record_battle("UA", "UB", "UA", 7)

    assert store.recent_battles("UA", 5)[0].at == "2026-03-04T05:06:07+00:00"


def test_a_coworker_lead_shows_until_the_window_is_one_second_past(frozen, store):
    store.issue_token("UB", keep_existing=True)
    store.save_party("UB", PARTY)
    remote = RemoteOps(store)

    def coworkers():
        return battle_overview(store, "UA", lambda user_id: user_id, remote)["coworkers"]

    frozen.at(T0 + COWORKER_WINDOW)
    assert [lead["name"] for lead in coworkers()] == ["UB"]
    frozen.at(T0 + COWORKER_WINDOW + timedelta(seconds=1))
    assert coworkers() == []


def test_a_miracle_offer_expires_one_trade_lifetime_after_it_was_posted(frozen, store):
    service = TradeService(store)
    service.save_pool(ALICE, [HAUNTER])
    offers = MiracleService(service, FakeBoard())

    brief = offers.post(ALICE, HAUNTER["id"]).offer

    assert brief["expires_at"] == (T0 + TRADE_LIFETIME).isoformat(timespec="seconds")


class FakeBoard:
    def post(self, text, blocks):
        return "1700000000.000001"

    def update(self, ts, text, blocks):
        pass
