import pytest
from test_commands import MOVES, NOW, FakePokeAPI, lineups, member
from test_upload_server import FakeMoves, call

from ypoke.commands import CommandHandler
from ypoke.lineup_editor import (
    ADD_SLOT,
    BACK_ACTION,
    BOX_ADD_ACTION,
    DEFAULT_MOVES_ACTION,
    ITEM_ACTION,
    MOVES_ACTION,
    ORDER_ACTION,
    SET_MOVES_ACTION,
    SWAP_ACTION,
    STALE,
)
from ypoke.remote_lineup import LINEUP, REASONS
from ypoke.remote_ops import OLD_APP_REFUSAL, RemoteOps
from ypoke.remote_views import BOX_COMMAND, PARTY_COMMAND
from ypoke.store import Store
from ypoke.trades import TradeService
from ypoke.transport import editor_listener, editor_options_listener
from ypoke.upload_server import battle_overview, serve

LEFTOVERS = {"item_key": "leftovers", "item_name": "먹다남은음식", "held_item": "leftovers"}
SCARF = {"key": "choiceScarf", "name": "구애스카프", "count": 1, "equip": True, "held_item": "choice-scarf"}
EARTHQUAKE_TM = {"key": "tm:89", "name": "기술머신 지진", "count": 1}
BAG = [SCARF, EARTHQUAKE_TM, {"key": "rareCandy", "name": "이상한사탕", "count": 3}]
EARTHQUAKE = {"id": 89, "name": "지진", "type": "ground", "power": 100, "damage_class": "physical", "accuracy": 100,
              "pp": 10, "crit_rate": 0, "priority": 0, "ailment": None, "ailment_chance": 0, "stat_changes": [],
              "stat_target": "target", "stat_chance": 0, "drain": 0, "min_hits": 1, "max_hits": 1, "weather": None,
              "always_hits_in": [], "level": 0}


class LineupAPI(FakePokeAPI):
    """Level-up moves, plus Earthquake by machine when its TM is owned."""

    def attacking_moves(self, pokemon_id, level, machine_ids=(), status=False, egg=False):
        moves = [{**move, "source": "level"} for move in super().attacking_moves(pokemon_id, level, machine_ids)]
        if machine_ids is None or 89 in machine_ids:
            moves.append({**EARTHQUAKE, "source": "machine"})
        return moves


def party_member(individual_id, pokemon_id, level, **extra):
    return {**member(pokemon_id, level), "id": individual_id, **extra}


def box_entry(individual_id, pokemon_id, name, level=30, **extra):
    return {"id": individual_id, "pokemon_id": pokemon_id, "level": level, "shiny": False, "name": name,
            "entry": {"nature": "bold"}, "member": member(pokemon_id, level) | extra}


PARTY = [party_member("p1", 25, 42, **LEFTOVERS), party_member("p2", 7, 20)]
POOL = [
    box_entry("b1", 54, "고라파덕"),
    box_entry("b2", 25, "피카츄"),
    box_entry("b3", 60, "발챙이", **LEFTOVERS),
    box_entry("b4", 118, "콘치"),
]


@pytest.fixture
def server(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    http_server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), trades=TradeService(store))
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}"
    http_server.shutdown()


def post(server, user_id="UA", **fields):
    store, base = server
    token = store.issue_token(user_id, keep_existing=True)
    status, body = call(f"{base}/v1/party", "POST", token, payload(**fields))
    assert status == 200, body
    return body


def payload(party=PARTY, pool=POOL, bag=BAG, applied=0, kinds=(LINEUP,), **extra):
    return {"party": party, "trade_pool": pool, "remote_ops": 1, "applied_op_id": applied, "wallet": 500, "bag": bag,
            "remote_ops_kinds": list(kinds), **extra}


def bot(store):
    return CommandHandler(store, LineupAPI(), now=lambda: NOW, bot_user_id="UBOT")


def party_ids(store, user_id="UA"):
    return [member["id"] for member in RemoteOps(store).party(user_id).party]


def select_values(blocks, block_id, action_id):
    block = next(block for block in blocks if block.get("block_id") == block_id)
    element = next(element for element in block["elements"] if element["action_id"] == action_id)
    return [option["value"] for option in element["options"]]


# The /파티 screen


def test_party_screen_offers_only_box_pokemon_that_keep_the_clauses(server):
    store, _ = server
    post(server)
    blocks = bot(store).editor.handle("UA", PARTY_COMMAND, "").blocks
    assert select_values(blocks, "p1", SWAP_ACTION) == ["p1|b1", "p1|b2", "p1|b3", "p1|b4"]
    assert select_values(blocks, "p2", SWAP_ACTION) == ["p2|b1", "p2|b4"]
    assert select_values(blocks, ADD_SLOT, SWAP_ACTION) == ["+|b1", "+|b4"]
    assert select_values(blocks, "p2", ITEM_ACTION) == ["p2|", "p2|choiceScarf"]
    assert select_values(blocks, "p1", ITEM_ACTION) == ["p1|", "p1|leftovers", "p1|choiceScarf"]
    assert select_values(blocks, "p1", ORDER_ACTION) == ["down|p1", "drop|p1"]
    assert "한 종에 한 마리" in str(blocks)


def test_an_app_that_does_not_apply_lineup_ops_gets_the_read_only_screen_and_a_refusal(server):
    store, _ = server
    post(server, kinds=())
    editor = bot(store).editor
    assert not [block for block in editor.handle("UA", PARTY_COMMAND, "").blocks if block["type"] == "actions"]
    reply = editor.act("UA", SWAP_ACTION, "p1|b1", [])
    assert (reply.replace, reply.screen.text) == (False, OLD_APP_REFUSAL)
    assert RemoteOps(store).pending("UA") == []


# Building a lineup from the party and the Box


def test_a_swap_queues_one_lineup_op_and_every_party_reader_uses_it_at_once(server):
    store, base = server
    post(server)
    post(server, "UB", party=[party_member("q1", 7, 20)], pool=[])
    reply = bot(store).editor.act("UA", SWAP_ACTION, "p1|b1", [])
    assert reply.replace
    assert [op.kind for op in RemoteOps(store).pending("UA")] == [LINEUP]
    assert party_ids(store) == ["b1", "p2"]
    assert "고라파덕" in reply.screen.blocks[1]["text"]["text"]
    assert lineups(bot(store).handle("UB", "<@UA|a> 2"))[1][0].startswith("고라파덕")
    assert "고라파덕" in bot(store).editor.handle("UA", PARTY_COMMAND, "").blocks[1]["text"]["text"]
    assert [lead["pokemon_id"] for lead in battle_overview(store, "UB", lambda _: None, RemoteOps(store))["coworkers"]] == [54]
    status, body = call(f"{base}/v1/party", "GET", store.issue_token("UA", keep_existing=True))
    assert status == 200 and [member["pokemon_id"] for member in body["party"]] == [54, 7]


def test_the_upload_reply_lists_coworkers_with_their_slack_lineup(server):
    store, _ = server
    post(server)
    bot(store).editor.act("UA", SWAP_ACTION, "p1|b1", [])
    assert [lead["pokemon_id"] for lead in post(server, "UB", party=[party_member("q1", 7, 20)], pool=[])["coworkers"]] == [54]


def test_add_reorder_and_drop_build_the_whole_target_lineup(server):
    store, _ = server
    post(server)
    editor = bot(store).editor
    editor.act("UA", SWAP_ACTION, "+|b1", [])
    editor.act("UA", ORDER_ACTION, "up|b1", [])
    assert party_ids(store) == ["p1", "b1", "p2"]
    editor.act("UA", ORDER_ACTION, "drop|p1", [])
    assert party_ids(store) == ["b1", "p2"]
    assert [op.payload["members"][0]["id"] for op in RemoteOps(store).pending("UA")] == ["b1"]


def test_a_dropped_member_can_come_back_from_the_bench(server):
    store, _ = server
    post(server)
    editor = bot(store).editor
    editor.act("UA", ORDER_ACTION, "drop|p2", [])
    editor.act("UA", SWAP_ACTION, "+|p2", [])
    assert party_ids(store) == ["p1", "p2"]


@pytest.mark.parametrize("value,reason", [("p2|b2", "species_clause"), ("p2|b3", "item_clause")])
def test_a_swap_that_breaks_a_clause_is_refused_and_queues_nothing(server, value, reason):
    store, _ = server
    post(server)
    reply = bot(store).editor.act("UA", SWAP_ACTION, value, [])
    assert not reply.replace and REASONS[reason] in reply.screen.text
    assert RemoteOps(store).pending("UA") == []


def test_giving_an_item_another_member_holds_is_refused(server):
    store, _ = server
    post(server, bag=[{**SCARF, "key": "leftovers", "name": "먹다남은음식", "held_item": "leftovers"}])
    reply = bot(store).editor.act("UA", ITEM_ACTION, "p2|leftovers", [])
    assert REASONS["item_clause"] in reply.screen.text


def test_a_stale_press_names_what_changed(server):
    store, _ = server
    post(server)
    assert bot(store).editor.act("UA", SWAP_ACTION, "gone|b1", []).screen.text == STALE


# Held items move between the bag and the holders


def test_equipping_takes_a_bag_copy_and_taking_off_puts_one_back(server):
    store, _ = server
    post(server)
    editor = bot(store).editor
    editor.act("UA", ITEM_ACTION, "p2|choiceScarf", [])
    editor.act("UA", ITEM_ACTION, "p1|", [])
    view = RemoteOps(store).view("UA")
    assert [member.get("item_key") for member in view.party] == [None, "choiceScarf"]
    assert view.party[1]["held_item"] == "choice-scarf"
    assert "held_item" not in view.party[0]
    assert {line["key"]: line["count"] for line in view.bag} == {"tm:89": 1, "rareCandy": 3, "leftovers": 1}
    assert select_values(editor.handle("UA", PARTY_COMMAND, "").blocks, "p1", ITEM_ACTION) == ["p1|", "p1|leftovers"]


def test_an_item_without_a_bag_copy_cannot_be_equipped(server):
    store, _ = server
    post(server, bag=[{**SCARF, "count": 1}])
    editor = bot(store).editor
    editor.act("UA", ITEM_ACTION, "p2|choiceScarf", [])
    reply = editor.act("UA", ITEM_ACTION, "p1|choiceScarf", [])
    assert REASONS["no_item"] in reply.screen.text


# Moves


def test_the_moves_screen_lists_learnable_moves_and_a_pick_queues_them_with_the_machine_ones(server):
    store, _ = server
    post(server)
    editor = bot(store).editor
    screen = editor.act("UA", MOVES_ACTION, "p1", []).screen
    select = screen.blocks[1]["elements"][0]
    assert (select["action_id"], select["max_selected_items"]) == (SET_MOVES_ACTION, 4)
    groups = {group["label"]["text"]: [option["value"] for option in group["options"]] for group in select["option_groups"]}
    assert groups == {"레벨업": [str(move["id"]) for move in MOVES[25] if move["level"] <= 42], "기술머신": ["89"]}
    editor.act("UA", SET_MOVES_ACTION, "p1", ["85", "89", "999"])
    first = RemoteOps(store).party("UA").party[0]
    assert (first["moves"], first["machine"]) == ([85, 89], [89])
    again = editor.act("UA", MOVES_ACTION, "p1", []).screen.blocks[1]["elements"][0]
    assert [option["value"] for option in again["initial_options"]] == ["85", "89"]
    editor.act("UA", DEFAULT_MOVES_ACTION, "p1", [])
    assert "moves" not in RemoteOps(store).party("UA").party[0]


def test_a_machine_move_without_its_tm_is_refused_on_replay(server):
    store, _ = server
    post(server, bag=[SCARF])
    RemoteOps(store).submit("UA", LINEUP, {"members": [
        {"id": "p1", "pokemon_id": 25, "name": "피카츄", "moves": [89], "machine": [89], "item": "leftovers"}]})
    assert party_ids(store) == ["p1", "p2"]


# /박스 button


def test_a_box_search_offers_entry_buttons_for_pokemon_that_can_join(server):
    store, _ = server
    post(server)
    blocks = bot(store).editor.handle("UA", BOX_COMMAND, "고라파덕").blocks
    assert blocks[1]["accessory"]["value"] == "b1"
    assert "accessory" not in bot(store).editor.handle("UA", BOX_COMMAND, "피카츄").blocks[1]
    bot(store).editor.act("UA", BOX_ADD_ACTION, "b1", [])
    assert party_ids(store) == ["p1", "p2", "b1"]


def test_adding_from_the_box_to_a_full_party_asks_whom_it_replaces(server):
    store, _ = server
    six = [party_member(f"p{index}", species, 20) for index, species in enumerate((25, 7, 8, 9, 26, 172), 1)]
    post(server, party=six)
    editor = bot(store).editor
    reply = editor.act("UA", BOX_ADD_ACTION, "b1", [])
    options = reply.screen.blocks[1]["elements"][0]["options"]
    assert [option["value"] for option in options] == [f"p{index}|b1" for index in range(1, 7)]
    editor.act("UA", SWAP_ACTION, "p3|b1", [])
    assert party_ids(store) == ["p1", "p2", "b1", "p4", "p5", "p6"]
    assert editor.act("UA", BACK_ACTION, "b1", []).replace


# Sync with the app


def test_an_upload_from_before_the_op_does_not_undo_it_and_the_applied_one_settles_it(server):
    store, base = server
    post(server)
    bot(store).editor.act("UA", SWAP_ACTION, "p1|b1", [])
    (op,) = RemoteOps(store).pending("UA")
    post(server)
    assert party_ids(store) == ["b1", "p2"]
    applied_party = [party_member("b1", 54, 30), party_member("p2", 7, 20)]
    post(server, party=applied_party, pool=[POOL[1], POOL[3]], applied=op.id)
    assert party_ids(store) == ["b1", "p2"]
    status, _ = call(f"{base}/v1/ops/ack", "POST", store.issue_token("UA", keep_existing=True),
                     {"applied": [op.id], "cancelled": []})
    assert status == 200 and RemoteOps(store).pending("UA") == []


def test_a_new_lineup_op_supersedes_the_pending_one(server):
    store, _ = server
    post(server)
    editor = bot(store).editor
    editor.act("UA", SWAP_ACTION, "p1|b1", [])
    editor.act("UA", SWAP_ACTION, "p2|b4", [])
    (op,) = RemoteOps(store).pending("UA")
    assert [member["id"] for member in op.payload["members"]] == ["b1", "b4"]
    assert RemoteOps(store).ack("UA", [op.id - 1], []) is None


def test_an_applied_op_id_from_another_bot_database_counts_as_none(server):
    store, base = server
    post(server)
    bot(store).editor.act("UA", SWAP_ACTION, "p1|b1", [])
    (op,) = RemoteOps(store).pending("UA")
    post(server, applied=op.id, ops_epoch="another-database")
    assert party_ids(store) == ["b1", "p2"]
    _, body = call(f"{base}/v1/ops", "GET", store.issue_token("UA", keep_existing=True))
    assert body["epoch"] == RemoteOps(store).epoch
    post(server, applied=op.id, ops_epoch=RemoteOps(store).epoch)
    assert party_ids(store) == ["p1", "p2"]


def test_a_pool_member_is_kept_only_when_valid_and_never_delivered(server):
    store, _ = server
    broken = {**POOL[0], "id": "b9", "member": {"pokemon_id": "x"}}
    post(server, pool=[*POOL, broken])
    pool = {entry["id"]: entry for entry in TradeService(store).pool("UA")}
    assert pool["b1"]["member"]["id"] == "b1" and "member" not in pool["b9"]
    assert [member["id"] for member in RemoteOps(store).view("UA").bench] == ["b1", "b2", "b3", "b4"]


# Slack plumbing


def test_the_action_listener_replaces_the_screen_and_answers_a_refusal_under_it(server):
    store, _ = server
    post(server)
    listener = editor_listener(bot(store).editor)
    sent = []

    def press(action):
        listener(ack=lambda: None, body={"user": {"id": "UA"}}, action=action,
                 respond=lambda **message: sent.append(message))

    press({"action_id": SWAP_ACTION, "block_id": "p1", "selected_option": {"value": "p1|b1"}})
    press({"action_id": SWAP_ACTION, "block_id": "p1", "selected_option": {"value": "p1|b2"}})
    assert [(message["replace_original"], message["response_type"]) for message in sent] == [
        (True, "ephemeral"), (False, "ephemeral")]
    assert party_ids(store) == ["b1", "p2"]
    press({"action_id": SET_MOVES_ACTION, "block_id": "b1", "selected_options": [{"value": "33"}]})
    assert RemoteOps(store).party("UA").party[0]["moves"] == [33]


def test_the_options_listener_filters_the_swap_menu_by_the_typed_name(server):
    store, _ = server
    post(server)
    answered = []
    editor_options_listener(bot(store).editor)(ack=lambda **reply: answered.append(reply), body={"user": {"id": "UA"}},
                                               payload={"block_id": "p2", "value": "콘치"})
    assert [option["value"] for option in answered[0]["options"]] == ["p2|b4"]


def test_the_party_slash_command_answers_with_the_editor(server):
    store, _ = server
    post(server)
    reply = bot(store).handle("UA", "", PARTY_COMMAND)
    assert any(block.get("block_id") == "p1" for block in reply.blocks)


def test_the_result_dm_words_a_cancelled_lineup_op_with_its_reason(server):
    store, _ = server
    post(server)
    bot(store).editor.act("UA", SWAP_ACTION, "p1|b1", [])
    (op,) = RemoteOps(store).pending("UA")
    message = RemoteOps(store).ack("UA", [], [(op.id, "gone")])
    assert "대결 라인업 바꾸기: 고라파덕 · 꼬부기" in message.text and REASONS["gone"] in message.text
