import json
import threading
import time
import urllib.error

import pytest

from ypoke import pokeapi
from ypoke.commands import CommandHandler
from ypoke.pokeapi import PokeAPIService, learnset_from, move_from
from ypoke.store import Store

GROUPS = {"red-blue": 1, "sword-shield": 20, "scarlet-violet": 25, "legends-za": 30}


def learned(move_id, *details):
    return {
        "move": {"name": f"m{move_id}", "url": f"https://pokeapi.co/api/v2/move/{move_id}/"},
        "version_group_details": [
            {"level_learned_at": level, "move_learn_method": {"name": method},
             "version_group": {"name": group, "url": f"https://pokeapi.co/api/v2/version-group/{GROUPS[group]}/"}}
            for group, method, level in details
        ],
    }


def test_learnset_uses_the_newest_main_game_and_its_lowest_level():
    body = {"moves": [
        learned(84, ("red-blue", "level-up", 1), ("scarlet-violet", "level-up", 1), ("scarlet-violet", "level-up", 8)),
        learned(85, ("scarlet-violet", "level-up", 36), ("legends-za", "level-up", 20)),
        learned(87, ("sword-shield", "level-up", 30)),
        learned(9, ("scarlet-violet", "machine", 0)),
    ]}
    assert learnset_from(body) == [{"move_id": 84, "level": 1}, {"move_id": 85, "level": 36}]


def test_learnset_falls_back_to_a_side_game_when_no_main_game_has_it():
    body = {"moves": [learned(85, ("legends-za", "level-up", 20))]}
    assert learnset_from(body) == [{"move_id": 85, "level": 20}]
    assert learnset_from({"moves": []}) == []


MOVES = {
    84: {"id": 84, "names": [{"language": {"name": "ko"}, "name": "전기쇼크"}], "name": "thunder-shock",
         "type": {"name": "electric"}, "power": 40, "damage_class": {"name": "special"}, "accuracy": 100, "pp": 30,
         "priority": 0, "meta": {"ailment": {"name": "paralysis"}, "ailment_chance": 10, "category": {"name": "damage-ailment"},
                  "crit_rate": 0, "stat_chance": 0},
         "stat_changes": []},
    86: {"id": 86, "names": [{"language": {"name": "ko"}, "name": "전기자석파"}], "name": "thunder-wave",
         "type": {"name": "electric"}, "power": None, "damage_class": {"name": "status"}, "accuracy": 90, "pp": 20, "priority": 0},
    360: {"id": 360, "names": [{"language": {"name": "en"}, "name": "Gyro Ball"}], "name": "gyro-ball",
          "type": {"name": "steel"}, "power": None, "damage_class": {"name": "physical"}, "accuracy": 100, "pp": 5, "priority": 0},
    240: {"id": 240, "names": [{"language": {"name": "ko"}, "name": "비바라기"}], "name": "rain-dance",
          "type": {"name": "water"}, "power": None, "damage_class": {"name": "status"}, "accuracy": None, "pp": 5,
          "priority": 0, "meta": {"ailment": {"name": "none"}, "category": {"name": "field-effect"}}},
    85: {"id": 85, "names": [], "name": "thunderbolt",
         "type": {"name": "electric"}, "power": 90, "damage_class": {"name": "special"}, "accuracy": 100, "pp": 15, "priority": 0, "meta": None},
}
PIKACHU = {"moves": [
    learned(84, ("scarlet-violet", "level-up", 1)),
    learned(86, ("scarlet-violet", "level-up", 4)),
    learned(360, ("scarlet-violet", "level-up", 10)),
    learned(240, ("scarlet-violet", "level-up", 20)),
    learned(85, ("scarlet-violet", "level-up", 36)),
]}


POKEMON_BODY = {
    **PIKACHU, "name": "pikachu", "species": {"url": "https://pokeapi.co/api/v2/pokemon-species/25/"},
    "types": [{"slot": 1, "type": {"name": "electric"}}],
    "stats": [{"stat": {"name": "hp"}, "base_stat": 35}, {"stat": {"name": "attack"}, "base_stat": 55},
              {"stat": {"name": "defense"}, "base_stat": 40}, {"stat": {"name": "special-attack"}, "base_stat": 50},
              {"stat": {"name": "special-defense"}, "base_stat": 50}, {"stat": {"name": "speed"}, "base_stat": 90}],
}
SPECIES_BODY = {"names": [{"language": {"name": "ko"}, "name": "피카츄"}]}


@pytest.fixture
def service(tmp_path, monkeypatch):
    fetched = []

    def get_json(url):
        fetched.append(url)
        kind, item = url.rstrip("/").rsplit("/", 2)[-2:]
        if kind == "pokemon-species":
            return SPECIES_BODY
        return POKEMON_BODY if kind == "pokemon" else MOVES[int(item)]

    monkeypatch.setattr(pokeapi, "_get_json", get_json)
    return PokeAPIService(Store(str(tmp_path / "bot.sqlite3"))), fetched


def test_attacking_moves_keep_weather_moves_skip_other_status_and_powerless_moves_and_respect_the_level(service):
    api, _ = service
    assert api.attacking_moves(25, 35) == [
        {"id": 84, "name": "전기쇼크", "type": "electric", "power": 40, "damage_class": "special", "accuracy": 100,
         "pp": 30, "priority": 0, "crit_rate": 0, "ailment": "paralysis", "ailment_chance": 10, "stat_changes": [],
         "stat_target": "target", "stat_chance": 0, "drain": 0, "min_hits": 1, "max_hits": 1, "weather": None,
         "always_hits_in": [], "level": 1},
        {"id": 240, "name": "비바라기", "type": "water", "power": 0, "damage_class": "status", "accuracy": None,
         "pp": 5, "priority": 0, "crit_rate": 0, "ailment": None, "ailment_chance": 0, "stat_changes": [],
         "stat_target": "target", "stat_chance": 0, "drain": 0, "min_hits": 1, "max_hits": 1, "weather": "rain",
         "always_hits_in": [], "level": 20},
    ]
    assert [move["name"] for move in api.attacking_moves(25, 36)] == ["전기쇼크", "비바라기", "thunderbolt"]


@pytest.mark.parametrize("move_id, weather, always_hits_in", [
    (241, "sun", []), (240, "rain", []), (201, "sandstorm", []), (258, "hail", []), (883, "snow", []),
    (87, None, ["rain"]), (542, None, ["rain"]), (59, None, ["hail", "snow"]), (85, None, []),
])
def test_move_from_flags_weather_setters_and_moves_that_never_miss_in_weather(move_id, weather, always_hits_in):
    data = move_from({**body("damage"), "id": move_id})
    assert (data["weather"], data["always_hits_in"]) == (weather, always_hits_in)


def timeout_error():
    return TimeoutError("timed out")


def connect_timeout():
    return urllib.error.URLError(TimeoutError("timed out"))


def server_error():
    return urllib.error.HTTPError("https://pokeapi.co", 503, "unavailable", None, None)


@pytest.fixture
def no_sleep(monkeypatch):
    sleeps = []
    monkeypatch.setattr(pokeapi.time, "sleep", sleeps.append)
    return sleeps


@pytest.mark.parametrize("make_error", [timeout_error, connect_timeout, server_error])
def test_one_transient_failure_is_retried_after_a_backoff(monkeypatch, no_sleep, make_error):
    calls = []

    def read(request):
        calls.append(request)
        if len(calls) == 1:
            raise make_error()
        return {"ok": True}

    monkeypatch.setattr(pokeapi, "_read", read)
    assert pokeapi._get_json("https://pokeapi.co/api/v2/move/85/") == {"ok": True}
    assert (len(calls), no_sleep) == (2, [pokeapi.RETRY_BACKOFF_SECONDS])


@pytest.mark.parametrize("make_error", [timeout_error, connect_timeout, server_error])
def test_two_transient_failures_raise_the_error(monkeypatch, no_sleep, make_error):
    calls = []

    def read(request):
        calls.append(request)
        raise make_error()

    monkeypatch.setattr(pokeapi, "_read", read)
    with pytest.raises(OSError):
        pokeapi._get_json("https://pokeapi.co/api/v2/move/85/")
    assert len(calls) == 2


@pytest.mark.parametrize("error", [
    urllib.error.HTTPError("https://pokeapi.co", 404, "missing", None, None),
    urllib.error.URLError(ConnectionRefusedError()),
])
def test_other_failures_are_not_retried(monkeypatch, no_sleep, error):
    calls = []

    def read(request):
        calls.append(request)
        raise error

    monkeypatch.setattr(pokeapi, "_read", read)
    with pytest.raises(OSError):
        pokeapi._get_json("https://pokeapi.co/api/v2/move/85/")
    assert len(calls) == 1


def test_learnsets_and_moves_are_cached(service):
    api, fetched = service
    api.attacking_moves(25, 50)
    count = len(fetched)
    api.attacking_moves(25, 50)
    assert len(fetched) == count == 1 + len(MOVES)


def body(category, ailment="none", ailment_chance=0, stat_changes=(), stat_chance=0, crit_rate=0, priority=0,
         drain=0, hits=(None, None), move_id=1):
    return {
        "id": move_id, "names": [{"language": {"name": "ko"}, "name": "기술"}], "name": "move", "type": {"name": "fire"},
        "power": 80, "damage_class": {"name": "physical"}, "accuracy": 100, "pp": 15, "priority": priority,
        "meta": {"ailment": {"name": ailment}, "ailment_chance": ailment_chance, "category": {"name": category},
                 "crit_rate": crit_rate, "stat_chance": stat_chance, "drain": drain,
                 "min_hits": hits[0], "max_hits": hits[1]},
        "stat_changes": [{"stat": {"name": stat}, "change": change} for stat, change in stat_changes],
    }


@pytest.mark.parametrize("move,expected", [
    (body("damage-ailment", "burn", 10), {"ailment": "burn", "ailment_chance": 10}),
    (body("damage-ailment", "poison", 30), {"ailment": "poison", "ailment_chance": 30}),
    (body("damage-ailment", "poison", 50, move_id=305), {"ailment": "toxic", "ailment_chance": 50}),
    (body("damage-ailment", "sleep", 10), {"ailment": "sleep", "ailment_chance": 10}),
    (body("damage-ailment", "freeze", 10), {"ailment": "freeze", "ailment_chance": 10}),
    (body("damage-ailment", "confusion", 20), {"ailment": "confusion", "ailment_chance": 20}),
    (body("damage-ailment", "trap", 100), {"ailment": None, "ailment_chance": 0}),
    (body("damage+heal", drain=50), {"drain": 50}),
    (body("damage", drain=-33), {"drain": -33}),
    (body("damage", hits=(2, 5)), {"min_hits": 2, "max_hits": 5}),
    (body("damage"), {"drain": 0, "min_hits": 1, "max_hits": 1}),
    (body("damage-lower", stat_changes=[("defense", -1)], stat_chance=20),
     {"stat_changes": [{"stat": "defense", "change": -1}], "stat_target": "target", "stat_chance": 20}),
    (body("damage-raise", stat_changes=[("special-attack", -2)], stat_chance=100),
     {"stat_changes": [{"stat": "special_attack", "change": -2}], "stat_target": "user", "stat_chance": 100}),
    (body("damage-lower", stat_changes=[("accuracy", -1)], stat_chance=30), {"stat_changes": [], "stat_chance": 0}),
    (body("damage", crit_rate=1), {"crit_rate": 1, "pp": 15}),
    (body("damage", priority=1), {"priority": 1}),
    (body("damage"), {"priority": 0}),
])
def test_move_keeps_only_the_simulated_secondary_effects(move, expected):
    data = move_from(move)
    assert {key: data[key] for key in expected} == expected


def test_warm_caches_every_member_so_a_later_lookup_makes_no_network_call(service):
    api, fetched = service
    members = [{"pokemon_id": 25, "level": 36}, {"pokemon_id": 25, "level": 50}, {"pokemon_id": 7, "level": 10}]
    assert api.warm(members) == 2
    warmed = len(fetched)
    api.pokemon(25)
    api.attacking_moves(25, 36)
    api.attacking_moves(25, 50)
    assert len(fetched) == warmed


def test_warm_tries_every_member_and_raises_the_first_network_error(service, monkeypatch):
    api, _ = service
    real = pokeapi._get_json

    def get_json(url):
        if url.endswith("/pokemon/7"):
            raise TimeoutError
        return real(url)

    monkeypatch.setattr(pokeapi, "_get_json", get_json)
    with pytest.raises(TimeoutError):
        api.warm([{"pokemon_id": 7, "level": 5}, {"pokemon_id": 25, "level": 36}])
    assert api.attacking_moves(25, 36)


def test_warming_never_has_more_requests_in_flight_than_the_slot_limit(tmp_path, monkeypatch):
    api = PokeAPIService(Store(str(tmp_path / "bot.sqlite3")))
    active = peak = 0
    lock = threading.Lock()

    class Response:
        def __init__(self, body):
            self.body = body

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def read(self, *args):
            return json.dumps(self.body).encode()

    def urlopen(request, timeout):
        nonlocal active, peak
        with lock:
            active += 1
            peak = max(peak, active)
        time.sleep(0.02)
        with lock:
            active -= 1
        return Response(SPECIES_BODY if "pokemon-species" in request.full_url else POKEMON_BODY)

    monkeypatch.setattr(pokeapi.urllib.request, "urlopen", urlopen)
    monkeypatch.setattr(pokeapi, "move_from", lambda body: {"id": 1, "weather": None, "power": 0, "damage_class": "status"})
    monkeypatch.setattr(pokeapi, "learnset_from", lambda body: [{"move_id": n, "level": 1} for n in range(1, 13)])
    api.warm([{"pokemon_id": species, "level": 50} for species in range(1, 4)])
    assert 1 < peak <= pokeapi.MOVE_FETCH_WORKERS


def battle_over(tmp_path, monkeypatch, outcomes):
    """Run one 1v1 battle through the real service; `outcomes` are the first reads' results, later reads succeed."""
    monkeypatch.setattr(pokeapi.time, "sleep", lambda seconds: None)
    reads = []

    def read(request):
        reads.append(request.full_url)
        if len(reads) <= len(outcomes):
            raise outcomes[len(reads) - 1]
        kind, item = request.full_url.rstrip("/").rsplit("/", 2)[-2:]
        if kind == "pokemon-species":
            return SPECIES_BODY
        return POKEMON_BODY if kind == "pokemon" else MOVES[int(item)]

    monkeypatch.setattr(pokeapi, "_read", read)
    store = Store(str(tmp_path / "bot.sqlite3"))
    for user_id, species in (("UA", 25), ("UB", 7)):
        store.issue_token(user_id)
        store.save_party(user_id, [{"pokemon_id": species, "level": 36, "shiny": False, "ivs": {}}])
    handler = CommandHandler(store, PokeAPIService(store), None, bot_user_id="UBOT")
    return handler.handle("UA", "<@UB>"), store, reads


def test_a_battle_survives_one_timeout_while_the_cache_is_cold(tmp_path, monkeypatch):
    reply, store, _ = battle_over(tmp_path, monkeypatch, [timeout_error()])
    assert "불러오지 못했어요" not in reply.text
    assert store.record("UA").wins + store.record("UA").losses == 1


def test_a_battle_with_two_timeouts_in_a_row_gives_the_ephemeral_message(tmp_path, monkeypatch):
    reply, store, _ = battle_over(tmp_path, monkeypatch, [timeout_error(), connect_timeout()])
    assert "포켓몬 정보를 불러오지 못했어요" in reply.text
    assert not reply.in_channel
    assert store.record("UA").wins + store.record("UA").losses == 0


def test_a_battle_with_every_species_cached_makes_no_network_call(tmp_path, monkeypatch):
    _, store, reads = battle_over(tmp_path, monkeypatch, [])
    assert reads
    reads.clear()
    handler = CommandHandler(store, PokeAPIService(store), None, bot_user_id="UBOT")
    assert "불러오지 못했어요" not in handler.handle("UA", "<@UB>").text
    assert reads == []
