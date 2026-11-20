"""The battle card in the channel, the turn log in its thread, and the matchup pictures above the log."""

from io import BytesIO

import pytest
from PIL import Image
from test_commands import handler, member, upload
from test_result_thread import FakeClient, FakeRespond, mention_event, slash

from ypoke import battle_render
from ypoke.battle import (
    Action,
    BaseStats,
    BattleResult,
    Combatant,
    FormShift,
    MegaEvolution,
    SendOut,
)
from ypoke.battle_render import CANVAS, MatchupPictures, cache_key, composite
from ypoke.commands import (
    LOG_BLOCK_LIMIT,
    REMATCH_ACTION_ID,
    Delivery,
    Reply,
    Where,
    log_messages,
    result_blocks,
)
from ypoke.narration import Matchup, Portrait, battle_card
from ypoke.store import Store
from ypoke.transport import deliver, mention_listener, rematch_listener

RED, BLUE = (220, 30, 30, 255), (30, 30, 220, 255)


@pytest.fixture
def store(tmp_path):
    return Store(str(tmp_path / "bot.sqlite3"))


def ready_pair(store):
    upload(store, "UA", 25, 60)
    upload(store, "UB", 7, 20)


def mon(name, pokemon_id, shiny=False):
    return Combatant(name, 50, ("normal",), BaseStats(80, 80, 80, 80, 80, 80), BaseStats(15, 15, 15, 15, 15, 15),
                     shiny=shiny, pokemon_id=pokemon_id)


def hit(turn, side, defender_hp=90, knockout=False):
    return Action(turn, side, "a", "b", "몸통박치기", defender_hp=defender_hp, knockout=knockout)


def card_of(sides, events, remaining, turns=None):
    result = BattleResult(0, turns or max(event.turn for event in events), events, remaining=remaining)
    return battle_card(("<@UA>", "<@UB>"), sides, result)


def drawn_pairs(card):
    return [(matchup.left.form_id, matchup.right.form_id) if matchup else None for matchup in card.log_matchups]


class FakePictures:
    """Uploads nothing: each matchup's picture is a `slack_file` block named after its cache key."""

    def __init__(self, fail=False):
        self.fail = fail
        self.forgotten = []
        self.settled = 0

    def image_blocks(self, client, matchups):
        if self.fail:
            return {}
        return {matchup: battle_render.image_block(cache_key(matchup), matchup) for matchup in matchups}

    def settle(self):
        self.settled += 1

    def forget(self, matchups):
        self.forgotten += list(matchups)


class RefusingFiles(FakeClient):
    """Slack refuses any message that shows an uploaded file."""

    def chat_postMessage(self, **kwargs):
        if any("slack_file" in block for block in kwargs.get("blocks") or ()):
            raise RuntimeError("invalid_blocks")
        return super().chat_postMessage(**kwargs)


def is_card(post):
    return any(block["type"] == "actions" for block in post["blocks"])


def test_the_card_has_no_log_and_the_log_is_in_the_cards_thread(store):
    ready_pair(store)
    client = FakeClient()
    slash(handler(store), client, FakeRespond())
    card, *logs = client.posts
    assert is_card(card) and card["thread_ts"] is None
    assert [block["type"] for block in card["blocks"]] == ["context", "section", "section", "actions"]
    assert logs and all(post["thread_ts"] == "9.1" and post["channel"] == "CCHAN" for post in logs)
    assert logs[0]["blocks"][-1]["text"]["text"].startswith("*1턴*")


def test_turns_are_full_width_sections_not_grey_context(store):
    ready_pair(store)
    reply = handler(store).handle("UA", "<@UB>")
    [message] = log_messages(reply)
    turns = [block for block in message.blocks if block["type"] == "section"]
    assert [turn["text"]["text"] for turn in turns] == list(reply.card.log)
    assert all("accessory" not in turn for turn in turns)


def test_a_mention_keeps_the_card_and_the_log_in_the_mentions_thread(store):
    ready_pair(store)
    client = FakeClient()
    mention_listener(handler(store), FakePictures())(mention_event(thread_ts="4.4"), client)
    card, *logs = client.posts
    assert is_card(card) and logs
    assert {post["thread_ts"] for post in client.posts} == {"4.4"}


def test_a_rematch_of_a_channel_card_posts_its_card_in_the_channel_with_its_own_thread(store):
    ready_pair(store)
    client = FakeClient()
    old_card = {"ts": "8.1", "thread_ts": "8.1", "blocks": result_blocks(handler(store).handle("UA", "<@UB>"))}
    loser = next(block for block in old_card["blocks"] if block["type"] == "actions")["elements"][0]["value"].split(":")[3]
    body = {"user": {"id": loser}, "channel": {"id": "CCHAN"}, "message": old_card}
    rematch_listener(handler(store))(lambda: None, body, {"value": f"UA:UB:1:{loser}"}, FakeRespond(), client)
    card, *logs = client.posts
    assert is_card(card) and card["thread_ts"] is None
    assert logs and {post["thread_ts"] for post in logs} == {"9.1"}


def test_a_rematch_of_a_card_in_a_mention_thread_stays_in_that_thread(store):
    ready_pair(store)
    client = FakeClient()
    body = {"user": {"id": "UA"}, "channel": {"id": "CCHAN"}, "message": {"ts": "8.2", "thread_ts": "4.4"}}
    rematch_listener(handler(store))(lambda: None, body, {"value": "UA:UB:1:UA"}, FakeRespond(), client)
    assert {post["thread_ts"] for post in client.posts} == {"4.4"}


def test_a_pending_battle_posts_its_card_and_threads_the_log_off_it(store):
    ready_pair(store)
    reply = handler(store).handle("UA", "<@UB>", echo=True)
    client = FakeClient()
    deliver(client, Delivery("UA", Where("CCHAN"), reply), FakePictures())
    card, *logs = client.posts
    assert is_card(card) and card["thread_ts"] is None
    assert logs and {post["thread_ts"] for post in logs} == {"9.1"}


def test_the_response_url_path_sends_the_card_then_the_log_as_the_next_messages(store):
    ready_pair(store)
    respond = FakeRespond()
    slash(handler(store), FakeClient(fail_post=True), respond)
    card, *logs = respond.calls
    assert is_card(card) and logs
    assert all(call["response_type"] == "in_channel" for call in respond.calls)


def test_the_lead_pair_is_drawn_above_the_first_turn_and_not_again_while_it_stays():
    sides = ((mon("피카츄", 25),), (mon("꼬부기", 7),))
    card = card_of(sides, [hit(1, 0), hit(2, 1), hit(3, 0)], ((80,), (40,)))
    assert drawn_pairs(card) == [(25, 7), None, None]
    assert card.log_matchups[0].left == Portrait(25, False, "피카츄")


def test_a_knockout_replacement_draws_the_new_pair_above_the_next_turn():
    sides = ((mon("피카츄", 25),), (mon("꼬부기", 7), mon("파이리", 4)))
    events = [hit(1, 0), hit(2, 0, 0, knockout=True), SendOut(2, 1, "파이리", 1), hit(3, 0), hit(4, 1)]
    card = card_of(sides, events, ((80,), (0, 50)))
    assert drawn_pairs(card) == [(25, 7), None, (25, 4), None]


def test_a_switch_in_by_member_index_draws_that_member():
    sides = ((mon("피카츄", 25), mon("라이츄", 26), mon("이브이", 133)), (mon("꼬부기", 7),))
    events = [hit(1, 0), SendOut(1, 0, "이브이", 2), hit(2, 1)]
    card = card_of(sides, events, ((80, 100, 70), (40,)))
    assert drawn_pairs(card) == [(25, 7), (133, 7)]


def test_a_mega_draws_the_pair_again_in_its_shiny_mega_form():
    sides = ((mon("리자몽", 6, shiny=True),), (mon("꼬부기", 7),))
    events = [hit(1, 0), MegaEvolution(2, 0, "리자몽", None, 10034), hit(2, 0)]
    card = card_of(sides, events, ((80,), (40,)))
    assert drawn_pairs(card) == [(6, 7), (10034, 7)]
    assert card.log_matchups[1].left.url.endswith("/shiny/10034.png")


def test_an_entry_form_is_part_of_the_first_picture():
    sides = ((mon("테라파고스", 1024),), (mon("꼬부기", 7),))
    card = card_of(sides, [FormShift(1, 0, "테라파고스", "terastal", 10276), hit(1, 0)], ((80,), (40,)))
    assert drawn_pairs(card) == [(10276, 7)]


def test_a_flipping_ability_form_draws_no_new_picture():
    sides = ((mon("킬가르도", 681),), (mon("꼬부기", 7),))
    events = [hit(1, 0), FormShift(2, 0, "킬가르도", "blade", 10026), hit(2, 0),
              FormShift(3, 0, "킬가르도", "base", 681), hit(3, 0)]
    card = card_of(sides, events, ((80,), (40,)))
    assert drawn_pairs(card) == [(681, 7), None, None]


def test_a_member_without_a_species_id_draws_nothing():
    sides = ((Combatant("미상", 50, ("normal",), BaseStats(*[80] * 6), BaseStats(*[15] * 6)),), (mon("꼬부기", 7),))
    assert drawn_pairs(card_of(sides, [hit(1, 0)], ((80,), (40,)))) == [None]


def test_a_switch_deep_in_a_collapsed_battle_is_drawn_above_its_own_turn():
    sides = ((mon("피카츄", 25),), (mon("꼬부기", 7), mon("파이리", 4)))
    events = [hit(turn, 0) for turn in range(1, 200)]
    events.insert(99, SendOut(100, 1, "파이리", 1))
    card = card_of(sides, events, ((80,), (0, 50)))
    assert any("생략" in text for text in card.log)
    first, second = [index for index, matchup in enumerate(card.log_matchups) if matchup]
    assert first == 0 and card.log_matchups[second].right.form_id == 4
    assert card.log[second].startswith("*100턴*\n↪ 🔴 파이리 등장")


def test_a_picture_opens_its_turn_and_a_failed_upload_falls_back_to_a_small_sprite_line(store):
    ready_pair(store)
    reply = handler(store).handle("UA", "<@UB>")
    [drawn] = log_messages(reply, FakePictures().image_blocks(None, [reply.card.log_matchups[0]]))
    assert drawn.blocks[0]["type"] == "image" and drawn.blocks[0]["slack_file"]
    assert drawn.blocks[0]["title"]["text"] == "🔵 피카츄 vs 🔴 꼬부기"
    assert drawn.blocks[1]["text"]["text"].startswith("*1턴*")
    [plain] = log_messages(reply)
    line = plain.blocks[0]
    assert line["type"] == "context"
    assert [element["type"] for element in line["elements"]] == ["image", "mrkdwn", "image"]
    assert line["elements"][0]["image_url"].endswith("/25.png") and line["elements"][2]["image_url"].endswith("/7.png")


def test_an_upload_failure_still_posts_the_card_and_the_log_with_small_sprites(store):
    ready_pair(store)
    client = FakeClient()
    slash(handler(store), client, FakeRespond())
    card, log = client.posts[0], client.posts[1]
    assert is_card(card)
    assert log["blocks"][0]["type"] == "context" and log["blocks"][0]["elements"][0]["type"] == "image"


def test_a_refused_picture_is_sent_again_then_posted_with_small_sprites(store):
    ready_pair(store)
    client, pictures = RefusingFiles(), FakePictures()
    reply = handler(store).handle("UA", "<@UB>", echo=True)
    deliver(client, Delivery("UA", Where("CCHAN"), reply), pictures)
    card, log = client.posts
    assert is_card(card) and log["thread_ts"] == "9.1"
    assert log["blocks"][0]["type"] == "context"
    assert pictures.settled == 1 and pictures.forgotten == [reply.card.log_matchups[0]]


def test_a_long_six_on_six_splits_into_replies_under_fifty_blocks_in_order():
    card = full_party_battle()
    reply = Reply("h", summary="h", card=card, rematch="UA:UB:6")
    matchups = [matchup for matchup in card.log_matchups if matchup]
    assert len(matchups) == 11 and matchups[1].left.form_id == 10034
    messages = log_messages(reply, FakePictures().image_blocks(None, matchups))
    assert len(messages) == 2
    assert [message.text for message in messages] == ["대결 로그 1/2", "대결 로그 2/2"]
    assert all(len(message.blocks) <= LOG_BLOCK_LIMIT for message in messages)
    assert all(message.blocks[-1]["type"] == "section" for message in messages)
    turns = [block["text"]["text"] for message in messages for block in message.blocks if block["type"] == "section"]
    assert turns == list(card.log)
    assert sum(block["type"] == "image" for message in messages for block in message.blocks) == 11
    assert "*1턴*" in turns[0] and turns[-1].startswith("*300턴*")


def full_party_battle():
    """300 turns with all ten knockout replacements of a 6:6 and a Mega on each side."""
    sides = tuple(tuple(mon(f"{name}{index}", 100 + side * 10 + index) for index in range(6))
                  for side, name in enumerate(("가", "나")))
    events = []
    sent = [0, 0]
    for turn in range(1, 301):
        if turn in (40, 90):
            side = turn // 90
            events.append(MegaEvolution(turn, side, "메가", None, 10034 + side))
        events.append(hit(turn, turn % 2, 99))
        if turn % 25 == 0 and turn // 25 <= 10:
            side = (turn // 25) % 2
            sent[side] += 1
            events.append(hit(turn, 1 - side, 0, knockout=True))
            events.append(SendOut(turn, side, f"{('가', '나')[side]}{sent[side]}", sent[side]))
    return card_of(sides, events, ((50, 0, 0, 0, 0, 0), (0, 0, 0, 0, 0, 0)), turns=300)


def sprite(color, size=(100, 100), notch=True):
    """A solid square whose top-left quarter is clear, so a mirrored copy has its notch on the right."""
    image = Image.new("RGBA", size, color)
    if notch:
        image.paste((0, 0, 0, 0), (0, 0, size[0] // 2, size[1] // 2))
    out = BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()


def opaque_columns(image, x_range):
    return [x for x in x_range if any(image.getpixel((x, y))[3] for y in range(image.height))]


def test_the_challenger_is_on_the_left_mirrored_and_the_opponent_on_the_right():
    image = Image.open(BytesIO(composite(sprite(RED), sprite(BLUE)))).convert("RGBA")
    assert image.size == CANVAS
    half = CANVAS[0] // 2
    left, right = opaque_columns(image, range(half)), opaque_columns(image, range(half, CANVAS[0]))
    middle = (CANVAS[1] + battle_render.SPRITE_BOX) // 2 - 10
    assert image.getpixel((left[len(left) // 2], middle)) == RED
    assert image.getpixel((right[len(right) // 2], middle)) == BLUE
    top = (CANVAS[1] - battle_render.SPRITE_BOX) // 2 + 10
    assert image.getpixel((left[5], top))[3] == 255 and image.getpixel((left[-5], top))[3] == 0
    assert image.getpixel((right[5], top))[3] == 0 and image.getpixel((right[-5], top))[3] == 255


def test_each_side_is_large_enough_to_read_at_a_narrow_width():
    image = Image.open(BytesIO(composite(sprite(RED, (40, 60), False), sprite(BLUE, (300, 200), False))))
    half = CANVAS[0] // 2
    for columns in (opaque_columns(image, range(half)), opaque_columns(image, range(half, CANVAS[0]))):
        assert len(columns) >= 88
    assert len(opaque_columns(image, range(half, CANVAS[0]))) >= 0.3 * CANVAS[0]
    assert CANVAS[0] / CANVAS[1] <= 2


def test_the_background_stays_transparent():
    image = Image.open(BytesIO(composite(sprite(RED), sprite(BLUE)))).convert("RGBA")
    assert image.getpixel((0, 0))[3] == 0 and image.getpixel((CANVAS[0] // 2, 0))[3] == 0


class Uploads:
    def __init__(self, fail=False):
        self.fail = fail
        self.calls = []

    def files_upload_v2(self, **kwargs):
        if self.fail:
            raise RuntimeError("missing_scope")
        self.calls.append(kwargs)
        return {"file": {"id": f"F{len(self.calls)}"}}


def matchup(left=25, right=7, shiny=False):
    return Matchup(Portrait(left, shiny, "피카츄"), Portrait(right, False, "꼬부기"))


def test_sprites_pictures_and_file_ids_are_kept_so_a_rematch_fetches_and_uploads_nothing(store, tmp_path):
    fetched = []

    def fetch(url):
        fetched.append(url)
        return sprite(RED if url.endswith("/25.png") else BLUE)

    uploads = Uploads()
    pictures = MatchupPictures(store, tmp_path / "pictures", fetch)
    first = pictures.image_blocks(uploads, [matchup(), matchup()])
    assert first[matchup()]["slack_file"] == {"id": "F1"}
    assert len(fetched) == 2 and len(uploads.calls) == 1
    again = MatchupPictures(store, tmp_path / "pictures", fetch).image_blocks(uploads, [matchup()])
    assert again == first and len(fetched) == 2 and len(uploads.calls) == 1
    pictures.forget([matchup()])
    pictures.image_blocks(uploads, [matchup()])
    assert len(fetched) == 2 and len(uploads.calls) == 2


def test_a_shiny_and_a_plain_pair_are_different_pictures(store, tmp_path):
    uploads = Uploads()
    pictures = MatchupPictures(store, tmp_path, lambda url: sprite(RED))
    pictures.image_blocks(uploads, [matchup(), matchup(shiny=True)])
    assert len(uploads.calls) == 2


def test_an_upload_or_fetch_failure_leaves_the_picture_out(store, tmp_path):
    assert MatchupPictures(store, tmp_path, lambda url: sprite(RED)).image_blocks(Uploads(fail=True), [matchup()]) == {}

    def offline(url):
        raise OSError("offline")

    assert MatchupPictures(store, tmp_path / "other", offline).image_blocks(Uploads(), [matchup()]) == {}


def test_practice_battles_post_the_same_card_and_thread_log(store):
    upload(store, "UA", 25, 60)
    client = FakeClient()
    slash(handler(store), client, FakeRespond(), text="<@UBOT>")
    card, *logs = client.posts
    assert is_card(card) and logs and {post["thread_ts"] for post in logs} == {"9.1"}
    assert logs[0]["blocks"][0]["type"] == "context" and logs[0]["blocks"][0]["elements"][0]["type"] == "image"


def test_the_rematch_button_stays_on_the_card(store):
    for user in ("UA", "UB"):
        store.issue_token(user)
        store.save_party(user, [member(25, 50), member(7, 20), member(26, 40)])
    client = FakeClient()
    slash(handler(store), client, FakeRespond(), text="<@UB|bob> 3")
    card = client.posts[0]
    assert next(block for block in card["blocks"] if block["type"] == "actions")["elements"][0]["action_id"] == REMATCH_ACTION_ID
    assert not any(block["type"] in ("divider", "image") for block in card["blocks"])
