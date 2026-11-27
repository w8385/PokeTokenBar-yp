import json
import urllib.error
import urllib.request

import pytest
from fixed_clock import fixed_now

from ypoke import tower
from ypoke.store import Store
from ypoke.tower_battle import TowerBattles
from ypoke.upload_server import serve

WEAK = {"hp": 40, "attack": 40, "defense": 40, "special_attack": 40, "special_defense": 40, "speed": 40}
STRONG = {"hp": 200, "attack": 200, "defense": 200, "special_attack": 200, "special_defense": 200, "speed": 200}
TACKLE = {
    "id": 33, "name": "몸통박치기", "type": "normal", "power": 40, "damage_class": "physical", "accuracy": 100,
    "pp": 35, "crit_rate": 0, "priority": 0, "ailment": None, "ailment_chance": 0, "stat_changes": [],
    "stat_target": "target", "stat_chance": 0, "drain": 0, "min_hits": 1, "max_hits": 1, "weather": None,
    "always_hits_in": [], "level": 1,
}
ENTRY = [{"pokemon_id": 900 + index, "level": 30 + index} for index in range(3)]
RUN = 42


class FakePokeAPI:
    """Every species is weak except those in `strong`, so a test decides who wins."""

    def __init__(self):
        self.strong = {900, 901, 902}

    def pokemon(self, pokemon_id):
        return {"name_ko": f"#{pokemon_id}", "types": ["normal"],
                "base": STRONG if pokemon_id in self.strong else WEAK}

    def mega_form(self, form_id):
        return {"types": ["normal"], "base": WEAK, "ability": None, "ability_id": None}

    def attacking_moves(self, pokemon_id, level, machine_ids=(), status=False, egg=False):
        return [TACKLE]


@pytest.fixture
def pokeapi():
    return FakePokeAPI()


class Clock:
    now = 100.0

    def __call__(self):
        return self.now


@pytest.fixture
def clock():
    return Clock()


class Board:
    """The battle channel as a list; `fail` makes posting raise like a Slack outage."""

    def __init__(self):
        self.lines = []
        self.fail = False

    def __call__(self, text):
        if self.fail:
            raise RuntimeError("slack is down")
        self.lines.append(text)


@pytest.fixture
def board():
    return Board()


@pytest.fixture
def server(tmp_path, pokeapi, clock, board):
    store = Store(str(tmp_path / "bot.sqlite3"), fixed_now)
    names = {"U1": "하나", "U2": "두리", "U3": "세나"}
    http_server = serve(
        store, "127.0.0.1", 0, lambda user_id, party: None, pokeapi.attacking_moves, names.get, clock=clock,
        now=fixed_now, tower=TowerBattles(store, pokeapi, new_seed=lambda: RUN, boast=board),
    )
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}", clock
    http_server.shutdown()


def call(url, method="GET", token=None, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def fight(base, token, clock, mode="entry", team=ENTRY, **extra):
    clock.now += 10
    return call(f"{base}/v1/tower/battle", "POST", token, {"mode": mode, "team": team, **extra})


def rental(base, token, **change):
    return call(f"{base}/v1/tower/rental", "POST", token, change)


def foes(battle):
    return {member.pokemon_id for member in tower.opponent(RUN, battle).members}


def at_streak(store, user_id, mode, streak, **fields):
    state = {"streak": streak, "best": streak, "run": RUN, "team": tower.team_key(ENTRY), "trophies": [], **fields}
    store.save_tower_run(user_id, mode, state)


def test_every_tower_endpoint_needs_a_token(server):
    _, base, _ = server
    assert call(f"{base}/v1/tower/record")[0] == 401
    for path in ("battle", "rental", "quit"):
        assert call(f"{base}/v1/tower/{path}", "POST", body={"mode": "entry"})[0] == 401


def test_a_win_in_entry_mode_counts_battle_one_and_replies_like_a_gym_battle(server):
    store, base, clock = server
    status, body = fight(base, store.issue_token("U1"), clock)
    expected = tower.opponent(RUN, 1)
    assert status == 200 and body["won"] is True
    assert (body["gym_id"], body["kind"], body["run"]) == (expected.sprite, "tower", None)
    assert [m["pokemon_id"] for m in body["foe_team"]] == [m.pokemon_id for m in expected.members]
    assert [m["level"] for m in body["player_team"]] == [50, 50, 50]
    assert body["opponent"]["team"] == [m.pokemon_id for m in expected.members]
    assert body["opponent"]["trainer"] == {"name": expected.trainer.name, "line": expected.trainer.line}
    assert body["events"] and body["log"]
    assert body["tower"] == {"mode": "entry", "battle": 1, "set": 1, "streak": 1, "best": 1, "bp": 1, "trophy": None,
                             "trophies": [], "next": {"battle": 2, "set": 1, "owner": False}}


def test_an_entry_must_be_three_different_species(server):
    store, base, clock = server
    token = store.issue_token("U1")
    assert fight(base, token, clock, team=ENTRY[:2])[0] == 400
    assert fight(base, token, clock, team=[*ENTRY[:2], {"pokemon_id": 900, "level": 50}])[0] == 400
    assert fight(base, token, clock, team=None)[0] == 400


def test_the_entry_is_locked_while_a_run_is_live_and_free_again_after_a_loss(server, pokeapi):
    store, base, clock = server
    token = store.issue_token("U1")
    other = [{"pokemon_id": 903 + index, "level": 50} for index in range(3)]
    fight(base, token, clock)
    status, body = fight(base, token, clock, team=other)
    assert (status, body["error"]) == (409, "team_locked")
    assert fight(base, token, clock)[1]["tower"]["battle"] == 2
    pokeapi.strong = foes(3)
    lost = fight(base, token, clock)[1]
    assert (lost["won"], lost["tower"]["streak"], lost["tower"]["best"], lost["tower"]["bp"]) == (False, 0, 2, 0)
    assert fight(base, token, clock, team=other)[1]["tower"]["battle"] == 1


def test_the_owner_gives_silver_at_battle_20_once_and_gold_at_50(server):
    store, base, clock = server
    token = store.issue_token("U1")
    at_streak(store, "U1", "entry", 19)
    body = fight(base, token, clock)[1]
    assert (body["kind"], body["gym_id"], body["tower"]["trophy"], body["tower"]["bp"]) == (
        "tower-owner", tower.OWNER_ID, "silver", 10)
    at_streak(store, "U1", "entry", 19, trophies=["silver"])
    assert fight(base, token, clock)[1]["tower"]["trophy"] is None
    at_streak(store, "U1", "entry", 49, trophies=["silver"])
    body = fight(base, token, clock)[1]
    assert (body["tower"]["trophy"], body["tower"]["trophies"], body["tower"]["bp"]) == ("gold", ["silver", "gold"], 20)


def test_battle_21_starts_set_three_against_a_normal_trainer(server):
    store, base, clock = server
    at_streak(store, "U1", "entry", 20)
    body = fight(base, store.issue_token("U1"), clock)[1]
    assert (body["kind"], body["tower"]["set"], body["tower"]["bp"]) == ("tower", 3, 3)


def test_a_rental_run_offers_six_once_then_fights_the_three_picked(server, pokeapi):
    store, base, clock = server
    token = store.issue_token("U1")
    status, first = rental(base, token)
    assert status == 200 and len(first["offer"]) == 6 and first["team"] is None
    assert rental(base, token)[1]["offer"] == first["offer"]
    assert first["offer"] == [member.to_json() for member in tower.offer(RUN, 1)]
    assert (fight(base, token, clock, mode="rental", team=None)[1]["error"]) == "no_rental"
    picked = rental(base, token, pick=[0, 2, 5])[1]
    assert picked["team"] == [first["offer"][index] for index in (0, 2, 5)] and picked["offer"] is None
    assert rental(base, token, pick=[1, 2, 3])[1]["error"] == "no_offer"
    pokeapi.strong = {member["pokemon_id"] for member in picked["team"]}
    body = fight(base, token, clock, mode="rental", team=None)[1]
    assert body["won"] is True
    assert [m["pokemon_id"] for m in body["player_team"]] == [member["pokemon_id"] for member in picked["team"]]
    assert body["tower"]["beaten"] == [member.to_json() for member in tower.opponent(RUN, 1).members]


def test_after_a_rental_win_one_member_may_be_swapped_for_one_just_beaten(server, pokeapi):
    store, base, clock = server
    token = store.issue_token("U1")
    offer = rental(base, token)[1]["offer"]
    team = rental(base, token, pick=[0, 1, 2])[1]["team"]
    assert rental(base, token, swap={"give": 0, "take": 0})[1]["error"] == "nothing_to_swap"
    pokeapi.strong = {member["pokemon_id"] for member in offer}
    beaten = fight(base, token, clock, mode="rental", team=None)[1]["tower"]["beaten"]
    assert rental(base, token, swap={"give": 3, "take": 0})[0] == 400
    swapped = rental(base, token, swap={"give": 1, "take": 2})[1]
    assert swapped["team"] == [team[0], beaten[2], team[2]] and swapped["beaten"] is None
    assert rental(base, token, swap={"give": 0, "take": 0})[1]["error"] == "nothing_to_swap"


def test_a_swap_may_not_repeat_a_species_already_on_the_team(server, pokeapi):
    store, base, clock = server
    token = store.issue_token("U1")
    team = [tower.Member(149, (200,), "life-orb", 12).to_json(), tower.Member(248, (444,), "leftovers", 12).to_json(),
            tower.Member(376, (309,), "assault-vest", 12).to_json()]
    beaten = [tower.Member(149, (17,), "choice-band", 12).to_json()]
    at_streak(store, "U1", "rental", 1, rental=team, beaten=beaten)
    status, body = rental(base, token, swap={"give": 1, "take": 0})
    assert status == 400 and "species" in body["error"]


def test_a_rental_loss_ends_the_run_and_the_next_offer_is_a_new_one(server, pokeapi):
    store, base, clock = server
    token = store.issue_token("U1")
    rental(base, token)
    rental(base, token, pick=[0, 1, 2])
    pokeapi.strong = foes(1)
    body = fight(base, token, clock, mode="rental", team=None)[1]
    assert (body["won"], body["tower"]["team"], body["tower"]["beaten"], body["tower"]["streak"]) == (False, None, None, 0)
    assert len(rental(base, token)[1]["offer"]) == 6


def test_quitting_ends_only_that_modes_run(server):
    store, base, clock = server
    token = store.issue_token("U1")
    at_streak(store, "U1", "entry", 7)
    at_streak(store, "U1", "rental", 3, rental=[tower.Member(149, (200,), "life-orb", 12).to_json()] * 3)
    status, body = call(f"{base}/v1/tower/quit", "POST", token, {"mode": "entry"})
    assert (status, body["streak"], body["best"]) == (200, 0, 7)
    modes = call(f"{base}/v1/tower/record", token=token)[1]["modes"]
    assert (modes["entry"]["streak"], modes["rental"]["streak"]) == (0, 3)


def test_the_record_ranks_bests_per_mode_with_display_names(server):
    store, base, _ = server
    at_streak(store, "U1", "entry", 12)
    at_streak(store, "U2", "entry", 30)
    at_streak(store, "U3", "rental", 4)
    status, body = call(f"{base}/v1/tower/record", token=store.issue_token("U1"))
    assert status == 200
    assert body["ranking"] == {"entry": [{"name": "두리", "best": 30, "me": False}, {"name": "하나", "best": 12, "me": True}],
                               "rental": [{"name": "세나", "best": 4, "me": False}]}
    assert body["modes"]["entry"] == {"mode": "entry", "streak": 12, "best": 12, "trophies": [],
                                      "next": {"battle": 13, "set": 2, "owner": False}}
    assert body["modes"]["rental"]["offer"] is None


def test_a_bad_mode_or_change_is_a_400(server):
    store, base, clock = server
    token = store.issue_token("U1")
    assert fight(base, token, clock, mode="doubles")[0] == 400
    assert rental(base, token, pick=[0, 1, 2], swap={"give": 0, "take": 0})[0] == 400
    assert rental(base, token, pick="012")[0] == 400
    assert rental(base, token, swap={"give": "0", "take": 0})[0] == 400
    rental(base, token)
    assert rental(base, token, pick=[0, 0, 1])[0] == 400
    assert rental(base, token, pick=[0, 1, 6])[0] == 400


def test_tower_battles_share_the_gym_rate_limit_interval(server):
    store, base, clock = server
    token = store.issue_token("U1")
    assert fight(base, token, clock)[0] == 200
    status, body = call(f"{base}/v1/tower/battle", "POST", token, {"mode": "entry", "team": ENTRY})
    assert (status, body["error"]) == (429, "rate_limited")


def best_line(user_id, mode, streak):
    return f"🏯 <@{user_id}>님이 배틀 타워 {tower.MODE_NAMES[mode]} 모드에서 {streak}연승으로 최고 기록을 세웠어요!"


def test_a_climb_posts_nothing_until_its_run_ends_past_the_best_it_started_from(server, pokeapi, board):
    store, base, clock = server
    token = store.issue_token("U1")
    at_streak(store, "U1", "entry", 0, best=3)
    for _ in range(4):
        assert fight(base, token, clock)[1]["won"] is True
    assert board.lines == []
    pokeapi.strong = foes(5)
    assert fight(base, token, clock)[1]["won"] is False
    assert board.lines == [best_line("U1", "entry", 4)]


def test_a_run_that_ends_at_or_below_the_old_best_posts_nothing(server, pokeapi, board):
    store, base, clock = server
    token = store.issue_token("U1")
    at_streak(store, "U1", "entry", 0, best=2)
    fight(base, token, clock)
    fight(base, token, clock)
    pokeapi.strong = foes(3)
    fight(base, token, clock)
    assert board.lines == []


def test_quitting_a_run_past_the_old_best_posts_it_once(server, board):
    store, base, clock = server
    token = store.issue_token("U1")
    fight(base, token, clock)
    fight(base, token, clock)
    call(f"{base}/v1/tower/quit", "POST", token, {"mode": "entry"})
    call(f"{base}/v1/tower/quit", "POST", token, {"mode": "entry"})
    assert board.lines == [best_line("U1", "entry", 2)]


def test_a_run_from_before_boasts_existed_is_not_posted_when_it_ends(server, board):
    store, base, _ = server
    at_streak(store, "U1", "entry", 7)
    call(f"{base}/v1/tower/quit", "POST", store.issue_token("U1"), {"mode": "entry"})
    assert board.lines == []


def test_the_first_owner_win_posts_at_once_and_a_repeat_does_not(server, board):
    store, base, clock = server
    token = store.issue_token("U1")
    at_streak(store, "U1", "entry", 19)
    fight(base, token, clock)
    assert board.lines == [f"🥈 <@U1>님이 배틀 타워 내 엔트리 모드 20번째 배틀에서 {tower.OWNER[0]}에게 이겨 은 트로피를 받았어요!"]
    at_streak(store, "U1", "entry", 19, trophies=["silver"])
    fight(base, token, clock)
    assert len(board.lines) == 1


def test_boast_false_keeps_the_trophy_and_the_run_end_out_of_the_channel(server, pokeapi, board):
    store, base, clock = server
    token = store.issue_token("U1")
    at_streak(store, "U1", "entry", 19)
    assert fight(base, token, clock, boast=False)[1]["tower"]["trophy"] == "silver"
    pokeapi.strong = foes(21)
    fight(base, token, clock, boast=False)
    call(f"{base}/v1/tower/quit", "POST", token, {"mode": "entry"})
    assert board.lines == []
    assert fight(base, token, clock, boast="no")[0] == 400


def test_a_channel_that_fails_to_post_still_returns_the_saved_battle(server, board):
    store, base, clock = server
    board.fail = True
    token = store.issue_token("U1")
    at_streak(store, "U1", "entry", 19)
    status, body = fight(base, token, clock)
    assert (status, body["tower"]["trophy"]) == (200, "silver")
    assert store.tower_run("U1", "entry")["streak"] == 20
