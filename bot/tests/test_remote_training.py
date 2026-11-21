from dataclasses import replace

import pytest
from slack_rules import violations
from test_commands import NOW, move
from test_remote_lineup import LineupAPI, party_member
from test_remote_ops import text_of
from test_upload_server import FakeMoves, call

import ypoke.commands
from ypoke.commands import HELP_TEXT, CommandHandler
from ypoke.lineup_editor import SET_MOVES_ACTION as LINEUP_SET_MOVES_ACTION
from ypoke.lineup_editor import SWAP_ACTION, TRAINING_OPEN_ACTION
from ypoke.remote_buy import BUY
from ypoke.remote_lineup import LINEUP
from ypoke.remote_ops import OLD_APP_REFUSAL, RemoteOps
from ypoke.remote_train import REASONS, TRAIN, train
from ypoke.remote_views import PARTY_COMMAND, SHOP_COMMAND, TRAINING_COMMAND, ability_name
from ypoke.shop_editor import BUY_ACTION, SHORT
from ypoke.store import Store
from ypoke.trades import TradeService
from ypoke.training_editor import (
    BACK_ACTION,
    CAP_ACTION,
    CAPSULE_ACTION,
    DEFAULT_MOVES_ACTION,
    FORM_ACTION,
    GOLD_CAP_ACTION,
    HERB_ACTION,
    MOVES_ACTION,
    NATURE_ACTION,
    PATCH_ACTION,
    PICK_ACTION,
    SET_MOVES_ACTION,
)
from ypoke.transport import editor_listener
from ypoke.upload_server import battle_overview, serve

IVS = {"hp": 10, "attack": 20, "defense": 31, "special_attack": 5, "special_defense": 6, "speed": 7}
CAMEL_IVS = {"hp": 10, "attack": 20, "defense": 31, "specialAttack": 5, "specialDefense": 6, "speed": 7}
THUNDURUS_FORMS = [{"form": "incarnate", "pokemon_id": 642, "ability": None},
                   {"form": "therian", "pokemon_id": 10020, "ability": "volt-absorb"}]
THUNDURUS = party_member("p1", 642, 50, id="p1", nature="hardy", ability="prankster", ability_slot=1,
                         own_ability="prankster", form="incarnate", form_tool="revealGlass", forms=THUNDURUS_FORMS,
                         ivs=dict(IVS))
PIKACHU = party_member("p2", 25, 42, nature="hardy", ability="static", ability_slot=1, egg_moves=True, ivs=dict(IVS))
PSYDUCK = {"id": "b1", "pokemon_id": 54, "level": 30, "shiny": False, "name": "고라파덕",
           "entry": {"nature": "bold", "profile": {"ivs": dict(CAMEL_IVS), "abilitySlot": 1, "abilityIsHidden": False,
                                                    "abilityName": "damp"}},
           "member": {"pokemon_id": 54, "level": 30, "shiny": False, "ivs": dict(IVS), "nature": "bold",
                      "ability": "damp", "ability_slot": 1, "egg_moves": True}}
PARTY = [THUNDURUS, PIKACHU]
POOL = [PSYDUCK]
MINT = {"key": "mint", "name": "민트", "count": 1}
BAG = [MINT, {"key": "abilityCapsule", "name": "특성캡슐", "count": 1},
       {"key": "abilityPatch", "name": "특성패치", "count": 1}, {"key": "bottleCap", "name": "병뚜껑", "count": 2},
       {"key": "goldBottleCap", "name": "금색병뚜껑", "count": 1}, {"key": "revealGlass", "name": "비추는거울", "count": 1}]
SHOP = [{"key": "mint", "name": "민트", "price": 300, "category": "growth", "category_name": "육성", "single": False},
        {"key": "mirrorHerb", "name": "흉내허브", "price": 400, "category": "growth", "category_name": "육성",
         "single": False},
        {"key": "rareCandy", "name": "이상한사탕", "price": 200, "category": "growth", "category_name": "육성",
         "single": False}]
KINDS = (BUY, LINEUP, TRAIN)
ABILITIES = {
    25: [{"name": "static", "slot": 1, "hidden": False}, {"name": "lightning-rod", "slot": 3, "hidden": True}],
    54: [{"name": "damp", "slot": 1, "hidden": False}, {"name": "cloud-nine", "slot": 2, "hidden": False},
         {"name": "swift-swim", "slot": 3, "hidden": True}],
    642: [{"name": "prankster", "slot": 1, "hidden": False}, {"name": "defiant", "slot": 3, "hidden": True}],
}
EGG_MOVE = move(56, "하이드로펌프", "water", 110, 0)


class TrainingAPI(LineupAPI):
    """Abilities by `/pokemon` id, and Hydro Pump as an egg move once a Mirror Herb is used."""

    def abilities(self, pokemon_id):
        return ABILITIES.get(pokemon_id, [])

    def attacking_moves(self, pokemon_id, level, machine_ids=(), status=False, egg=False):
        moves = super().attacking_moves(pokemon_id, level, machine_ids, status, egg)
        return [*moves, {**EGG_MOVE, "source": "egg"}] if egg else moves


@pytest.fixture
def server(tmp_path):
    store = Store(str(tmp_path / "bot.sqlite3"))
    http_server = serve(store, "127.0.0.1", 0, lambda user_id, party: None, FakeMoves(), trades=TradeService(store))
    yield store, f"http://127.0.0.1:{http_server.server_address[1]}"
    http_server.shutdown()


def post(server, user_id="UA", party=PARTY, pool=POOL, bag=BAG, wallet=500, kinds=KINDS, applied=0):
    store, base = server
    body = {"party": party, "trade_pool": pool, "remote_ops": 1, "applied_op_id": applied, "wallet": wallet,
            "bag": bag, "shop": SHOP, "remote_ops_kinds": list(kinds)}
    status, reply = call(f"{base}/v1/party", "POST", store.issue_token(user_id, keep_existing=True), body)
    assert status == 200, reply
    return reply


def bot(store):
    return CommandHandler(store, TrainingAPI(), now=lambda: NOW, bot_user_id="UBOT")


def press(store, action_id, value, selected=()):
    return bot(store).training.act("UA", action_id, value, list(selected))


def trained(store, action_id, value, selected=()):
    reply = press(store, action_id, value, selected)
    assert reply.replace, reply.screen.text
    return reply


def view(store):
    return RemoteOps(store).view("UA")


def member_of(store, individual_id):
    current = view(store)
    return next(member for member in [*current.party, *current.bench] if member["id"] == individual_id)


def count(store, key):
    return sum(line["count"] for line in view(store).bag if line["key"] == key)


def controls(blocks):
    return {element["action_id"]: element for block in blocks if block["type"] == "actions"
            for element in block["elements"]}


# The /트레이닝 screens


def test_the_picker_lists_the_party_then_the_box_and_a_name_opens_one(server):
    store, _ = server
    post(server)
    blocks = bot(store).handle("UA", "", TRAINING_COMMAND).blocks
    picker = controls(blocks)[PICK_ACTION]
    assert [option["value"] for option in picker["options"]] == ["p1", "p2", "b1"]
    assert picker["options"][0]["text"]["text"].startswith("[파티] ")
    opened = bot(store).handle("UA", "고라파덕", TRAINING_COMMAND)
    assert "고라파덕" in opened.text and NATURE_ACTION in controls(opened.blocks)


def test_the_pokemon_screen_says_what_each_control_costs(server):
    store, _ = server
    post(server, bag=[{"key": "abilityPatch", "name": "특성패치", "count": 1}])
    found = controls(press(store, PICK_ACTION, "p2").screen.blocks)
    assert found[NATURE_ACTION]["placeholder"]["text"] == "민트로 성격 바꾸기 (300토큰)"
    assert found[HERB_ACTION]["text"]["text"] == "흉내허브 (400토큰)"
    assert found[PATCH_ACTION]["text"]["text"] == f"특성패치 → {ability_name('lightning-rod')} (가방 ×1)"
    assert CAPSULE_ACTION not in found and CAP_ACTION not in found and GOLD_CAP_ACTION not in found
    assert set(found) >= {MOVES_ACTION, BACK_ACTION}


def test_controls_the_bag_and_balance_cannot_pay_are_left_out(server):
    store, _ = server
    post(server, bag=[], wallet=100)
    found = controls(press(store, PICK_ACTION, "p2").screen.blocks)
    assert NATURE_ACTION not in found and HERB_ACTION not in found and FORM_ACTION not in found


# Each action queues one train op, and the view changes at once


def test_a_mint_from_the_bag_sets_the_nature_and_uses_the_mint(server):
    store, _ = server
    post(server)
    trained(store, NATURE_ACTION, "p2|adamant")
    assert member_of(store, "p2")["nature"] == "adamant"
    assert count(store, "mint") == 0 and view(store).wallet == 500
    [op] = RemoteOps(store).pending("UA")
    assert (op.kind, op.payload["action"], op.payload["price"]) == (TRAIN, "nature", None)


def test_a_mint_with_none_in_the_bag_is_bought_at_the_shop_price(server):
    store, _ = server
    post(server, bag=[])
    trained(store, NATURE_ACTION, "b1|modest")
    assert member_of(store, "b1")["nature"] == "modest"
    assert view(store).pool[0]["entry"]["nature"] == "modest"
    assert view(store).wallet == 200
    assert RemoteOps(store).pending("UA")[0].payload["price"] == 300


def test_the_capsule_swaps_to_the_other_regular_ability(server):
    store, _ = server
    post(server)
    trained(store, CAPSULE_ACTION, "b1")
    changed = member_of(store, "b1")
    assert (changed["ability"], changed["ability_slot"]) == ("cloud-nine", 2)
    assert view(store).pool[0]["entry"]["profile"]["abilityName"] == "cloud-nine"
    assert count(store, "abilityCapsule") == 0


def test_the_patch_gives_the_hidden_ability(server):
    store, _ = server
    post(server)
    trained(store, PATCH_ACTION, "p2")
    changed = member_of(store, "p2")
    assert (changed["ability"], changed["ability_slot"], changed["ability_hidden"]) == ("lightning-rod", 3, True)
    assert count(store, "abilityPatch") == 0


def test_a_bottle_cap_maxes_one_iv_and_the_gold_one_all(server):
    store, _ = server
    post(server)
    trained(store, CAP_ACTION, "p2|special-attack")
    assert member_of(store, "p2")["ivs"]["special_attack"] == 31
    assert count(store, "bottleCap") == 1
    trained(store, GOLD_CAP_ACTION, "b1")
    assert set(member_of(store, "b1")["ivs"].values()) == {31}
    assert set(view(store).pool[0]["entry"]["profile"]["ivs"].values()) == {31}


def test_a_mirror_herb_is_bought_when_the_bag_has_none_and_unlocks_egg_moves(server):
    store, _ = server
    post(server)
    trained(store, HERB_ACTION, "b1")
    assert member_of(store, "b1")["mirror_herb"] is True
    assert view(store).pool[0]["entry"]["profile"]["mirrorHerb"] is True
    assert view(store).wallet == 100


def test_a_form_change_with_the_key_item_switches_the_form_ability_and_drops_the_moves(server):
    store, _ = server
    post(server, party=[{**THUNDURUS, "moves": [84]}, PIKACHU])
    trained(store, FORM_ACTION, "p1|therian")
    changed = member_of(store, "p1")
    assert (changed["pokemon_id"], changed["form"], changed["ability"]) == (10020, "therian", "volt-absorb")
    assert "moves" not in changed
    assert count(store, "revealGlass") == 1
    trained(store, FORM_ACTION, "p1|incarnate")
    assert (member_of(store, "p1")["pokemon_id"], member_of(store, "p1")["ability"]) == (642, "prankster")


def test_a_form_with_its_own_fixed_ability_offers_no_capsule_or_patch(server):
    store, _ = server
    post(server)
    trained(store, FORM_ACTION, "p1|therian")
    found = controls(press(store, PICK_ACTION, "p1").screen.blocks)
    assert CAPSULE_ACTION not in found and PATCH_ACTION not in found
    patch = {"name": "defiant", "slot": 3, "hidden": True}
    assert train(view(store), {"id": "p1", "pokemon_id": 10020, "action": "patch", "ability": patch})[1] == "not_applicable"


def test_moves_are_set_from_the_learnable_list_and_reset_to_the_defaults(server):
    store, _ = server
    post(server)
    reply = trained(store, SET_MOVES_ACTION, "p2", ["85", "98"])
    assert member_of(store, "p2")["moves"] == [85, 98]
    assert "10만볼트" in reply.screen.blocks[0]["text"]["text"]
    trained(store, DEFAULT_MOVES_ACTION, "p2")
    assert "moves" not in member_of(store, "p2")


def test_the_training_moves_menu_is_a_typed_search_with_the_current_moves_picked(server):
    store, _ = server
    post(server)
    trained(store, SET_MOVES_ACTION, "p2", ["85", "98"])
    select = press(store, MOVES_ACTION, "p2").screen.blocks[0]["accessory"]
    assert (select["type"], select["action_id"]) == ("multi_external_select", SET_MOVES_ACTION)
    assert [option["value"] for option in select["initial_options"]] == ["85", "98"]
    everything = [option["value"] for option in bot(store).training.move_options("UA", "p2", "")]
    assert everything[:2] == ["85", "98"] and len(everything) == len(set(everything)) > 2
    assert bot(store).training.move_options("UA", "gone", "") == []


# Refusals on the spot


def test_a_herb_past_the_spendable_balance_is_refused_with_the_balance(server):
    store, _ = server
    post(server, wallet=300)
    reply = press(store, HERB_ACTION, "b1")
    assert not reply.replace
    assert REASONS["no_tokens"] in reply.screen.text and "쓸 수 있는 토큰 300, 필요한 토큰 400" in reply.screen.text
    assert RemoteOps(store).pending("UA") == []


def test_pending_training_costs_come_off_the_balance_the_shop_spends(server):
    store, _ = server
    post(server, bag=[])
    trained(store, HERB_ACTION, "b1")
    reply = bot(store).shop.act("UA", BUY_ACTION, "1|200|rareCandy", [])
    assert not reply.replace and SHORT in reply.screen.text
    assert "쓸 수 있는 토큰 100" in str(bot(store).handle("UA", "", SHOP_COMMAND).blocks)


def test_a_second_mint_buy_past_the_balance_is_refused(server):
    store, _ = server
    post(server, bag=[])
    trained(store, NATURE_ACTION, "b1|modest")
    reply = press(store, NATURE_ACTION, "p2|modest")
    assert not reply.replace and REASONS["no_tokens"] in reply.screen.text


@pytest.mark.parametrize("payload,reason", [
    ({"action": "nature", "nature": "hardy"}, "unchanged"),
    ({"action": "herb", "price": 400, "id": "p1", "pokemon_id": 642}, "not_applicable"),
    ({"action": "cap", "stat": "defense"}, "unchanged"),
    ({"action": "cap", "stat": "luck"}, "invalid"),
    ({"action": "moves", "moves": [56], "egg": [56]}, "no_herb"),
    ({"action": "moves", "moves": [89], "machine": [89]}, "no_machine"),
    ({"action": "nature", "nature": "adamant", "pokemon_id": 26}, "evolved"),
    ({"action": "nature", "nature": "adamant", "id": "gone"}, "gone"),
    ({"action": "dance"}, "invalid"),
])
def test_what_the_app_would_cancel_is_refused_before_it_is_queued(server, payload, reason):
    store, _ = server
    post(server, bag=[MINT, {"key": "bottleCap", "name": "병뚜껑", "count": 1}])
    assert train(view(store), {"id": "p2", "pokemon_id": 25, **payload})[1] == reason


def test_the_check_leaves_the_view_it_reads_unchanged(server):
    store, _ = server
    post(server)
    current = view(store)
    train(current, {"id": "p2", "pokemon_id": 25, "action": "nature", "nature": "adamant", "price": None})
    assert current.party[1]["nature"] == "hardy" and current.bag[0]["count"] == 1


def test_a_pokemon_in_a_trade_cannot_be_trained(server):
    store, _ = server
    post(server)
    locked = replace(view(store), bench=[])
    assert train(locked, {"id": "b1", "pokemon_id": 54, "action": "nature", "nature": "adamant"})[1] == "trade_locked"


# Every reader sees the trained Pokémon


def test_coworkers_battles_the_party_screen_the_overview_and_get_party_read_the_training(server, monkeypatch):
    store, base = server
    post(server)
    post(server, "UB", party=[party_member("q1", 7, 20)], pool=[], kinds=())
    trained(store, FORM_ACTION, "p1|therian")
    trained(store, NATURE_ACTION, "p2|adamant")
    fought = []
    real = ypoke.commands.combatant
    monkeypatch.setattr(ypoke.commands, "combatant", lambda api, member: fought.append(member) or real(api, member))
    bot(store).handle("UB", "<@UA|a> 2")
    sides = {member["pokemon_id"]: member for member in fought}
    assert (sides[10020]["ability"], sides[25]["nature"]) == ("volt-absorb", "adamant")
    assert 642 not in sides
    party_screen = bot(store).handle("UA", "", PARTY_COMMAND).blocks
    assert "고집" in " ".join(block["text"]["text"] for block in party_screen if block["type"] == "section")
    overview = battle_overview(store, "UB", lambda _: None, RemoteOps(store))
    assert [lead["pokemon_id"] for lead in overview["coworkers"]] == [10020]
    status, body = call(f"{base}/v1/party", "GET", store.issue_token("UA", keep_existing=True))
    assert status == 200 and [member["pokemon_id"] for member in body["party"]] == [10020, 25]
    assert body["party"][1]["nature"] == "adamant"


def test_a_lineup_after_a_mirror_herb_can_take_an_egg_move(server):
    store, _ = server
    post(server)
    trained(store, HERB_ACTION, "b1")
    editor = bot(store).editor
    assert editor.act("UA", SWAP_ACTION, "+|b1", []).replace
    reply = editor.act("UA", LINEUP_SET_MOVES_ACTION, "b1", ["56"])
    assert reply.replace, reply.screen.text
    assert next(member for member in view(store).party if member["id"] == "b1")["moves"] == [56]


def test_without_the_herb_the_lineup_does_not_offer_the_egg_move(server):
    store, _ = server
    post(server)
    editor = bot(store).editor
    editor.act("UA", SWAP_ACTION, "+|b1", [])
    editor.act("UA", LINEUP_SET_MOVES_ACTION, "b1", ["56"])
    assert "moves" not in next(member for member in view(store).party if member["id"] == "b1")


def test_the_party_screen_has_a_training_button_that_opens_the_pokemon(server):
    store, _ = server
    post(server)
    blocks = bot(store).editor.handle("UA", PARTY_COMMAND, "").blocks
    assert TRAINING_OPEN_ACTION in controls(blocks)
    reply = press(store, TRAINING_OPEN_ACTION, "p2")
    assert reply.replace and NATURE_ACTION in controls(reply.screen.blocks)


def test_a_press_through_the_action_listener_queues_one_op(server):
    store, _ = server
    post(server)
    responses = []
    editor_listener(bot(store).training)(
        ack=lambda: None, body={"user": {"id": "UA"}},
        action={"action_id": NATURE_ACTION, "selected_option": {"value": "p2|jolly"}},
        respond=lambda **reply: responses.append(reply))
    assert responses[0]["replace_original"] is True
    assert [op.payload["nature"] for op in RemoteOps(store).pending("UA")] == ["jolly"]


# The app settles


def test_the_ack_clears_the_op_and_a_cancel_is_worded(server):
    store, base = server
    post(server)
    trained(store, NATURE_ACTION, "p2|adamant")
    trained(store, CAPSULE_ACTION, "b1")
    first, second = RemoteOps(store).pending("UA")
    message = RemoteOps(store).ack("UA", [first.id], [(second.id, "no_item")])
    assert f"❌ 트레이닝 특성캡슐: 고라파덕 → {ability_name('cloud-nine')}: {REASONS['no_item']}" in message.text
    post(server, applied=second.id, party=[THUNDURUS, {**PIKACHU, "nature": "adamant"}])
    assert RemoteOps(store).pending("UA") == []
    assert member_of(store, "p2")["nature"] == "adamant" and member_of(store, "b1")["ability"] == "damp"


# Upload hints


def test_the_upload_keeps_well_formed_training_hints_and_drops_the_rest(server):
    store, _ = server
    bad_forms = [{"form": "therian", "pokemon_id": 99999, "ability": None}]
    post(server, party=[THUNDURUS, {**PIKACHU, "ability_slot": 9, "egg_moves": "yes", "form": "x y",
                                    "forms": THUNDURUS_FORMS}],
         pool=[{**PSYDUCK, "member": {**PSYDUCK["member"], "form_tool": "revealGlass", "forms": bad_forms}}])
    kept = member_of(store, "p1")
    assert (kept["form_tool"], kept["forms"], kept["ability_slot"]) == ("revealGlass", THUNDURUS_FORMS, 1)
    dropped = member_of(store, "p2")
    assert not {"ability_slot", "egg_moves", "form", "forms"} & set(dropped)
    assert "forms" not in member_of(store, "b1")


# Old apps


def test_an_app_that_does_not_apply_train_ops_gets_a_read_only_screen_and_a_refusal(server):
    store, _ = server
    post(server, kinds=(BUY, LINEUP))
    reply = bot(store).handle("UA", "", TRAINING_COMMAND)
    assert text_of(reply).split("\n")[1] == OLD_APP_REFUSAL
    assert not [block for block in reply.blocks if block["type"] == "actions"]
    assert "고라파덕" in text_of(reply)
    assert press(store, NATURE_ACTION, "p2|adamant").screen.text == OLD_APP_REFUSAL
    assert TRAINING_OPEN_ACTION not in controls(bot(store).editor.handle("UA", PARTY_COMMAND, "").blocks)
    assert RemoteOps(store).pending("UA") == []


def test_every_training_screen_follows_slacks_block_rules(server):
    store, _ = server
    post(server)
    editor = bot(store).training
    screens = [editor.handle("UA", TRAINING_COMMAND, ""), editor.handle("UA", TRAINING_COMMAND, "썬더로스"),
               press(store, PICK_ACTION, "p2").screen, press(store, MOVES_ACTION, "p2").screen,
               press(store, SET_MOVES_ACTION, "p2", ["85", "98"]).screen, press(store, PICK_ACTION, "b1").screen]
    assert [violations(screen.blocks) for screen in screens] == [[]] * len(screens)
    assert press(store, MOVES_ACTION, "p2").screen.blocks[0]["accessory"]["type"] == "multi_external_select"


def test_the_help_explains_training():
    assert f"`{TRAINING_COMMAND} [이름]`" in HELP_TEXT and "흉내허브" in HELP_TEXT
