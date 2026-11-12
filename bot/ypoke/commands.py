"""Slash command logic, independent of Slack transport."""

import random
import re
import secrets
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta, timezone
from urllib.parse import urlencode

from ypoke.battle import BaseStats, Combatant, simulate
from ypoke.narration import battle_lines
from ypoke.pokeapi import PokeAPIService, base_stats
from ypoke.store import Record, Store
from ypoke.upload_server import IV_KEYS

DEFAULT_IV = 15
REGISTER_LINK = "poketokenbar://ypoke-register"
DOWNLOAD_URL = "https://github.com/w8385/PokeTokenBar-yp/releases/latest"
REGISTER_ACTION_ID = "open_poketokenbar"
_MENTION = re.compile(r"<@([UW][A-Z0-9]+)(?:\|[^>]*)?>")
KST = timezone(timedelta(hours=9), "KST")
MAX_SPECIES_ID = 1025
_BOT_BATTLE_WORDS = {"대결", "battle"}
RANKING_SIZE = 10

BATTLE_COMMAND = "/대결"
LINK_COMMAND = "/포켓몬연결"
RECORD_COMMAND = "/전적"
RANKING_COMMAND = "/랭킹"
UMBRELLA_COMMAND = "/ypoke"
COMMAND_NAMES = (BATTLE_COMMAND, LINK_COMMAND, RECORD_COMMAND, RANKING_COMMAND, UMBRELLA_COMMAND)

HELP_TEXT = (
    "*YPoke 대결*\n"
    f"`{BATTLE_COMMAND} @상대` 서로 지금 키우는 포켓몬끼리 1:1로 한 판 붙어요. 결과는 이 채널에 올라가요.\n"
    f"`{BATTLE_COMMAND} @YPoke` 또는 `@YPoke 대결` 봇이 내보낸 포켓몬과 연습 대결을 해요. 전적에 안 남아요.\n"
    f"`{LINK_COMMAND}` 앱 연결 링크를 DM으로 보내요. 다시 하면 새 링크가 나오고 옛 연결은 끊겨요.\n"
    f"`{RECORD_COMMAND} [@누구]` 승패를 보여줘요.\n"
    f"`{RANKING_COMMAND}` 이번 주(월요일 0시부터) 승리 순위를 이 채널에 올려요.\n"
    "전적만 남고 포켓몬은 오가지 않아요.\n"
    f"앱 받기: <{DOWNLOAD_URL}|PokeTokenBar>"
)


@dataclass(frozen=True)
class Reply:
    text: str
    in_channel: bool = False
    direct_message: str | None = None
    direct_message_blocks: list[dict] | None = None


class CommandHandler:
    def __init__(
        self,
        store: Store,
        pokeapi: PokeAPIService,
        public_url: str | None = None,
        now: Callable[[], datetime] = lambda: datetime.now(UTC),
        bot_user_id: str | None = None,
    ):
        self._store = store
        self._pokeapi = pokeapi
        self._public_url = public_url
        self._now = now
        self._bot_user_id = bot_user_id

    def handle(self, user_id: str, text: str, command: str = BATTLE_COMMAND) -> Reply:
        mention = _MENTION.search(text)
        if command == LINK_COMMAND:
            return self._register(user_id)
        if command == RECORD_COMMAND:
            return self._record(mention.group(1) if mention else user_id)
        if command == RANKING_COMMAND:
            return self._ranking()
        if command == BATTLE_COMMAND and mention:
            if mention.group(1) == self._bot_user_id:
                return self._bot_battle(user_id)
            return self._battle(user_id, mention.group(1))
        return Reply(HELP_TEXT)

    def handle_mention(self, user_id: str, text: str) -> Reply:
        """An `@YPoke …` message in a channel."""
        if _BOT_BATTLE_WORDS & set(text.lower().split()):
            return self._bot_battle(user_id)
        return Reply(HELP_TEXT)

    def _register(self, user_id: str) -> Reply:
        token = self._store.issue_token(user_id)
        query = {"token": token}
        if self._public_url:
            query["server"] = self._public_url
        link = f"{REGISTER_LINK}?{urlencode(query)}"
        blocks = [
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
        return Reply(
            "DM으로 연결 링크를 보냈어요.",
            direct_message="PokeTokenBar를 YPoke에 연결하세요.",
            direct_message_blocks=blocks,
        )

    def _record(self, user_id: str) -> Reply:
        record = self._store.record(user_id)
        return Reply(f"<@{user_id}> 전적: {record.wins}승 {record.losses}패")

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

    def _battle(self, challenger_id: str, opponent_id: str) -> Reply:
        if challenger_id == opponent_id:
            return Reply("자기 자신과는 대결할 수 없어요.")
        challenger_party = self._store.party(challenger_id)
        if challenger_party is None:
            return self._no_party_reply()
        opponent_party = self._store.party(opponent_id)
        if opponent_party is None:
            return Reply(f"<@{opponent_id}>님은 아직 파티를 올리지 않았어요.")
        try:
            sides = (self._combatants(challenger_party.party[:1]), self._combatants(opponent_party.party[:1]))
        except OSError:
            return Reply("포켓몬 정보를 불러오지 못했어요. 잠시 뒤 다시 해 주세요.")
        seed = secrets.randbits(31)
        result = simulate(sides, seed)
        winner_id = challenger_id if result.winner == 0 else opponent_id
        self._store.record_battle(challenger_id, opponent_id, winner_id, seed)
        lines = battle_lines((f"<@{challenger_id}>", f"<@{opponent_id}>"), (sides[0][0], sides[1][0]), result)
        return Reply("\n".join(lines), in_channel=True)

    def _bot_battle(self, challenger_id: str) -> Reply:
        """Practice battle against a seeded random species at the challenger's level; nothing is stored."""
        challenger_party = self._store.party(challenger_id)
        if challenger_party is None:
            return self._no_party_reply()
        seed = secrets.randbits(31)
        try:
            challenger = self._combatants(challenger_party.party[:1])[0]
            data = self._pokeapi.pokemon(bot_species(seed))
        except OSError:
            return Reply("포켓몬 정보를 불러오지 못했어요. 잠시 뒤 다시 해 주세요.")
        wild = Combatant(
            name=data["name_ko"],
            level=challenger.level,
            types=tuple(data["types"]),
            base=base_stats(data),
            ivs=BaseStats(*[DEFAULT_IV] * len(IV_KEYS)),
        )
        result = simulate(([challenger], [wild]), seed)
        bot = f"<@{self._bot_user_id}>" if self._bot_user_id else "YPoke"
        lines = battle_lines((f"<@{challenger_id}>", bot), (challenger, wild), result, practice=True)
        return Reply("\n".join(lines), in_channel=True)

    def _no_party_reply(self) -> Reply:
        return Reply(
            f"아직 내 파티가 없어요. `{LINK_COMMAND}` 로 앱을 연결하면 파티가 올라와요. "
            f"앱은 <{DOWNLOAD_URL}|여기서> 받아요."
        )

    def _combatants(self, party: list[dict]) -> list[Combatant]:
        pokemon_ids = list({member["pokemon_id"] for member in party})
        with ThreadPoolExecutor(max_workers=len(pokemon_ids)) as pool:
            species = dict(zip(pokemon_ids, pool.map(self._pokeapi.pokemon, pokemon_ids)))
        combatants = []
        for member in party:
            data = species[member["pokemon_id"]]
            ivs = {key: member["ivs"].get(key, DEFAULT_IV) for key in IV_KEYS}
            combatants.append(Combatant(
                name=member.get("name") or data["name_ko"],
                level=member["level"],
                types=tuple(data["types"]),
                base=base_stats(data),
                ivs=BaseStats(**ivs),
                shiny=member["shiny"],
            ))
        return combatants


def bot_species(seed: int) -> int:
    return random.Random(seed).randint(1, MAX_SPECIES_ID)


def week_start(now: datetime) -> datetime:
    """Monday 00:00 KST of the week containing `now`, in UTC."""
    local = now.astimezone(KST)
    monday = (local - timedelta(days=local.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    return monday.astimezone(UTC)


def _win_rate(record: Record) -> float:
    return record.wins / (record.wins + record.losses)
