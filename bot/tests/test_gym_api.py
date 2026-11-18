import json
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from ypoke import gym_battle, gym_data, gyms
from ypoke.battle import Action, BattleResult, Carry, Change, ItemEffect, SendOut, StatusDamage
from ypoke.gym_battle import GymBattles
from ypoke.narration import split_side
from ypoke.store import Store
from ypoke.upload_server import GYM_BATTLE_INTERVAL, serve

STATS = {"hp": 60, "attack": 60, "defense": 60, "special_attack": 60, "special_defense": 60, "speed": 60}
STRONG = {"hp": 150, "attack": 150, "defense": 150, "special_attack": 150, "special_defense": 150, "speed": 150}
TACKLE = {
    "id": 33, "name": "몸통박치기", "type": "normal", "power": 40, "damage_class": "physical", "accuracy": 100,
    "pp": 35, "crit_rate": 0, "priority": 0, "ailment": None, "ailment_chance": 0, "stat_changes": [],
    "stat_target": "target", "stat_chance": 0, "drain": 0, "min_hits": 1, "max_hits": 1, "weather": None,
    "always_hits_in": [], "level": 1,
}
HYPER = {**TACKLE, "id": 63, "name": "파괴광선", "power": 150, "level": 20}
SWORDS_DANCE = {**TACKLE, "id": 14, "name": "칼춤", "power": 0, "damage_class": "status", "accuracy": None,
                "pp": 20, "level": 0, "source": "egg"}
FOE_IDS = {species for region in gyms.regions()[:1] for o in (*region.gyms, *region.elite, *region.hideout) for species in o.team}
FULL = {"hp": 100, "status": None}


class FakePokeAPI:
    def __init__(self):
        self.offline = False

    def pokemon(self, pokemon_id):
        if self.offline:
            raise OSError("offline")
        return {"name_ko": f"#{pokemon_id}", "types": ["normal"], "base": STATS if pokemon_id in FOE_IDS else STRONG}

    def mega_form(self, form_id):
        return {"types": ["normal"], "base": STATS, "ability": None, "ability_id": None}

    def attacking_moves(self, pokemon_id, level, machine_ids=(), status=False):
        if self.offline:
            raise OSError("offline")
        return [move for move in (TACKLE, HYPER) if move["level"] <= level] + ([SWORDS_DANCE] if status else [])


class Clock:
    now = 100.0

    def __call__(self):
        return self.now


class Spy:
    def __init__(self):
        self.calls = []

    def __call__(self, *args):
        self.calls.append(args)


@pytest.fixture
def pokeapi():
    return FakePokeAPI()


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def server(tmp_path, pokeapi, clock):
    store = Store(str(tmp_path / "bot.sqlite3"))
    uploads, notices = Spy(), Spy()
    http_server = serve(
        store, "127.0.0.1", 0, uploads, pokeapi.attacking_moves,
        notify=notices, gyms=GymBattles(pokeapi, new_seed=lambda: 42), clock=clock,
    )
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}", uploads, notices
    http_server.shutdown()


def call(url, method="GET", token=None, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.load(response), dict(response.headers)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error), dict(error.headers)


def battle(base, token, gym_id="kanto-1", team=None, carried=None):
    team = [{"pokemon_id": 900, "level": 50}] if team is None else team
    body = {"gym_id": gym_id, "team": team}
    if carried is not None:
        body["carried"] = carried
    return call(f"{base}/v1/gym/battle", "POST", token, body)


def strong_team(size):
    return [{"pokemon_id": 900 + index, "level": 50, "name": f"멤버{index}"} for index in range(size)]


def test_the_apps_kanto_catalog_fixture_matches_the_bots_catalog():
    fixture = Path(__file__).resolve().parents[2] / "Tests/PokeTokenBarTests/Fixtures/kanto-gym-catalog.json"
    kanto = [region for region in gyms.catalog()["regions"] if region["id"] == "kanto"]

    assert json.loads(fixture.read_text()) == {"ok": True, "regions": kanto}


def test_the_catalog_needs_a_token_and_lists_every_region(server):
    store, base, _, _ = server
    assert call(f"{base}/v1/gyms")[0] == 401
    status, body, _ = call(f"{base}/v1/gyms", token=store.issue_token("U1"))
    assert status == 200 and body["ok"] is True
    assert [region["id"] for region in body["regions"]] == list(gyms.DEX_REGIONS)
    kanto = body["regions"][0]
    assert [len(kanto["gyms"]), len(kanto["elite"]["battles"]), len(kanto["hideout"]["battles"])] == [8, 5, 4]
    assert kanto["gyms"][0]["team"] == list(gyms.find("kanto-1").team)


def test_a_strong_team_beats_a_gym_and_the_reply_has_both_rosters_and_a_full_log(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"))
    assert status == 200 and body["ok"] is True
    assert (body["gym_id"], body["kind"], body["won"], body["seed"]) == ("kanto-1", "gym", True, 42)
    assert body["trainer"] == {"name": gyms.find("kanto-1").trainer.name, "line": gyms.find("kanto-1").trainer.line}
    assert [member["pokemon_id"] for member in body["foe_team"]] == list(gyms.find("kanto-1").team)
    assert body["player_team"][0] == {
        "pokemon_id": 900, "name": "#900", "level": 50, "types": ["normal"], "shiny": False, "hp": body["player_team"][0]["hp"],
    }
    assert 0 < body["player_team"][0]["hp"] <= 100
    assert all(member["hp"] == 0 for member in body["foe_team"])
    assert (body["run"], body["carry"]) == (None, None)
    assert [turn["turn"] for turn in body["log"]] == list(range(1, body["turns"] + 1))
    lines = [line for turn in body["log"] for line in turn["lines"]]
    assert {line["side"] for line in lines} >= {0, 1}
    assert all(set(line) == {"side", "text"} and line["text"] for line in lines)
    assert not any(line["text"].startswith(("🔵", "🔴")) for line in lines)


def test_a_weak_team_loses_with_its_fainted_members_at_zero_and_the_unfought_foes_at_null(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-8", [{"pokemon_id": 1, "level": 5}])
    assert status == 200 and body["won"] is False
    assert body["player_team"][0]["hp"] == 0
    assert body["foe_team"][0]["hp"] > 0
    assert [member["hp"] for member in body["foe_team"][1:]] == [None] * 5


def test_a_six_member_team_fights_in_order_and_unsent_members_read_null(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-2", strong_team(6))
    assert status == 200
    assert [member["name"] for member in body["player_team"]] == [f"멤버{index}" for index in range(6)]
    assert body["player_team"][0]["hp"] is not None
    assert body["player_team"][-1]["hp"] is None


def test_a_trainers_foes_are_the_same_on_every_battle(server, clock):
    store, base, _, _ = server
    token = store.issue_token("U1")
    first = battle(base, token, "kanto-3")[1]
    clock.now += GYM_BATTLE_INTERVAL
    second = battle(base, token, "kanto-3")[1]
    assert [member["pokemon_id"] for member in first["foe_team"]] == list(gyms.find("kanto-3").team)
    assert [member["pokemon_id"] for member in second["foe_team"]] == [member["pokemon_id"] for member in first["foe_team"]]


def test_a_rental_fights_at_the_trainers_level(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-3", [{"pokemon_id": 900, "level": 5, "rental": True}])
    assert status == 200 and body["player_team"][0]["level"] == 50


def test_a_battle_stores_nothing_posts_nothing_and_keeps_the_uploaded_party(server):
    store, base, uploads, notices = server
    token = store.issue_token("U1")
    party = [{"pokemon_id": 25, "level": 42, "shiny": False, "ivs": {}}]
    store.save_party("U1", party, None)
    stored = store.party("U1")
    assert battle(base, token, "kanto-1", [{"pokemon_id": 900, "level": 50}] * 6)[0] == 200
    assert store.party("U1") == stored
    assert store.recent_battles("U1", 10) == []
    assert store.record("U1").wins == 0 and store.record("U1").losses == 0
    assert uploads.calls == [] and notices.calls == []


@pytest.mark.parametrize("team,message", [
    ("nope", "team must be a list of 1 to 6 entries"),
    ([], "team must be a list of 1 to 6 entries"),
    ([{"pokemon_id": 900, "level": 50}] * 7, "team must be a list of 1 to 6 entries"),
    ([{"pokemon_id": 0, "level": 50}], "team[0].pokemon_id must be 1..1025 or 10001..10999"),
    ([{"pokemon_id": 900, "level": 50}, {"pokemon_id": 25, "level": 101}], "team[1].level must be 1..100"),
    ([{"pokemon_id": 25, "level": 50, "moves": [1, 1]}], "team[0].moves must be a list of up to 4 distinct move ids"),
    ([{"pokemon_id": 25, "level": 50, "moves": [9999]}], "team[0].moves: 9999 is not an attacking move learnable at level 50"),
])
def test_a_bad_team_is_a_400_naming_the_team_field(server, team, message):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), team=team)
    assert (status, body) == (400, {"ok": False, "error": message})


def test_chosen_moves_are_checked_and_used(server):
    store, base, _, _ = server
    token = store.issue_token("U1")
    status, body, _ = battle(base, token, team=[{"pokemon_id": 900, "level": 50, "moves": [63]}])
    assert status == 200
    assert any("파괴광선" in line["text"] for turn in body["log"] for line in turn["lines"])


def test_a_players_chosen_swords_dance_is_used_by_the_foe_ais_rule_and_raises_attack(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), gym_id="kanto-8",
                             team=[{"pokemon_id": 900, "level": 50, "moves": [33, 14]}])
    assert status == 200
    player_moves = [event["move"] for event in body["events"] if event["type"] == "move" and event["side"] == 0]
    assert player_moves[0] == "칼춤" and player_moves[1:3] == ["몸통박치기", "몸통박치기"]
    assert any("⚔️공격이 크게 올랐다" in line["text"] for turn in body["log"] for line in turn["lines"])


@pytest.mark.parametrize("body", [{"team": [{"pokemon_id": 900, "level": 50}]}, {"gym_id": 3, "team": []}, [], None])
def test_a_missing_or_malformed_gym_id_is_a_400(server, body):
    store, base, _, _ = server
    status, reply, _ = call(f"{base}/v1/gym/battle", "POST", store.issue_token("U1"), body)
    assert status == 400 and reply["ok"] is False


def test_an_unknown_battle_is_404_and_an_unauthorized_caller_401(server):
    store, base, _, _ = server
    assert battle(base, store.issue_token("U1"), "kanto-9")[:2] == (404, {"ok": False, "error": "unknown_gym"})
    assert battle(base, None)[0] == 401
    assert battle(base, "wrong")[0] == 401


def test_pokeapi_down_is_a_503(server, pokeapi):
    store, base, _, _ = server
    pokeapi.offline = True
    assert battle(base, store.issue_token("U1"))[:2] == (503, {"ok": False, "error": "pokeapi_unavailable"})


def test_a_user_gets_one_battle_every_three_seconds_and_others_are_not_held_up(server, clock):
    store, base, _, _ = server
    token, other = store.issue_token("U1"), store.issue_token("U2")
    assert battle(base, token)[0] == 200
    clock.now += GYM_BATTLE_INTERVAL - 1
    status, body, headers = battle(base, token)
    assert status == 429
    assert body == {"ok": False, "error": "rate_limited", "retry_after": 1.0}
    assert headers["Retry-After"] == "1"
    assert battle(base, other)[0] == 200
    clock.now += 1
    assert battle(base, token)[0] == 200


def test_a_bot_without_gyms_does_not_serve_the_endpoints(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    http_server = serve(store, "127.0.0.1", 0, Spy(), lambda pokemon_id, level: [])
    try:
        base = f"http://127.0.0.1:{http_server.server_address[1]}"
        token = store.issue_token("U1")
        assert call(f"{base}/v1/gyms", token=token)[:2] == (404, {"ok": False, "error": "not_found"})
        assert battle(base, token)[:2] == (404, {"ok": False, "error": "not_found"})
    finally:
        http_server.shutdown()


def test_a_won_run_battle_points_to_the_next_one_and_carries_every_members_state(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-elite-1", strong_team(3))
    assert status == 200 and body["won"] is True and body["kind"] == "elite"
    assert body["run"] == {"id": "kanto-elite", "step": 1, "steps": 5, "first": "kanto-elite-1", "next": "kanto-elite-2"}
    assert [entry["hp"] for entry in body["carry"]] == [
        member["hp"] if member["hp"] is not None else 100 for member in body["player_team"]
    ]
    assert all(set(entry) == {"hp", "status"} for entry in body["carry"])


def test_the_last_battle_of_a_run_and_a_lost_one_carry_nothing(server, clock):
    store, base, _, _ = server
    token = store.issue_token("U1")
    status, body, _ = battle(base, token, "kanto-champion", strong_team(2))
    assert status == 200 and body["won"] is True and body["kind"] == "champion"
    assert body["run"] == {"id": "kanto-elite", "step": 5, "steps": 5, "first": "kanto-elite-1", "next": None}
    assert body["carry"] is None
    clock.now += GYM_BATTLE_INTERVAL
    _, lost, _ = battle(base, token, "kanto-hideout-2", [{"pokemon_id": 1, "level": 5}])
    assert lost["won"] is False
    assert lost["run"] == {"id": "kanto-hideout", "step": 2, "steps": 4, "first": "kanto-hideout-1", "next": None}
    assert lost["carry"] is None


def test_a_champions_finale_comes_out_only_after_the_first_six_faint_and_the_log_marks_it(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-champion", strong_team(6))
    assert status == 200 and body["won"] is True and len(body["foe_team"]) == 7
    events = body["events"]
    finale = next(index for index, event in enumerate(events) if event["type"] == "finale")
    assert events[finale]["text"] == gym_data.FINALE_LINE and events[finale]["member"] == 6
    assert {e["member"] for e in events[:finale] if e["side"] == 1 and e["type"] == "faint"} == set(range(6))
    assert all(e["member"] != 6 for e in events[:finale] if e["side"] == 1)
    assert (events[finale + 1]["type"], events[finale + 1]["side"], events[finale + 1]["member"]) == ("switch", 1, 6)
    assert events[-1] == {"turn": events[-1]["turn"], "type": "faint", "side": 1, "member": 6}
    lines = [line["text"] for turn in body["log"] for line in turn["lines"]]
    assert lines.count(gym_data.FINALE_LINE["ko"]) == 1


def test_the_hidden_boss_is_one_full_hp_battle_whose_every_stone_holder_mega_evolves(server):
    store, base, _, _ = server
    token = store.issue_token("U1")
    status, body, _ = battle(base, token, "kanto-hidden", strong_team(6))
    assert status == 200 and body["kind"] == "hidden" and body["run"] is None and body["carry"] is None
    assert len(body["foe_team"]) == len(gym_data.HIDDEN_TEAMS["kanto"])
    lines = [line["text"] for turn in body["log"] for line in turn["lines"]]
    assert sum("메가진화" in line for line in lines) == 3
    status, reply, _ = battle(base, store.issue_token("U2"), "kanto-hidden", strong_team(6), [None] * 6)
    assert status == 400 and reply["error"] == "carried is only for Elite Four and hideout battles"


def test_a_member_that_was_down_stays_down_and_one_that_is_not_sent_out_keeps_its_state(server):
    store, base, _, _ = server
    carried = [{"hp": 0, "status": None}, None, {"hp": 40, "status": "burn"}]
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-hideout-1", strong_team(3), carried)
    assert status == 200 and body["won"] is True
    assert [member["hp"] for member in body["player_team"]][0] == 0
    assert body["player_team"][1]["hp"] is not None and body["player_team"][2]["hp"] is None
    assert body["carry"][0] == {"hp": 0, "status": None}
    assert body["carry"][2] == {"hp": 40, "status": "burn"}
    assert 0 < body["carry"][1]["hp"] <= 100


def test_a_hurt_member_goes_in_hurt_and_its_loss_ends_the_run_battle(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-hideout-3", [{"pokemon_id": 1, "level": 5}],
                             [{"hp": 5, "status": "poison"}])
    assert status == 200 and body["won"] is False and body["player_team"][0]["hp"] == 0


@pytest.mark.parametrize("carried,message", [
    ("nope", "carried must be a list with one entry per team member (2)"),
    ([None], "carried must be a list with one entry per team member (2)"),
    ([None, {"hp": 101, "status": None}], "carried[1].hp must be 0..100"),
    ([None, {"hp": "9"}], "carried[1].hp must be 0..100"),
    ([None, {"hp": True}], "carried[1].hp must be 0..100"),
    ([{"hp": 5, "status": "dizzy"}, None], "carried[0].status must be null or one of burn, poison, toxic, paralysis, sleep, freeze"),
    ([{"hp": 0}, {"hp": 0, "status": None}], "carried: no member can still fight"),
])
def test_a_bad_carried_state_is_a_400(server, carried, message):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-elite-2", strong_team(2), carried)
    assert (status, body) == (400, {"ok": False, "error": message})


def test_carried_state_is_refused_for_a_gym(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-1", strong_team(1), [FULL])
    assert (status, body) == (400, {"ok": False, "error": "carried is only for Elite Four and hideout battles"})


def test_a_hideout_battle_uses_the_hideout_trainers_team(server):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-hideout-4", strong_team(1))
    assert status == 200 and body["kind"] == "boss"
    assert [member["pokemon_id"] for member in body["foe_team"]] == list(gyms.find("kanto-hideout-4").team)


def test_split_side_reads_the_marker_and_keeps_the_send_out_arrow():
    assert split_side("🔵 피카츄 › 번개 → 꼬부기 12%") == (0, "피카츄 › 번개 → 꼬부기 12%")
    assert split_side("↪ 🔴 꼬부기 등장") == (1, "↪ 꼬부기 등장")
    assert split_side("💥 꼬부기 쓰러짐") == (None, "💥 꼬부기 쓰러짐")
    assert split_side("☀️끝") == (None, "☀️끝")


@pytest.mark.parametrize("gym_id,team", [
    ("kanto-1", None), ("kanto-2", strong_team(6)), ("kanto-8", [{"pokemon_id": 1, "level": 5}] * 2),
])
def test_the_events_replay_to_the_hp_each_roster_ends_with(server, gym_id, team):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), gym_id, team)
    assert status == 200
    assert any(event["type"] == "move" and event["move"] for event in body["events"])
    assert_replay_matches_the_rosters(body)


@pytest.mark.parametrize("gym_id,team", [
    ("kanto-1", None), ("kanto-8", [{"pokemon_id": 900, "level": 50, "moves": [33, 14]}]),
    ("kanto-champion", strong_team(6)),
])
def test_every_move_event_carries_the_pokeapi_id_of_its_move_on_both_sides(server, gym_id, team):
    store, base, _, _ = server
    status, body, _ = battle(base, store.issue_token("U1"), gym_id, team)
    assert status == 200
    moves = [event for event in body["events"] if event["type"] == "move"]
    ids = {move["name"]: move["id"] for move in (TACKLE, HYPER, SWORDS_DANCE)}
    assert {event["side"] for event in moves} == {0, 1}
    assert all(set(event) == {"turn", "type", "side", "member", "move", "move_id"} for event in moves)
    assert all(event["move_id"] == ids[event["move"]] for event in moves), moves


def test_a_member_that_came_in_down_never_appears_and_a_hurt_one_switches_in_hurt(server):
    store, base, _, _ = server
    carried = [{"hp": 0, "status": None}, {"hp": 40, "status": "burn"}, None]
    status, body, _ = battle(base, store.issue_token("U1"), "kanto-hideout-1", strong_team(3), carried)
    assert status == 200
    first = body["events"][0]
    assert (first["member"], first["hp"], first["status"]) == (1, 40, "burn")
    assert all(event["member"] != 0 for event in body["events"] if event["side"] == 0)
    body["player_team"][0]["hp"] = None
    assert_replay_matches_the_rosters(body)


def test_the_events_follow_statuses_recoil_and_who_is_out():
    result = BattleResult(winner=0, turns=2, events=[
        Action(1, 0, "A", "B", "불꽃", recovered=("sleep",), defender_hp=70, attacker_hp=50, move_id=52,
               changes=(Change(1, "B", "burn"), Change(1, "B", "attack", -1))),
        StatusDamage(1, 1, "B", 64, False, "burn"),
        ItemEffect(1, 1, "B", "lum-berry", "cure"),
        Action(2, 1, "B", "A", "", blocked="paralysis", defender_hp=50, attacker_hp=64),
        Action(2, 0, "A", "B", "불꽃", defender_hp=0, knockout=True, attacker_hp=38, recoil=True, move_id=52),
        SendOut(2, 1, "C"),
    ])
    events = gym_battle._events(result, ([2], [0, 1]), [Carry(50, "sleep")])
    assert [tuple(event.values()) for event in events] == [
        (0, "switch", 0, 2, 50, "sleep"),
        (0, "switch", 1, 0, 100, None),
        (1, "move", 0, 2, "불꽃", 52),
        (1, "status", 0, 2, None),
        (1, "damage", 1, 0, 70),
        (1, "status", 1, 0, "burn"),
        (1, "damage", 1, 0, 64),
        (1, "status", 1, 0, None),
        (2, "move", 0, 2, "불꽃", 52),
        (2, "damage", 1, 0, 0),
        (2, "faint", 1, 0),
        (2, "damage", 0, 2, 38),
        (2, "switch", 1, 1, 100, None),
    ]


def assert_replay_matches_the_rosters(body):
    events = body["events"]
    assert [(event["turn"], event["type"], event["side"]) for event in events[:2]] == [(0, "switch", 0), (0, "switch", 1)]
    assert [event["turn"] for event in events] == sorted(event["turn"] for event in events)
    assert events[-1]["turn"] <= body["turns"]
    assert {event["type"] for event in events} <= {"switch", "move", "damage", "faint", "status"}
    left = replayed(body)
    for side, roster in ((0, body["player_team"]), (1, body["foe_team"])):
        for member, fighter in enumerate(roster):
            assert left.get((side, member)) == fighter["hp"], (side, member)
    faints = [(event["side"], event["member"]) for event in events if event["type"] == "faint"]
    assert faints == [(event["side"], event["member"]) for event in events if event["type"] == "damage" and event["hp"] == 0]


def replayed(body):
    """Each member's HP share after the last event that names it; members no event names are absent."""
    left = {}
    for event in body["events"]:
        if event["type"] in ("switch", "damage"):
            left[(event["side"], event["member"])] = event["hp"]
    return left
