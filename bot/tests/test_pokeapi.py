import pytest

from ypoke import pokeapi
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


@pytest.fixture
def service(tmp_path, monkeypatch):
    fetched = []

    def get_json(url):
        fetched.append(url)
        kind, item = url.rstrip("/").rsplit("/", 2)[-2:]
        return PIKACHU if kind == "pokemon" else MOVES[int(item)]

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


@pytest.mark.parametrize("timeouts, succeeds", [(2, True), (3, False)])
def test_read_timeouts_are_retried_up_to_three_attempts(monkeypatch, timeouts, succeeds):
    calls = []

    def read(request):
        calls.append(request)
        if len(calls) <= timeouts:
            raise TimeoutError
        return {"ok": True}

    monkeypatch.setattr(pokeapi, "_read", read)
    if succeeds:
        assert pokeapi._get_json("https://pokeapi.co/api/v2/move/85/") == {"ok": True}
    else:
        with pytest.raises(TimeoutError):
            pokeapi._get_json("https://pokeapi.co/api/v2/move/85/")
    assert len(calls) == min(timeouts + 1, 3)


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
