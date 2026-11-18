import json
import re
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from ypoke import pokeapi
from ypoke.move_effects import STATUS_MOVES
from ypoke.moves import battle_moves, default_move_ids
from ypoke.pokeapi import PokeAPIService
from ypoke.store import Store
from ypoke.upload_server import serve

SV, SWSH = ("scarlet-violet", 25), ("sword-shield", 20)


def detail(group, method, level=0):
    name, group_id = group
    return {"level_learned_at": level, "move_learn_method": {"name": method},
            "version_group": {"name": name, "url": f"https://pokeapi.co/api/v2/version-group/{group_id}/"}}


def entry(move_id, *details):
    return {"move": {"name": f"m{move_id}", "url": f"https://pokeapi.co/api/v2/move/{move_id}/"},
            "version_group_details": list(details)}


def move_body(move_id, power, damage_class="physical"):
    return {"id": move_id, "names": [], "name": f"move-{move_id}", "type": {"name": "ground"}, "power": power,
            "damage_class": {"name": damage_class}, "accuracy": 100, "pp": 10, "priority": 0, "meta": None}


MOVES = {
    84: move_body(84, 40, "special"),      # level-up at 1
    85: move_body(85, 90, "special"),      # level-up at 36, also a TM
    87: move_body(87, 110, "special"),     # TM in Sword/Shield only
    89: move_body(89, 100),                # TM
    92: move_body(92, None, "status"),     # status-only TM the battle does not implement
    86: move_body(86, None, "status"),     # Thunder Wave, a status TM the battle implements
    281: move_body(281, None, "status"),   # Yawn, an egg move
    33: move_body(33, 40),                 # an attacking egg move
    240: move_body(240, None, "status"),   # Rain Dance, a TM
    14: move_body(14, None, "status"),     # Swords Dance, an egg move and a TM
    446: move_body(446, None, "status"),   # Stealth Rock, level-up at 10
    433: move_body(433, None, "status"),   # Trick Room, not in this learnset
}
POKEMON = {
    "species": {"url": "https://pokeapi.co/api/v2/pokemon-species/25/"},
    "types": [{"slot": 1, "type": {"name": "ground"}}],
    "stats": [{"stat": {"name": "hp"}, "base_stat": 35}],
    "name": "pikachu",
    "moves": [
    entry(84, detail(SV, "level-up", 1)),
    entry(85, detail(SV, "level-up", 36), detail(SV, "machine")),
    entry(87, detail(SWSH, "machine")),
    entry(89, detail(SV, "machine")),
    entry(92, detail(SV, "machine")),
    entry(86, detail(SV, "machine")),
    entry(240, detail(SV, "machine")),
    entry(281, detail(SV, "egg")),
    entry(33, detail(SV, "egg")),
    entry(14, detail(SV, "machine"), detail(SV, "egg")),
    entry(446, detail(SV, "level-up", 10)),
]}


@pytest.fixture
def fetched(monkeypatch):
    urls = []

    def get_json(url):
        urls.append(url)
        kind, item = url.rstrip("/").rsplit("/", 2)[-2:]
        if kind == "pokemon-species":
            return {"names": []}
        return POKEMON if kind == "pokemon" else MOVES[int(item)]

    monkeypatch.setattr(pokeapi, "_get_json", get_json)
    return urls


@pytest.fixture
def api(tmp_path, fetched):
    return PokeAPIService(Store(str(tmp_path / "bot.sqlite3")))


def tagged(moves):
    return [(move["id"], move["source"], move["level"]) for move in moves]


def test_machine_moves_of_the_chosen_group_are_choosable_at_any_level(api):
    assert tagged(api.attacking_moves(25, 5, None)) == [(84, "level", 1), (85, "machine", 0), (89, "machine", 0), (240, "machine", 0)]


def test_the_level_gate_applies_to_level_up_moves_only(api):
    at_36 = tagged(api.attacking_moves(25, 36, None))
    assert (85, "level", 36) in at_36 and (85, "machine", 0) not in at_36
    assert (89, "machine", 0) in at_36
    assert 85 not in [move["id"] for move in api.attacking_moves(25, 35, ())]


def test_status_only_machine_moves_are_filtered_but_weather_ones_stay(api):
    ids = [move["id"] for move in api.attacking_moves(25, 50, None)]
    assert 86 not in ids and 92 not in ids and 240 in ids


def test_a_machine_move_taught_only_in_another_version_group_is_not_learnable(api):
    assert 87 not in [move["id"] for move in api.attacking_moves(25, 100, None)]


def test_machine_move_data_is_fetched_only_for_the_ids_asked_for(api, fetched):
    api.attacking_moves(25, 5, ())
    assert not any(url.endswith(("/move/89/", "/move/240/")) for url in fetched)
    assert [move["id"] for move in api.attacking_moves(25, 5, [89])] == [84, 89]


def test_defaults_stay_the_latest_level_up_moves(api):
    moves = api.attacking_moves(25, 40, None)
    assert default_move_ids(moves) == [84, 85]
    assert [move.name for move in battle_moves(moves, None)] == ["move-84", "move-85"]


def test_a_chosen_machine_move_is_used_in_battle(api):
    moves = api.attacking_moves(25, 5, [89])
    assert [move.name for move in battle_moves(moves, [89])] == ["move-89"]


def test_warm_caches_the_machine_moves_a_member_chose(api, fetched):
    api.warm([{"pokemon_id": 25, "level": 5, "moves": [89]}])
    warmed = len(fetched)
    api.attacking_moves(25, 5, [89])
    assert len(fetched) == warmed


@pytest.fixture
def server(tmp_path, api):
    store = Store(str(tmp_path / "upload.sqlite3"))
    http_server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, api.attacking_moves)
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}"
    http_server.shutdown()


def call(url, token, body=None):
    request = urllib.request.Request(
        url, data=None if body is None else json.dumps(body).encode(), method="GET" if body is None else "POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def test_the_moves_endpoint_tags_every_move_with_its_source(server):
    store, base = server
    status, body = call(f"{base}/v1/moves?pokemon_id=25&level=5&machine=1", store.issue_token("U1"))
    assert status == 200
    assert [(move["id"], move["source"]) for move in body["moves"]] == [(84, "level"), (85, "machine"), (89, "machine"), (240, "machine")]
    assert body["default"] == [84]


def test_the_moves_endpoint_hides_machine_moves_from_a_client_that_did_not_ask_for_them(server):
    store, base = server
    status, body = call(f"{base}/v1/moves?pokemon_id=25&level=5", store.issue_token("U1"))
    assert status == 200
    assert [(move["id"], move["source"]) for move in body["moves"]] == [(84, "level")]


def test_an_upload_may_choose_a_machine_move_at_any_level(server):
    store, base = server
    token = store.issue_token("U1")
    party = {"party": [{"pokemon_id": 25, "level": 5, "moves": [89, 85]}]}
    assert call(f"{base}/v1/party", token, party)[0] == 200
    assert store.party("U1").party[0]["moves"] == [89, 85]


@pytest.mark.parametrize("move_id", [87, 92, 33, 999, 433])
def test_an_upload_rejects_a_move_of_another_group_a_status_move_or_an_unknown_one(server, move_id):
    store, base = server
    status, body = call(f"{base}/v1/party", store.issue_token("U1"),
                        {"party": [{"pokemon_id": 25, "level": 100, "moves": [move_id]}]})
    assert (status, body) == (400, {"ok": False, "error": f"party[0].moves: {move_id} is not an attacking move learnable at level 100"})
    assert store.party("U1") is None


def test_an_upload_rejects_a_level_up_status_move_below_its_level(server):
    store, base = server
    status, body = call(f"{base}/v1/party", store.issue_token("U1"),
                        {"party": [{"pokemon_id": 25, "level": 9, "moves": [446]}]})
    assert (status, body) == (400, {"ok": False, "error": "party[0].moves: 446 is not an attacking move learnable at level 9"})
    assert call(f"{base}/v1/party", store.issue_token("U1"),
                {"party": [{"pokemon_id": 25, "level": 10, "moves": [446]}]})[0] == 200


def test_status_moves_count_egg_moves_but_attacking_moves_do_not(api):
    moves = api.attacking_moves(25, 5, None, status=True)
    assert [(move["id"], move["source"]) for move in moves if move["damage_class"] == "status"] == [
        (240, "machine"), (14, "egg"), (86, "machine"), (281, "egg"),
    ]
    assert 33 not in [move["id"] for move in moves]
    assert 92 not in [move["id"] for move in moves]


def test_an_egg_only_status_move_is_offered_without_any_machine_ids(api):
    moves = api.attacking_moves(25, 5, (), status=True)
    assert [(move["id"], move["source"], move["level"]) for move in moves if move["id"] == 281] == [(281, "egg", 0)]


def test_a_level_up_status_move_is_offered_from_its_level(api):
    assert 446 not in [move["id"] for move in api.attacking_moves(25, 9, (), status=True)]
    assert [(move["id"], move["source"], move["level"]) for move in api.attacking_moves(25, 10, (), status=True)
            if move["id"] == 446] == [(446, "level", 10)]


def test_a_status_move_that_is_an_egg_move_and_a_tm_is_listed_as_the_free_egg_move(api):
    sources = {move["id"]: move["source"] for move in api.attacking_moves(25, 5, [14], status=True)}
    assert sources[14] == "egg"


def test_status_moves_by_machine_follow_the_machine_ids_asked_for(api):
    ids = [move["id"] for move in api.attacking_moves(25, 5, (), status=True)]
    assert 281 in ids and 86 not in ids


@pytest.mark.parametrize("query", ["pokemon_id=25&level=50&machine=1", "pokemon_id=25&level=50&machine=1&status=0"])
def test_an_old_app_without_the_status_opt_in_gets_todays_reply_byte_for_byte(server, query):
    store, base = server
    expected = {"ok": True, "moves": [
        {**pokeapi.move_from(MOVES[move_id]), "level": level, "source": source}
        for move_id, level, source in [(84, 1, "level"), (85, 36, "level"), (89, 0, "machine"), (240, 0, "machine")]
    ], "default": [84, 85]}
    request = urllib.request.Request(f"{base}/v1/moves?{query}", headers={"Authorization": f"Bearer {store.issue_token('U1')}"})
    with urllib.request.urlopen(request, timeout=5) as response:
        assert response.read() == json.dumps(expected, ensure_ascii=False).encode()


def test_the_status_opt_in_lists_the_battles_status_moves_but_never_as_a_default(server):
    store, base = server
    status, body = call(f"{base}/v1/moves?pokemon_id=25&level=50&machine=1&status=1", store.issue_token("U1"))
    assert status == 200
    assert [(move["id"], move["source"], move["damage_class"], move["power"]) for move in body["moves"]][4:] == [
        (14, "egg", "status", 0), (86, "machine", "status", 0), (281, "egg", "status", 0), (446, "level", "status", 0),
    ]
    assert body["default"] == [84, 85]


def test_an_upload_may_choose_a_status_move_the_battle_implements(server):
    store, base = server
    party = {"party": [{"pokemon_id": 25, "level": 5, "moves": [84, 281, 86]}]}
    assert call(f"{base}/v1/party", store.issue_token("U1"), party)[0] == 200


def test_every_offered_status_move_has_an_effect_line_in_the_app():
    core = Path(__file__).resolve().parents[2] / "Sources/PokeTokenBar/Core"
    bodies = [(core / "LocalizationBox.swift").read_text().split("func statusMoveEffect", 1)[1].split("default:", 1)[0],
              (core / "LocalizationStatusMoves.swift").read_text().split("func moreStatusMoveEffect", 1)[1]
              .split("default: nil", 1)[0]]
    cases = [case for body in bodies for case in re.findall(r"case ([\d, ]+):", body)]
    listed = [int(found) for case in cases for found in case.split(",")]
    assert sorted(listed) == sorted(set(listed)) and set(listed) == set(STATUS_MOVES)
