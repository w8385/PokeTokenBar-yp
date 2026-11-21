import json
from types import SimpleNamespace

import pytest

from test_miracle import FakeBoard
from test_trades import ALICE, BOB, HAUNTER, NAMES, individual
from test_upload_server import PIKACHU as BATTLER
from test_upload_server import FakeMoves, call
from fixed_clock import fixed_now
from ypoke.miracle import PICK_ACTION_ID as MIRACLE_PICK_ACTION_ID
from ypoke.miracle import POST_ERRORS, MiracleService
from ypoke.store import Store
from ypoke.trades import PICK_ACTION_ID, PROPOSE_ERRORS, TradeService
from ypoke.transport import options_listener
from ypoke.upload_server import serve


def app_entry(index):
    """A pool entry the size the app sends: a full individual record, about 700 bytes."""
    entry = individual(f"box-{index:04d}-0000-0000-0000-000000000000", 133, "이브이", level=1 + index % 100)
    entry["entry"].update({
        "chainOrder": [133], "rarity": "rare", "isShiny": False, "nature": "jolly",
        "profile": {"instanceID": "", "seed": 301642480466534822 + index, "gender": "male",
                    "ivs": {"hp": 31, "attack": 30, "defense": 29, "specialAttack": 28, "specialDefense": 27, "speed": 26},
                    "abilitySlot": 2, "abilityName": "adaptability", "abilityIsHidden": False, "level": 1 + index % 100,
                    "growthTokens": 150000000,
                    "moves": [{"name": name, "learnedAtLevel": 40 + slot}
                              for slot, name in enumerate(["quick-attack", "bite", "double-edge", "last-resort"])]},
    })
    return entry


@pytest.fixture
def api(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"), fixed_now)
    trades = TradeService(store, fixed_now, name_for=NAMES.get)
    miracle = MiracleService(trades, FakeBoard(), fixed_now)
    server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), NAMES.get, trades, miracle=miracle, now=fixed_now)
    yield SimpleNamespace(base=f"http://127.0.0.1:{server.server_address[1]}", trades=trades, miracle=miracle,
                          alice=store.issue_token(ALICE), bob=store.issue_token(BOB))
    server.shutdown()


def upload(api, token, pool):
    body = json.dumps({"party": [BATTLER], "trade_pool": pool}).encode()
    return call(f"{api.base}/v1/party", "POST", token, body), len(body)


def test_the_oldest_of_a_300_pokemon_box_goes_up_for_miracle_trade(api):
    pool = [app_entry(index) for index in range(300)]

    (status, _), size = upload(api, api.alice, pool)
    stored = len(api.trades.free_entries(ALICE))
    result = api.miracle.post(ALICE, pool[-1]["id"])

    assert size > 64 * 1024
    assert status == 200
    assert stored == 300
    assert result.error is None and result.offer["give_id"] == pool[-1]["id"]


def test_the_oldest_of_a_300_pokemon_box_can_be_offered_in_a_trade(api):
    pool = [app_entry(index) for index in range(300)]
    upload(api, api.alice, pool)
    upload(api, api.bob, [individual("bob-pikachu", 25, "피카츄", 80)])

    assert api.trades.propose(ALICE, BOB, pool[-1]["id"]).error is None


def test_a_pokemon_missing_from_the_upload_blames_the_sync_not_raising_or_battle():
    for text in (PROPOSE_ERRORS["unknown_individual"], POST_ERRORS["unknown_individual"]):
        assert "동기화" in text
        assert "키우는" not in text and "대결" not in text


def select_of(blocks):
    (block,) = [block for block in blocks if block["type"] == "actions" and block["elements"][0]["action_id"]
                in (PICK_ACTION_ID, MIRACLE_PICK_ACTION_ID)]
    return block["block_id"], block["elements"][0]


def suggest(api, action_id, user_id, block_id, query):
    answers = []
    payload = {"type": "block_suggestion", "action_id": action_id, "block_id": block_id, "value": query,
               "user": {"id": user_id}}
    options_listener(api.trades)(lambda **answer: answers.append(answer), payload, payload)
    return answers[0]["options"]


def named_pool(count):
    return [individual(f"bob-{index:03d}", 25, f"피카{index:03d}", level=50) for index in range(count)]


def test_a_miracle_picker_past_100_finds_and_picks_the_130th_pokemon(api):
    api.trades.save_pool(ALICE, [HAUNTER])
    pool = named_pool(150)
    api.trades.save_pool(BOB, pool)
    api.miracle.post(ALICE, HAUNTER["id"])
    offer = api.miracle.status(ALICE)["offer_id"]

    block_id, select = select_of(api.miracle.open_picker(BOB, offer).blocks)
    first = suggest(api, MIRACLE_PICK_ACTION_ID, BOB, block_id, "")
    found = suggest(api, MIRACLE_PICK_ACTION_ID, BOB, block_id, "피카129")
    done = api.miracle.pick(BOB, *found[0]["value"].split("|"))

    assert select["type"] == "external_select" and "options" not in select
    assert len(first) == 30
    assert [option["text"]["text"] for option in found] == ["피카129 Lv.50"]
    assert found[0]["value"] == f"{offer}|bob-129"
    assert done.ok and done.final


def test_a_trade_picker_past_100_finds_the_130th_pokemon(api):
    api.trades.save_pool(ALICE, [HAUNTER])
    api.trades.save_pool(BOB, named_pool(150))
    (message,) = api.trades.propose(ALICE, BOB, HAUNTER["id"]).direct_messages

    block_id, select = select_of(message.blocks)
    found = suggest(api, PICK_ACTION_ID, BOB, block_id, "피카129")
    reply = api.trades.pick(BOB, *found[0]["value"].split("|"))

    assert select["type"] == "external_select"
    assert [option["value"] for option in found] == [f"{block_id}|bob-129"]
    assert reply.ok


def test_typed_options_keep_the_numbers_of_look_alike_labels(api):
    api.trades.save_pool(ALICE, [HAUNTER])
    api.trades.save_pool(BOB, [individual(f"bob-{index:03d}", 25, "피카츄", level=50) for index in range(120)])

    labels = [option["text"]["text"] for option in suggest(api, PICK_ACTION_ID, BOB, "t", "#7")]

    assert labels[:2] == ["피카츄 Lv.50 #7", "피카츄 Lv.50 #70"]


def test_typed_options_list_only_the_presser_s_own_pokemon(api):
    api.trades.save_pool(ALICE, [HAUNTER])
    api.trades.save_pool(BOB, named_pool(150))

    assert [option["value"] for option in suggest(api, PICK_ACTION_ID, ALICE, "t", "")] == ["t|alice-haunter"]


def test_a_picker_of_100_or_fewer_stays_a_static_select(api):
    api.trades.save_pool(ALICE, [HAUNTER])
    api.trades.save_pool(BOB, named_pool(100))
    (message,) = api.trades.propose(ALICE, BOB, HAUNTER["id"]).direct_messages

    _, select = select_of(message.blocks)

    assert select["type"] == "static_select" and len(select["options"]) == 100


def test_coworkers_skip_an_empty_pool(api):
    api.trades.save_pool(ALICE, [HAUNTER])
    api.trades.save_pool(BOB, [])

    assert api.trades.coworkers(BOB) == [{"id": api.trades.coworkers(BOB)[0]["id"], "name": "앨리스"}]
    assert api.trades.coworkers(ALICE) == []
