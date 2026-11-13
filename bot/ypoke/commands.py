"""Slash command logic, independent of Slack transport."""

import random
import re
import secrets
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta, timezone
from urllib.parse import urlencode

from ypoke.battle import BATTLE_LEVEL, BaseStats, Combatant, MegaForm, simulate
from ypoke.dex import NATIONAL_TOTAL, progress_fields, progress_lines, sprite_url
from ypoke.mega_stones import mega_form_id
from ypoke.messages import DirectMessage
from ypoke.moves import battle_moves
from ypoke.narration import PRACTICE_NOTE, Card, battle_card, battle_header
from ypoke.pokeapi import PokeAPIService, base_stats
from ypoke.store import PendingChallenge, Record, Store
from ypoke.upload_server import IV_KEYS, MAX_ENTRY_SIZE

DEFAULT_IV = 15
REGISTER_LINK = "poketokenbar://ypoke-register"
DOWNLOAD_URL = "https://github.com/w8385/PokeTokenBar-yp/releases/latest"
REGISTER_ACTION_ID = "open_poketokenbar"
REMATCH_ACTION_ID = "rematch"
REMATCH_LABEL = "다시 붙기"
REMATCH_DENIED = "대결한 두 사람만 누를 수 있어요."
SECTION_TEXT_LIMIT = 3000
FIELD_TEXT_LIMIT = 2000
ECHO_ARG_LIMIT = 200
_REMATCH_VALUE = re.compile(r"([UW][A-Z0-9]+):([UW][A-Z0-9]+)(?::([13]))?")
FULL_ENTRY_WORDS = frozenset({"3", "3:3", "풀"})
_MENTION_SPLIT = re.compile(r"(<@[UW][A-Z0-9]+(?:\|[^>]*)?>)")
_MENTION = re.compile(r"<@([UW][A-Z0-9]+)(?:\|[^>]*)?>")
KST = timezone(timedelta(hours=9), "KST")
MAX_SPECIES_ID = 1025
RANKING_SIZE = 10
PENDING_LIFETIME = timedelta(hours=24)
PROMPT_INTERVAL = timedelta(hours=24)
RESPONSE_URL_LIFETIME = timedelta(minutes=30)
PENDING_HEADER = "기다리던 포켓몬이 올라와서 대결을 시작해요!"
NETWORK_NOTE = "포켓몬은 앱이 회사 네트워크에서 한 번 켜져 있어야 올라가요. 올라오면 대결이 바로 열려요(24시간 안)."

BATTLE_COMMAND = "/대결"
LINK_COMMAND = "/포켓몬연결"
RECORD_COMMAND = "/전적"
RANKING_COMMAND = "/랭킹"
DEX_COMMAND = "/도감"
UMBRELLA_COMMAND = "/ypoke"
COMMAND_NAMES = (BATTLE_COMMAND, LINK_COMMAND, RECORD_COMMAND, RANKING_COMMAND, DEX_COMMAND, UMBRELLA_COMMAND)
MENTION_WORDS = {
    "대결": BATTLE_COMMAND,
    "battle": BATTLE_COMMAND,
    "전적": RECORD_COMMAND,
    "랭킹": RANKING_COMMAND,
    "연결": LINK_COMMAND,
    "도감": DEX_COMMAND,
}

HELP_TEXT = (
    "*YPoke 대결*\n"
    f"`{BATTLE_COMMAND} @상대` 서로 한 마리씩 내보내 한 판 붙어요(1:1). 앱 대결 탭에서 첫 번째로 고른 포켓몬이, 안 골랐으면 지금 키우는 포켓몬이 나가요. "
    f"`{BATTLE_COMMAND} @상대 3`(`3:3`·`풀`도 돼요)이면 최대 3마리를 정한 순서대로 내보내요. 한 마리가 쓰러지면 다음 포켓몬이 나오고, 교체는 없어요. "
    "알만 있으면 대여 포켓몬이 상대 레벨로 나가요. 상대가 아직 준비 전이면 연결 안내를 보내고, 준비되면 결과가 이 채널에 올라가요.\n"
    f"`{BATTLE_COMMAND} @YPoke [3]` 또는 `@YPoke 대결 [3]` 봇이 무작위 포켓몬을 내보내 연습 대결을 해요. 전적에 안 남아요.\n"
    f"`{LINK_COMMAND}` 앱 연결 링크를 DM으로 보내요. 다시 하면 새 링크가 나오고 옛 연결은 끊겨요.\n"
    f"`{RECORD_COMMAND} [@누구]` 승패를 보여줘요.\n"
    f"`{RANKING_COMMAND}` 이번 주(월요일 0시부터) 승리 순위를 이 채널에 올려요.\n"
    f"`{DEX_COMMAND} [@누구]` 도감 수·이로치 수·지역별 진행·대표 포켓몬을 보여줘요. 앱을 켜 둬야 도감이 올라가요.\n"
    "스레드에서는 `@YPoke 대결 @상대`처럼 멘션으로 불러요. `@YPoke 전적`·`@YPoke 랭킹`·`@YPoke 도감`·`@YPoke 연결`도 돼요. "
    f"`{UMBRELLA_COMMAND} 도감`처럼 `{UMBRELLA_COMMAND}` 뒤에 붙여도 돼요.\n"
    "대결로는 포켓몬이 오가지 않아요. 졸업한 포켓몬은 앱 대결 탭의 교환 제안으로 맞바꿔요. 상대가 DM에서 고르고 수락하면 끝나요.\n"
    f"앱 받기: <{DOWNLOAD_URL}|PokeTokenBar>"
)


@dataclass(frozen=True)
class Where:
    """Where a command was used. `response_url` is the slash command's, which Slack honours for 30 minutes."""

    channel_id: str
    thread_ts: str | None = None
    response_url: str | None = None


@dataclass(frozen=True)
class Reply:
    """`echo` names who ran which slash command; it heads the visible messages (`in_channel` or `public`).

    A battle result is one message: `summary` (the header line, also its `text`), `card` (header, lineups and
    turn log) and `rematch` (the button value).
    `public` is a line the channel sees beside a private `text`. `image_url` is shown beside `text`.
    `fields` (Slack's 2-column grid) follow `lead`, the part of `text` above them, in the blocks; `text` stays the fallback.
    """

    text: str
    in_channel: bool = False
    direct_messages: tuple[DirectMessage, ...] = ()
    echo: str | None = None
    summary: str | None = None
    card: Card | None = None
    rematch: str | None = None
    public: str | None = None
    image_url: str | None = None
    fields: tuple[str, ...] = ()
    lead: str | None = None


@dataclass(frozen=True)
class Delivery:
    """A pending battle's result for the place it was asked for; `where.response_url` is None once stale."""

    challenger_id: str
    where: Where
    reply: Reply

    @property
    def text(self) -> str:
        return self.reply.text


@dataclass(frozen=True)
class _Match:
    challenger_id: str
    opponent_id: str
    sides: tuple[tuple[Combatant, ...], tuple[Combatant, ...]]
    seed: int
    practice: bool
    pokemon: tuple[int, int]
    size: int


class CommandHandler:
    def __init__(
        self,
        store: Store,
        pokeapi: PokeAPIService,
        public_url: str | None = None,
        now: Callable[[], datetime] = lambda: datetime.now(UTC),
        bot_user_id: str | None = None,
        home_channel: str | None = None,
    ):
        self._store = store
        self._pokeapi = pokeapi
        self._public_url = public_url
        self._now = now
        self._bot_user_id = bot_user_id
        self._help = f"{HELP_TEXT}\n대결 채널: <#{home_channel}>" if home_channel else HELP_TEXT

    def handle_mention(self, user_id: str, text: str, where: Where | None = None) -> Reply:
        """An `@YPoke …` message. Slack runs no slash commands in threads, so this covers every command."""
        command, rest = parse_mention(text, self._bot_user_id)
        if command is None:
            return Reply(self._help)
        if command == BATTLE_COMMAND and not _MENTION.search(rest):
            return self._start(user_id, self._bot_user_id, where, size=battle_size(rest))
        reply = self.handle(user_id, rest, command, where)
        return replace(reply, in_channel=True) if command == DEX_COMMAND else reply

    @property
    def bot_user_id(self) -> str | None:
        return self._bot_user_id

    def handle(
        self, user_id: str, text: str, command: str = BATTLE_COMMAND, where: Where | None = None, echo: bool = False
    ) -> Reply:
        """`where` is needed to keep a challenge pending until both sides have uploaded.

        With `echo`, a visible reply carries the line saying who typed the command (a slash command is invisible).
        """
        line = command_echo(user_id, command, text) if echo else None
        return _echoed(self._dispatch(user_id, text, command, where, line), line)

    def rematch(self, user_id: str, value: str, where: Where) -> Reply:
        """The 다시 붙기 button: only the two who fought may rerun the matchup with their current uploads."""
        parsed = _REMATCH_VALUE.fullmatch(value)
        if parsed is None or user_id not in parsed.groups():
            return Reply(REMATCH_DENIED)
        line = f"<@{user_id}> 님이 {REMATCH_LABEL}를 눌렀어요"
        challenger_id, opponent_id, size = parsed.groups()
        return _echoed(self._start(challenger_id, opponent_id, where, line, int(size or 1)), line)

    def run_pending(self, user_id: str) -> list[Delivery]:
        """After `user_id` uploads: play every pending challenge of theirs whose sides are now both ready, once."""
        now = self._now()
        deliveries = []
        for challenge in self._store.pending_for(user_id, since=now - PENDING_LIFETIME):
            try:
                match = self._prepare(challenge.challenger_id, challenge.opponent_id, challenge.size)
            except OSError:
                continue
            if match is None or not self._store.claim_pending(challenge):
                continue
            fresh = now - challenge.created_at < RESPONSE_URL_LIFETIME
            where = Where(challenge.channel_id, challenge.thread_ts, challenge.response_url if fresh else None)
            reply = self._result(match)
            reply = replace(reply, card=replace(reply.card, note=PENDING_HEADER), echo=challenge.echo)
            deliveries.append(Delivery(challenge.challenger_id, where, reply))
        return deliveries

    def _dispatch(self, user_id: str, text: str, command: str, where: Where | None, echo: str | None) -> Reply:
        if command == UMBRELLA_COMMAND:
            command, text = parse_mention(text, self._bot_user_id)
        mention = _MENTION.search(text)
        if command == LINK_COMMAND:
            return self._register(user_id)
        if command == RECORD_COMMAND:
            return self._record(mention.group(1) if mention else user_id)
        if command == DEX_COMMAND:
            return self._dex(user_id, mention.group(1) if mention else user_id)
        if command == RANKING_COMMAND:
            return self._ranking()
        if command == BATTLE_COMMAND and mention:
            if mention.group(1) == user_id:
                return Reply("자기 자신과는 대결할 수 없어요.")
            return self._start(user_id, mention.group(1), where, echo, battle_size(text))
        return Reply(self._help)

    def _register(self, user_id: str) -> Reply:
        token = self._store.issue_token(user_id)
        return Reply(
            "DM으로 연결 링크를 보냈어요.",
            direct_messages=(DirectMessage(user_id, "PokeTokenBar를 YPoke에 연결하세요.", self._link_blocks(token)),),
        )

    def _link_blocks(self, token: str) -> list[dict]:
        query = {"token": token}
        if self._public_url:
            query["server"] = self._public_url
        link = f"{REGISTER_LINK}?{urlencode(query)}"
        return [
            {"type": "section", "text": {"type": "mrkdwn", "text": "버튼을 누르면 PokeTokenBar가 YPoke에 연결돼요."}},
            {"type": "actions", "elements": [{
                "type": "button", "style": "primary", "url": link, "action_id": REGISTER_ACTION_ID,
                "text": {"type": "plain_text", "text": "PokeTokenBar 연결"},
            }]},
            {"type": "context", "elements": [{
                "type": "mrkdwn",
                "text": f"버튼이 안 되면 앱 설정에 이 토큰을 붙여 넣어 주세요: `{token}`",
            }]},
            {"type": "context", "elements": [{
                "type": "mrkdwn",
                "text": f"앱이 없으면 <{DOWNLOAD_URL}|여기서 받아요>.",
            }]},
        ]

    def _record(self, user_id: str) -> Reply:
        record = self._store.record(user_id)
        return Reply(f"<@{user_id}> 전적: {record.wins}승 {record.losses}패")

    def _dex(self, user_id: str, target_id: str) -> Reply:
        """The target's uploaded dex summary. In a thread the mention listener makes it visible; a slash reply is private."""
        who = f"<@{target_id}>"
        if target_id == self._bot_user_id:
            return Reply("YPoke는 도감이 없어요.")
        summary = self._store.dex(target_id)
        if summary is None:
            if not self._store.is_linked(target_id):
                hint = f" `{LINK_COMMAND}`로 연결해 주세요." if target_id == user_id else ""
                return Reply(f"{who}님은 아직 YPoke에 연결하지 않았어요.{hint}")
            return Reply(f"{who}님의 도감은 아직 올라오지 않았어요. 앱을 최신 버전으로 켜 두면 올라와요.")
        head = [
            f"📖 {who}님의 도감",
            f"전체 *{summary['owned']}*/{NATIONAL_TOTAL} · ✨ 이로치 *{summary['shiny']}*",
        ]
        representative = summary.get("representative")
        tail = []
        image_url = None
        if representative is not None:
            name = self._species_name(representative["pokemon_id"])
            tail = [f"대표 포켓몬: {name}{' ✨' if representative['shiny'] else ''}"]
            image_url = sprite_url(representative["pokemon_id"], representative["shiny"])
        return Reply(
            "\n".join(head + progress_lines(summary) + tail), image_url=image_url,
            fields=tuple(progress_fields(summary)), lead="\n".join(head + tail),
        )

    def _species_name(self, pokemon_id: int) -> str:
        try:
            return self._pokeapi.pokemon(pokemon_id)["name_ko"]
        except OSError:
            return f"#{pokemon_id}"

    def _ranking(self) -> Reply:
        start = week_start(self._now())
        records = self._store.records_since(start)
        if not records:
            return Reply("이번 주에는 아직 대결이 없어요.", in_channel=True)
        ranked = sorted(records.items(), key=lambda item: (
            -item[1].wins, -_win_rate(item[1]), item[1].wins + item[1].losses, item[0],
        ))[:RANKING_SIZE]
        monday = start.astimezone(KST)
        lines = [f"🏆 이번 주 랭킹 ({monday.month}/{monday.day} 월요일부터)"]
        for rank, (user_id, record) in enumerate(ranked, start=1):
            lines.append(
                f"{rank}. <@{user_id}> {record.wins}승 {record.losses}패 ({round(_win_rate(record) * 100)}%)"
            )
        return Reply("\n".join(lines), in_channel=True)

    def _start(
        self, challenger_id: str, opponent_id: str, where: Where | None, echo: str | None = None, size: int = 1
    ) -> Reply:
        """A battle against `opponent_id` with each side's first `size` Pokémon; against the bot it is a practice
        battle and nothing is stored."""
        try:
            match = self._prepare(challenger_id, opponent_id, size)
        except OSError:
            return Reply("포켓몬 정보를 불러오지 못했어요. 잠시 뒤 다시 해 주세요.")
        if match is None:
            return self._wait(challenger_id, opponent_id, where, echo, size)
        return self._result(match)

    def _wait(self, challenger_id: str, opponent_id: str, where: Where | None, echo: str | None, size: int) -> Reply:
        """Keep the challenge until both sides have uploaded, and send the side(s) without one the link button."""
        if where is not None:
            self._store.save_pending(PendingChallenge(
                challenger_id, opponent_id, where.channel_id, where.thread_ts, where.response_url, self._now(), echo,
                size,
            ))
        not_ready = [user for user in (challenger_id, opponent_id)
                     if user != self._bot_user_id and self._store.party(user) is None]
        prompts = tuple(prompt for user in not_ready
                        if (prompt := self._link_prompt(user, challenger_id, opponent_id)) is not None)
        opponent = self._label(opponent_id)
        if challenger_id in not_ready:
            text = (
                "아직 내 포켓몬이 YPoke에 없어요. DM의 연결 버튼을 누르고 회사 네트워크에서 앱을 한 번 켜 두면 "
                f"{opponent}과(와)의 대결이 바로 열려요. 24시간이 지나면 취소돼요."
            )
            if opponent_id in not_ready:
                text += f" {opponent}님도 아직 준비 전이라 연결 안내를 보냈어요."
            text += f" DM이 안 보이면 `{LINK_COMMAND}`를 써 주세요. 앱은 <{DOWNLOAD_URL}|여기서> 받아요."
            public = (
                f"<@{challenger_id}>님은 아직 YPoke에 포켓몬이 없어요. "
                "DM의 연결 버튼을 누르고 회사 네트워크에서 앱을 켜 두면 이 대결이 열려요."
            )
            return Reply(text, direct_messages=prompts, public=public)
        return Reply(
            f"{opponent}님은 아직 YPoke에 포켓몬이 없어서 연결 안내를 DM으로 보냈어요. "
            "준비되면 이 대결 결과를 여기에 올릴게요. 24시간이 지나면 취소돼요.",
            in_channel=True,
            direct_messages=prompts,
        )

    def _link_prompt(self, user_id: str, challenger_id: str, opponent_id: str) -> DirectMessage | None:
        """The /포켓몬연결 button for a challenge side with no upload, at most once per `PROMPT_INTERVAL`.

        The new token is added beside any existing one, so an app that is linked but offline keeps working.
        """
        now = self._now()
        if not self._store.mark_prompted(user_id, since=now - PROMPT_INTERVAL, at=now):
            return None
        token = self._store.issue_token(user_id, keep_existing=True)
        if user_id == challenger_id:
            intro = f"{self._label(opponent_id)}과(와)의 대결이 기다리고 있어요."
        else:
            intro = f"<@{challenger_id}>님이 YPoke 대결을 신청했어요."
        blocks = [
            {"type": "section", "text": {"type": "mrkdwn", "text": intro}},
            *self._link_blocks(token),
            {"type": "context", "elements": [{"type": "mrkdwn", "text": NETWORK_NOTE}]},
        ]
        return DirectMessage(user_id, intro, blocks)

    def _prepare(self, challenger_id: str, opponent_id: str, size: int) -> _Match | None:
        """Both sides' first `size` combatants, or None while a side has no upload. Raises OSError when PokéAPI is down."""
        challenger = self._store.party(challenger_id)
        if challenger is None:
            return None
        entry = challenger.party[:size]
        seed = secrets.randbits(31)
        if opponent_id == self._bot_user_id:
            wild = [{"pokemon_id": species, "level": member["level"], "shiny": False, "ivs": {}}
                    for species, member in zip(bot_entry(seed, len(entry)), entry)]
            return _Match(challenger_id, opponent_id, self._combatants(entry, wild), seed, practice=True,
                          pokemon=(entry[0]["pokemon_id"], wild[0]["pokemon_id"]), size=size)
        opponent = self._store.party(opponent_id)
        if opponent is None:
            return None
        rival = opponent.party[:size]
        return _Match(challenger_id, opponent_id, self._combatants(entry, rival), seed, practice=False,
                      pokemon=(entry[0]["pokemon_id"], rival[0]["pokemon_id"]), size=size)

    def _result(self, match: _Match) -> Reply:
        result = simulate(match.sides, match.seed)
        if not match.practice:
            winner_id = match.challenger_id if result.winner == 0 else match.opponent_id
            self._store.record_battle(
                match.challenger_id, match.opponent_id, winner_id, match.seed, pokemon=match.pokemon, turns=result.turns
            )
        trainers = (f"<@{match.challenger_id}>", self._label(match.opponent_id))
        summary = battle_header(trainers, match.sides, result, match.practice)
        return Reply(
            summary,
            in_channel=True,
            summary=summary,
            card=battle_card(trainers, match.sides, result, match.practice),
            rematch=f"{match.challenger_id}:{match.opponent_id}:{match.size}",
        )

    def _label(self, user_id: str | None) -> str:
        return f"<@{user_id}>" if user_id else "YPoke"

    def _combatants(
        self, challenger: list[dict], opponent: list[dict]
    ) -> tuple[tuple[Combatant, ...], tuple[Combatant, ...]]:
        first, second = rental_levels(challenger, opponent)
        with ThreadPoolExecutor(max_workers=len(first) + len(second)) as pool:
            combatants = tuple(pool.map(self._combatant, [*first, *second]))
        return combatants[:len(first)], combatants[len(first):]

    def _combatant(self, member: dict) -> Combatant:
        data = self._pokeapi.pokemon(member["pokemon_id"])
        learnable = self._pokeapi.attacking_moves(member["pokemon_id"], member["level"])
        ivs = {key: member["ivs"].get(key, DEFAULT_IV) for key in IV_KEYS}
        return Combatant(
            name=member.get("name") or data["name_ko"],
            level=min(member["level"], BATTLE_LEVEL),
            types=tuple(data["types"]),
            base=base_stats(data),
            ivs=BaseStats(**ivs),
            shiny=member["shiny"],
            moves=battle_moves(learnable, member.get("moves")),
            rental=member.get("rental", False),
            nature=member.get("nature"),
            ability=member.get("ability"),
            item=member.get("held_item"),
            mega=self._mega(member),
            pokemon_id=member["pokemon_id"],
        )

    def _mega(self, member: dict) -> MegaForm | None:
        form_id = mega_form_id(member.get("held_item"), member["pokemon_id"])
        if form_id is None:
            return None
        data = self._pokeapi.mega_form(form_id)
        return MegaForm(types=tuple(data["types"]), base=base_stats(data), ability=data["ability"],
                        ability_id=data["ability_id"])


def rental_levels(challenger: list[dict], opponent: list[dict]) -> tuple[list[dict], list[dict]]:
    """A rental takes the other side's lead level (the battle cap applies after); two rentals keep their own."""
    if challenger[0].get("rental") and not opponent[0].get("rental"):
        return [{**member, "level": opponent[0]["level"]} for member in challenger], opponent
    if opponent[0].get("rental") and not challenger[0].get("rental"):
        return challenger, [{**member, "level": challenger[0]["level"]} for member in opponent]
    return challenger, opponent


def parse_mention(text: str, bot_user_id: str | None) -> tuple[str | None, str]:
    """Return the slash command an `@YPoke …` message asks for, and its text without the bot's own mentions."""
    rest = _MENTION.sub(lambda match: "" if match.group(1) == bot_user_id else match.group(0), text)
    command = next((MENTION_WORDS[word] for word in rest.lower().split() if word in MENTION_WORDS), None)
    return command, rest.strip()


def battle_size(text: str) -> int:
    """3 when the battle text asks for the full lineup (`3`, `3:3`, `풀`), else 1."""
    words = _MENTION.sub(" ", text).split()
    return MAX_ENTRY_SIZE if any(word in FULL_ENTRY_WORDS for word in words) else 1


def reply_thread_ts(event: dict) -> str:
    """Answer inside the mention's thread; a top-level mention starts one."""
    return event.get("thread_ts") or event["ts"]


def bot_entry(seed: int, count: int) -> list[int]:
    return random.Random(seed).sample(range(1, MAX_SPECIES_ID + 1), count)


def week_start(now: datetime) -> datetime:
    """Monday 00:00 KST of the week containing `now`, in UTC."""
    local = now.astimezone(KST)
    monday = (local - timedelta(days=local.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    return monday.astimezone(UTC)


def _win_rate(record: Record) -> float:
    return record.wins / (record.wins + record.losses)


def command_echo(user_id: str, command: str, text: str) -> str:
    """Who ran which command: the command and its text in code, user mentions outside it so they stay mentions."""
    parts = [f"`{command}`"]
    for chunk in _MENTION_SPLIT.split(text[:ECHO_ARG_LIMIT]):
        mention = _MENTION.fullmatch(chunk)
        if mention:
            parts.append(f"<@{mention.group(1)}>")
            continue
        plain = re.sub(r"[`<>]", "", chunk).strip()
        if plain:
            parts.append(f"`{plain}`")
    return f"<@{user_id}> 님이 {' '.join(parts)} 을(를) 썼어요"


def _echoed(reply: Reply, echo: str | None) -> Reply:
    return replace(reply, echo=echo) if echo and (reply.in_channel or reply.public) else reply


def fallback_text(reply: Reply) -> str:
    """Notification text of a visible battle result."""
    return "\n".join(line for line in (reply.echo, reply.summary) if line)


def result_blocks(reply: Reply) -> list[dict]:
    """The whole battle message: echo and tags, the header with the winner's sprite, both lineups side by side,
    the rematch button, then the turn log as grey context blocks."""
    card = reply.card
    blocks: list[dict] = []
    context = [line for line in (reply.echo, card.note, PRACTICE_NOTE if card.practice else None) if line]
    if context:
        blocks.append({"type": "context", "elements": [{"type": "mrkdwn", "text": line} for line in context]})
    header = {"type": "section", "text": {"type": "mrkdwn", "text": fit(
        "\n".join([f"*{card.title}*", card.detail, *card.highlights]), SECTION_TEXT_LIMIT)}}
    if card.sprite:
        header["accessory"] = {"type": "image", "image_url": card.sprite[0], "alt_text": card.sprite[1]}
    blocks.append(header)
    blocks.append({"type": "section", "fields": [
        {"type": "mrkdwn", "text": fit(column, FIELD_TEXT_LIMIT)} for column in card.columns]})
    blocks.append({"type": "actions", "elements": [{
        "type": "button", "action_id": REMATCH_ACTION_ID, "value": reply.rematch,
        "text": {"type": "plain_text", "text": REMATCH_LABEL},
    }]})
    if card.log:
        blocks.append({"type": "divider"})
    blocks += [
        {"type": "context", "elements": [{"type": "mrkdwn", "text": fit(entry, SECTION_TEXT_LIMIT)}]}
        for entry in card.log
    ]
    return blocks


def message_blocks(reply: Reply, visible: bool) -> list[dict] | None:
    """Blocks of a plain reply: the lead (with the echo line when `visible`) and thumbnail, then the field grid."""
    if not reply.fields:
        text = "\n".join(filter(None, (reply.echo, reply.text))) if visible else reply.text
        return image_blocks(text, reply.image_url)
    lead = "\n".join(filter(None, (reply.echo if visible else None, reply.lead)))
    blocks = image_blocks(lead, reply.image_url) or [{"type": "section", "text": {"type": "mrkdwn", "text": fit(lead, SECTION_TEXT_LIMIT)}}]
    blocks.append({"type": "section", "fields": [{"type": "mrkdwn", "text": field} for field in reply.fields]})
    return blocks


def image_blocks(text: str, image_url: str | None) -> list[dict] | None:
    """`text` with a thumbnail beside it, or None when there is no image and the plain text is enough."""
    if image_url is None:
        return None
    return [{
        "type": "section", "text": {"type": "mrkdwn", "text": fit(text, SECTION_TEXT_LIMIT)},
        "accessory": {"type": "image", "image_url": image_url, "alt_text": "대표 포켓몬"},
    }]


def fit(text: str, limit: int) -> str:
    return text if len(text) <= limit else f"{text[:limit - 1]}…"
