from datetime import UTC, datetime, timedelta

import pytest

from ypoke.store import Store
from ypoke.trades import (
    ACCEPT_ACTION_ID,
    DECLINE_ACTION_ID,
    MAX_POOL,
    PICK_ACTION_ID,
    TradeService,
    normalize_pool,
)

ALICE = "U0000000A"
BOB = "U0000000B"
CAROL = "U0000000C"
BOT = "U0000000Z"
NAMES = {ALICE: "앨리스", BOB: "밥", CAROL: "캐롤"}


class Clock:
    def __init__(self):
        self.now = datetime(2026, 11, 13, 9, 0, tzinfo=UTC)

    def __call__(self):
        return self.now

    def advance(self, **delta):
        self.now += timedelta(**delta)


def individual(individual_id, pokemon_id, name, level=60, shiny=False):
    return {"id": individual_id, "pokemon_id": pokemon_id, "level": level, "shiny": shiny, "name": name,
            "entry": {"id": individual_id, "baseID": pokemon_id, "finalID": pokemon_id}}


HAUNTER = individual("alice-haunter", 93, "고우스트", 100)
EEVEE = individual("alice-eevee", 133, "이브이", 55, shiny=True)
PIKACHU = individual("bob-pikachu", 25, "피카츄", 80)
SQUIRTLE = individual("bob-squirtle", 7, "꼬부기", 40)


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def trades(tmp_path, clock):
    store = Store(str(tmp_path / "bot.sqlite3"))
    service = TradeService(store, now=clock, name_for=NAMES.get, bot_user_id=BOT)
    service.save_pool(ALICE, [HAUNTER, EEVEE])
    service.save_pool(BOB, [PIKACHU, SQUIRTLE])
    return service


def complete(trades, give=HAUNTER, back=PIKACHU):
    trade_id = trades.propose(ALICE, BOB, give["id"]).trade_id
    assert trades.pick(BOB, trade_id, back["id"]).ok
    assert trades.accept(BOB, trade_id).final
    assert trades.accept(ALICE, trade_id).final
    return trade_id


def test_an_offer_dms_the_target_with_a_pick_list_and_buttons(trades):
    result = trades.propose(ALICE, BOB, HAUNTER["id"])

    assert result.error is None
    (message,) = result.direct_messages
    assert message.user_id == BOB
    assert "고우스트 Lv.100" in message.text
    select = message.blocks[1]["elements"][0]
    assert select["action_id"] == PICK_ACTION_ID
    assert [option["text"]["text"] for option in select["options"]] == ["피카츄 Lv.80", "꼬부기 Lv.40"]
    assert select["options"][0]["value"] == f"{result.trade_id}|bob-pikachu"
    assert [button["action_id"] for button in message.blocks[2]["elements"]] == [ACCEPT_ACTION_ID, DECLINE_ACTION_ID]


@pytest.mark.parametrize("target, give, error", [
    (ALICE, "alice-haunter", "self"),
    (BOT, "alice-haunter", "unknown_user"),
    (CAROL, "alice-haunter", "unknown_user"),
    (BOB, "alice-not-in-pool", "unknown_individual"),
])
def test_an_offer_is_refused_with_a_reason(trades, target, give, error):
    assert trades.propose(ALICE, target, give).error == error


def test_a_user_without_a_pool_is_not_a_coworker_to_trade_with(trades):
    trades.save_pool(CAROL, "not a list")

    assert [coworker["name"] for coworker in trades.coworkers(ALICE)] == ["밥"]


def test_coworkers_carry_a_stable_handle_that_is_not_the_slack_id_and_works_as_the_offer_target(trades):
    handle = trades.coworkers(ALICE)[0]["id"]

    assert handle != BOB
    assert trades.coworkers(ALICE)[0]["id"] == handle
    result = trades.propose(ALICE, handle, HAUNTER["id"])
    assert result.error is None
    assert result.direct_messages[0].user_id == BOB


def test_an_individual_in_an_open_offer_cannot_be_offered_again(trades):
    assert trades.propose(ALICE, BOB, HAUNTER["id"]).error is None

    assert trades.propose(ALICE, BOB, HAUNTER["id"]).error == "locked"


def test_the_pick_back_is_locked_in_other_offers(trades):
    trades.save_pool(CAROL, [individual("carol-ditto", 132, "메타몽")])
    first = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id
    second = trades.propose(CAROL, BOB, "carol-ditto").trade_id
    assert trades.pick(BOB, first, PIKACHU["id"]).ok

    assert trades.pick(BOB, second, PIKACHU["id"]).ok is False


def test_offer_to_offer_limit(trades):
    trades.save_pool(ALICE, [individual(f"a{index}", 1, "이상해씨") for index in range(4)])

    errors = [trades.propose(ALICE, BOB, f"a{index}").error for index in range(4)]

    assert errors == [None, None, None, "too_many"]


def test_both_sides_must_accept_and_the_trade_is_delivered_to_each(trades):
    trade_id = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id
    assert trades.deliveries(ALICE) == trades.deliveries(BOB) == []

    assert trades.pick(BOB, trade_id, PIKACHU["id"]).ok
    countered = trades.accept(BOB, trade_id)
    assert countered.final
    (confirm,) = countered.direct_messages
    assert confirm.user_id == ALICE and "피카츄 Lv.80" in confirm.text
    assert trades.deliveries(ALICE) == trades.deliveries(BOB) == []

    done = trades.accept(ALICE, trade_id)
    assert done.final and "교환이 끝났어요" in done.text
    assert [message.user_id for message in done.direct_messages] == [BOB]

    (to_alice,) = trades.deliveries(ALICE)
    (to_bob,) = trades.deliveries(BOB)
    assert to_alice == {"trade_id": trade_id, "give_id": "alice-haunter", "from_name": "밥", "receive": PIKACHU}
    assert to_bob == {"trade_id": trade_id, "give_id": "bob-pikachu", "from_name": "앨리스", "receive": HAUNTER}


def test_a_delivery_repeats_until_that_side_acknowledges_it(trades):
    trade_id = complete(trades)

    assert trades.deliveries(ALICE) == trades.deliveries(ALICE)
    trades.ack(ALICE, [trade_id])
    trades.ack(ALICE, [trade_id])

    assert trades.deliveries(ALICE) == []
    assert len(trades.deliveries(BOB)) == 1


def test_an_acknowledgement_only_counts_for_its_own_side(trades):
    trade_id = complete(trades)

    trades.ack(CAROL, [trade_id])

    assert len(trades.deliveries(ALICE)) == len(trades.deliveries(BOB)) == 1


def test_a_second_accept_does_not_complete_twice(trades):
    trade_id = complete(trades)

    again = trades.accept(ALICE, trade_id)

    assert again.ok is False
    assert len(trades.deliveries(ALICE)) == 1


def test_accepting_needs_a_pick_first(trades):
    trade_id = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id

    reply = trades.accept(BOB, trade_id)

    assert reply.ok is False and not reply.final


def test_the_proposer_cannot_accept_their_own_offer_and_strangers_cannot_press(trades):
    trade_id = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id

    assert trades.accept(ALICE, trade_id).ok is False
    assert trades.pick(CAROL, trade_id, PIKACHU["id"]).ok is False
    assert trades.decline(CAROL, trade_id).ok is False


@pytest.mark.parametrize("decliner, other", [(BOB, ALICE), (ALICE, BOB)])
def test_either_side_can_decline_and_the_other_is_told(trades, decliner, other):
    trade_id = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id

    reply = trades.decline(decliner, trade_id)

    assert reply.final
    assert [message.user_id for message in reply.direct_messages] == [other]
    assert trades.accept(BOB, trade_id).ok is False
    assert trades.deliveries(ALICE) == []
    assert trades.propose(ALICE, BOB, HAUNTER["id"]).error is None


def test_an_offer_expires_after_24_hours(trades, clock):
    trade_id = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id
    assert trades.pick(BOB, trade_id, PIKACHU["id"]).ok
    clock.advance(hours=24, seconds=1)

    reply = trades.accept(BOB, trade_id)

    assert reply.ok is False and reply.final and "24시간" in reply.text
    assert trades.history(ALICE)[0]["status"] == "expired"
    assert trades.propose(ALICE, BOB, HAUNTER["id"]).error is None


def test_a_countered_trade_expires_too_and_never_delivers(trades, clock):
    trade_id = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id
    trades.pick(BOB, trade_id, PIKACHU["id"])
    trades.accept(BOB, trade_id)
    clock.advance(hours=25)

    assert trades.accept(ALICE, trade_id).ok is False
    assert trades.deliveries(ALICE) == trades.deliveries(BOB) == []


def test_completion_is_refused_when_an_individual_left_the_tradable_pool(trades):
    trade_id = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id
    trades.pick(BOB, trade_id, PIKACHU["id"])
    trades.accept(BOB, trade_id)
    trades.save_pool(ALICE, [EEVEE])

    refused = trades.accept(ALICE, trade_id)

    assert refused.ok is False and "고우스트" in refused.text
    assert trades.deliveries(ALICE) == []
    trades.save_pool(ALICE, [HAUNTER, EEVEE])
    assert trades.accept(ALICE, trade_id).final


def test_the_pick_must_come_from_the_targets_pool(trades):
    trade_id = trades.propose(ALICE, BOB, HAUNTER["id"]).trade_id

    assert trades.pick(BOB, trade_id, "alice-eevee").ok is False


def test_history_lists_open_and_recent_trades_for_both_sides(trades):
    trade_id = complete(trades)

    (mine,) = trades.history(ALICE)
    (theirs,) = trades.history(BOB)

    assert (mine["trade_id"], mine["direction"], mine["status"], mine["with_name"]) == (trade_id, "outgoing", "completed", "밥")
    assert mine["give"]["pokemon_id"] == 93 and mine["want"]["pokemon_id"] == 25
    assert (theirs["direction"], theirs["give"]["pokemon_id"]) == ("incoming", 25)


def test_a_name_lookup_failure_falls_back_to_a_generic_name(tmp_path, clock):
    service = TradeService(Store(str(tmp_path / "bot.sqlite3")), now=clock)
    service.save_pool(ALICE, [HAUNTER])
    service.save_pool(BOB, [PIKACHU])

    assert service.coworkers(ALICE)[0]["name"] == "동료"


def test_pool_normalization_drops_bad_entries_and_caps_the_size():
    pool = normalize_pool([
        HAUNTER, HAUNTER,
        {**EEVEE, "pokemon_id": 0},
        {**EEVEE, "level": 101},
        {**EEVEE, "id": "a|b"},
        {**EEVEE, "entry": "no"},
        {**EEVEE, "entry": {"blob": "x" * 5000}},
        "junk",
        {**PIKACHU, "name": "   ", "shiny": "yes"},
    ])

    assert [entry["id"] for entry in pool] == ["alice-haunter", "bob-pikachu"]
    assert pool[1]["name"] == "#25" and pool[1]["shiny"] is False
    assert normalize_pool("nope") is None
    assert len(normalize_pool([individual(f"x{index}", 1, "a") for index in range(MAX_POOL + 20)])) == MAX_POOL
