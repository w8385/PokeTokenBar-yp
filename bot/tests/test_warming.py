import logging

from ypoke import __main__ as bot
from ypoke.store import Store


class FakePokeAPI:
    def __init__(self, fail=False):
        self.fail = fail
        self.warmed = []

    def warm(self, members):
        self.warmed.append(members)
        if self.fail:
            raise OSError("offline")
        return len({member["pokemon_id"] for member in members})


class FakeHandler:
    def __init__(self):
        self.pending_for = []

    def run_pending(self, user_id):
        self.pending_for.append(user_id)
        return []


def member(pokemon_id, level=30):
    return {"pokemon_id": pokemon_id, "level": level, "shiny": False, "ivs": {}}


def test_an_upload_warms_every_entry_member_before_pending_battles_run():
    pokeapi, handler = FakePokeAPI(), FakeHandler()
    party = [member(25), member(7), member(1), member(4)]
    bot._run_after_upload(pokeapi, handler, None, "UA", party)
    assert pokeapi.warmed == [party[:3]]
    assert handler.pending_for == ["UA"]


def test_a_failed_warm_is_logged_and_does_not_stop_pending_battles(caplog):
    pokeapi, handler = FakePokeAPI(fail=True), FakeHandler()
    with caplog.at_level(logging.WARNING):
        bot._run_after_upload(pokeapi, handler, None, "UA", [member(25)])
    assert "warming failed" in caplog.text
    assert handler.pending_for == ["UA"]


def test_startup_warms_each_stored_entry_member_one_at_a_time(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    for user_id, party in (("UA", [member(25), member(7)]), ("UB", [member(1)]), ("UC", None)):
        store.issue_token(user_id)
        if party:
            store.save_party(user_id, party)
    pokeapi = FakePokeAPI()
    bot._warm_stored_parties(pokeapi, store)
    assert sorted(call[0]["pokemon_id"] for call in pokeapi.warmed) == [1, 7, 25]
    assert all(len(call) == 1 for call in pokeapi.warmed)
