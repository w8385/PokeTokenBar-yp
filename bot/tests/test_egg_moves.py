import hashlib
import urllib.request

import pytest

from test_machine_moves import MOVES, POKEMON, SV, call, detail, entry, tagged
from ypoke import pokeapi
from ypoke.combatants import combatant
from ypoke.moves import default_move_ids
from ypoke.pokeapi import PokeAPIService
from ypoke.store import Store
from ypoke.upload_server import serve

PICHU, PIKACHU, RAICHU = 172, 25, 26
STATS = [{"stat": {"name": name}, "base_stat": 50}
         for name in ("hp", "attack", "defense", "special-attack", "special-defense", "speed")]
LEVEL_UP = [entry(84, detail(SV, "level-up", 1)), entry(85, detail(SV, "level-up", 36), detail(SV, "machine")),
            entry(89, detail(SV, "machine"))]
BODIES = {
    PICHU: {**POKEMON, "stats": STATS, "moves": [*LEVEL_UP, entry(33, detail(SV, "egg"))]},
    PIKACHU: POKEMON,
    RAICHU: {**POKEMON, "stats": STATS, "moves": LEVEL_UP},
}


@pytest.fixture
def fetched(monkeypatch):
    urls = []

    def get_json(url):
        urls.append(url)
        kind, item = url.rstrip("/").rsplit("/", 2)[-2:]
        if kind == "pokemon-species":
            return {"names": []}
        return BODIES[int(item)] if kind == "pokemon" else MOVES[int(item)]

    monkeypatch.setattr(pokeapi, "_get_json", get_json)
    return urls


@pytest.fixture
def api(tmp_path, fetched):
    return PokeAPIService(Store(str(tmp_path / "bot.sqlite3")))


@pytest.fixture
def server(tmp_path, api):
    store = Store(str(tmp_path / "upload.sqlite3"))
    http_server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, api.attacking_moves)
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}"
    http_server.shutdown()


def test_the_egg_opt_in_lists_attacking_egg_moves_between_level_up_and_machine_moves(api):
    assert tagged(api.attacking_moves(PIKACHU, 50, None, egg=True)) == [
        (84, "level", 1), (85, "level", 36), (33, "egg", 0), (89, "machine", 0), (240, "machine", 0),
    ]


def test_attacking_egg_moves_never_come_without_the_opt_in(api):
    assert 33 not in [move["id"] for move in api.attacking_moves(PIKACHU, 50, None, status=True)]


def test_an_egg_move_is_never_a_default(api):
    with_egg = api.attacking_moves(PIKACHU, 50, None, egg=True)
    assert default_move_ids(with_egg) == default_move_ids(api.attacking_moves(PIKACHU, 50, None)) == [84, 85]


def test_an_ancestors_egg_move_is_offered_after_evolution(api):
    assert (33, "egg", 0) in tagged(api.attacking_moves(RAICHU, 50, (), egg=True))
    assert 33 not in [move["id"] for move in api.attacking_moves(RAICHU, 50, ())]


@pytest.mark.parametrize("query, digest", [
    ("pokemon_id=25&level=50&machine=1&status=1", "9d9aef0bee3d6c8d69b55d03c162374623723c7330e88fe9ac233716694c58ed"),
    ("pokemon_id=25&level=50&machine=1", "2196b9e0e22699467aa6051078e0601d7745aedcb5f0ee61b08ae106229e2ce9"),
    ("pokemon_id=25&level=50", "2c8c154b604a53f89486c5b4077d70ff146859ba2b77e544760578bf8902d5e4"),
    ("pokemon_id=25&level=50&machine=1&status=1&egg=0", "9d9aef0bee3d6c8d69b55d03c162374623723c7330e88fe9ac233716694c58ed"),
])
def test_a_reply_without_egg_1_is_byte_identical_to_the_reply_before_egg_moves(server, query, digest):
    store, base = server
    request = urllib.request.Request(f"{base}/v1/moves?{query}", headers={"Authorization": f"Bearer {store.issue_token('U1')}"})
    with urllib.request.urlopen(request, timeout=5) as response:
        assert hashlib.sha256(response.read()).hexdigest() == digest


def test_egg_1_lists_the_egg_move_but_keeps_the_default(server):
    store, base = server
    status, body = call(f"{base}/v1/moves?pokemon_id=25&level=50&machine=1&egg=1", store.issue_token("U1"))
    assert status == 200
    assert [(move["id"], move["source"], move["level"]) for move in body["moves"] if move["id"] == 33] == [(33, "egg", 0)]
    assert body["default"] == [84, 85]


def test_an_upload_may_choose_an_attacking_egg_move_only_with_the_mirror_herb(server):
    store, base = server
    token = store.issue_token("U1")
    without = {"party": [{"pokemon_id": PIKACHU, "level": 50, "moves": [84, 33]}]}
    assert call(f"{base}/v1/party", token, without) == (
        400, {"ok": False, "error": "party[0].moves: 33 is not an attacking move learnable at level 50"})
    assert store.party("U1") is None
    with_herb = {"party": [{"pokemon_id": PIKACHU, "level": 50, "moves": [84, 33], "mirror_herb": True}]}
    assert call(f"{base}/v1/party", token, with_herb)[0] == 200
    assert store.party("U1").party[0]["mirror_herb"] is True
    assert store.party("U1").party[0]["moves"] == [84, 33]


def test_a_false_mirror_herb_is_not_stored_and_a_non_boolean_is_rejected(server):
    store, base = server
    token = store.issue_token("U1")
    assert call(f"{base}/v1/party", token, {"party": [{"pokemon_id": PIKACHU, "level": 50, "mirror_herb": False}]})[0] == 200
    assert "mirror_herb" not in store.party("U1").party[0]
    status, body = call(f"{base}/v1/party", token, {"party": [{"pokemon_id": PIKACHU, "level": 50, "mirror_herb": 1}]})
    assert (status, body["error"]) == (400, "party[0].mirror_herb must be a boolean")


def test_a_chosen_egg_move_is_used_in_battle_by_a_member_with_the_mirror_herb(api):
    member = {"pokemon_id": RAICHU, "level": 50, "shiny": False, "ivs": {}, "moves": [33], "mirror_herb": True}
    assert [move.id for move in combatant(api, member).moves] == [33]
    assert [move.id for move in combatant(api, {**member, "mirror_herb": False}).moves] == [84, 85]


def test_warm_caches_the_egg_moves_a_herb_member_chose(api, fetched):
    member = {"pokemon_id": RAICHU, "level": 50, "moves": [33], "mirror_herb": True}
    api.warm([member])
    warmed = len(fetched)
    api.attacking_moves(RAICHU, 50, [33], egg=True)
    assert len(fetched) == warmed
