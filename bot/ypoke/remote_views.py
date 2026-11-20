"""The private Slack views of a user's party, Box and bag, read from the bot's replayed view (`remote_ops.View`)."""

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from ypoke import battle_data
from ypoke.remote_ops import RemoteOps, View, describe
from ypoke.store import Store
from ypoke.trades import NATURE_NAMES_KO, option_labels

PARTY_COMMAND = "/파티"
BOX_COMMAND = "/박스"
BAG_COMMAND = "/가방"
SHOP_COMMAND = "/상점"
TRAINING_COMMAND = "/트레이닝"
TRADE_COMMAND = "/교환"
MIRACLE_COMMAND = "/미라클"
REMOTE_COMMANDS = (
    PARTY_COMMAND, BOX_COMMAND, BAG_COMMAND, SHOP_COMMAND, TRAINING_COMMAND, TRADE_COMMAND, MIRACLE_COMMAND,
)
REMOTE_WORDS = {command.removeprefix("/"): command for command in REMOTE_COMMANDS}
COMING_SOON = "곧 열려요."
NOT_LINKED = "아직 YPoke에 연결하지 않았어요. `/포켓몬연결`로 연결해 주세요."
NO_UPLOAD = "아직 YPoke에 올라온 포켓몬이 없어요. 회사 네트워크에서 앱을 한 번 켜 주세요."
OLD_APP_BAG = "앱을 업데이트하고 회사에서 한 번 켜 주면 잔액과 가방이 보여요."
BOX_BUTTON_NOTE = "버튼이 없는 포켓몬은 교환에 올렸거나, 파티에 같은 종·같은 도구가 있어요."
BOX_PAGE_SIZE = 25
SECTION_LIMIT = 2900
MAX_SECTIONS = 40
KST = timezone(timedelta(hours=9), "KST")


@dataclass(frozen=True)
class Screen:
    """A private reply: `text` is the notification fallback, `blocks` the message."""

    text: str
    blocks: list[dict]


class RemoteViews:
    def __init__(self, store: Store, remote: RemoteOps, species_name: Callable[[int], str]):
        self._store = store
        self._remote = remote
        self._species_name = species_name

    def handle(self, user_id: str, command: str, text: str) -> Screen:
        view = self._remote.view(user_id)
        if view is None:
            return _plain(NO_UPLOAD if self._store.is_linked(user_id) else NOT_LINKED)
        if command not in (PARTY_COMMAND, BOX_COMMAND, BAG_COMMAND):
            return text_screen([self._remote.edit_refusal(user_id) or COMING_SOON], view)
        if command == PARTY_COMMAND:
            return self._party(view)
        if command == BOX_COMMAND:
            return box_screen(view, text)
        return _bag(view)

    def _party(self, view: View) -> Screen:
        lines = [party_title(view)]
        for index, member in enumerate(view.party, start=1):
            lines += member_lines(index, member, member.get("name") or self._species_name(member["pokemon_id"]))
        return text_screen(lines, view)


def party_title(view: View) -> str:
    return f"*내 대결 파티* ({len(view.party)}마리)"


def member_lines(index: int, member: dict, name: str) -> list[str]:
    head = f"{index}. {name}{' ✨' if member.get('shiny') else ''} Lv.{member['level']}"
    if member.get("rental"):
        head += " (대여)"
    if member.get("item_name"):
        item = f"@{member['item_name']}"
    elif member.get("held_item"):
        item = f"@{_data_name('items', member.get('held_item')) or member['held_item']}"
    else:
        item = "도구 없음"
    traits = [
        NATURE_NAMES_KO.get(member.get("nature"), "성격 없음"),
        _data_name("abilities", member.get("ability")) or "특성 없음",
        item,
    ]
    moves = " / ".join(_data_name("moves", str(move_id)) or f"#{move_id}" for move_id in member.get("moves", []))
    return [head, f"    {' · '.join(traits)}", f"    기술: {moves or '레벨에 맞는 기본 기술'}"]


def box_screen(view: View, text: str, accessory: Callable[[dict], dict | None] | None = None) -> Screen:
    """Newest first. A trailing number picks the page; the rest of the text filters by name. With `accessory`, a
    name search lists each Pokémon in its own section with what `accessory` gives it (a button, or None)."""
    words = text.split()
    page = int(words.pop()) if words and words[-1].isdigit() else 1
    query = " ".join(words)
    labelled = list(zip(option_labels(view.pool), view.pool))
    if not labelled:
        return text_screen(["*내 박스*", "박스가 비어 있어요. 앱이 박스를 올리면 여기서 보여요."], view)
    if query:
        labelled = [(label, entry) for label, entry in labelled if query.lower() in entry["name"].lower()]
        if not labelled:
            return text_screen([f"*내 박스* '{query}' 검색", f"'{query}'에 맞는 포켓몬이 없어요."], view)
    pages = (len(labelled) + BOX_PAGE_SIZE - 1) // BOX_PAGE_SIZE
    page = min(max(page, 1), pages)
    start = (page - 1) * BOX_PAGE_SIZE
    title = f"*내 박스* '{query}' 검색 {len(labelled):,}마리" if query else f"*내 박스* {len(labelled):,}마리"
    lines = [f"{title} · {page}/{pages}쪽"]
    shown = labelled[start:start + BOX_PAGE_SIZE]
    lines += [f"{start + offset}. {label}" for offset, (label, _) in enumerate(shown, 1)]
    next_page = f"다음 쪽: `{BOX_COMMAND} {query + ' ' if query else ''}{page + 1}`" if page < pages else None
    if query and accessory is not None:
        return _box_with_buttons(lines[0], [(line, accessory(entry)) for line, (_, entry) in zip(lines[1:], shown)],
                                 next_page, view)
    if next_page:
        lines.append(next_page)
    return text_screen(lines, view)


def _box_with_buttons(title: str, rows: list[tuple[str, dict | None]], next_page: str | None, view: View) -> Screen:
    blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": title}}]
    for line, accessory in rows:
        section = {"type": "section", "text": {"type": "mrkdwn", "text": line}}
        blocks.append(section | {"accessory": accessory} if accessory else section)
    footer = [text for text in (BOX_BUTTON_NOTE, next_page, sync_line(view)) if text]
    blocks.append({"type": "context", "elements": [{"type": "mrkdwn", "text": text} for text in footer]})
    return Screen("\n".join([title, sync_line(view)]), blocks)


def sync_line(view: View) -> str:
    return f"회사에서 마지막으로 동기화: {_kst(view.uploaded_at)}"


def _bag(view: View) -> Screen:
    lines = ["*내 가방*"]
    if not view.remote_ops:
        lines.append(OLD_APP_BAG)
    else:
        lines.append(f"쓸 수 있는 토큰: {view.wallet:,}" if view.wallet is not None else "쓸 수 있는 토큰: 알 수 없음")
        items = sorted(view.bag, key=lambda line: line["name"])
        lines += [f"• {line['name']} ×{line['count']}" for line in items] or ["가방이 비어 있어요."]
    lines.append("*대기 중인 슬랙 작업*")
    lines += [f"{index}. {describe(op.kind, op.payload)}" for index, op in enumerate(view.pending, 1)] or ["없어요."]
    return text_screen(lines, view)


def _plain(text: str) -> Screen:
    return Screen(text, [{"type": "section", "text": {"type": "mrkdwn", "text": text}}])


def text_screen(lines: list[str], view: View) -> Screen:
    """Lines in as many sections as they need, then when the snapshot was taken."""
    blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": chunk}} for chunk in _chunks(lines)]
    stamp = sync_line(view)
    blocks.append({"type": "context", "elements": [{"type": "mrkdwn", "text": stamp}]})
    return Screen("\n".join([lines[0], stamp]), blocks)


def _chunks(lines: list[str]) -> list[str]:
    chunks: list[str] = []
    current: list[str] = []
    for line in lines:
        if current and len("\n".join([*current, line])) > SECTION_LIMIT:
            chunks.append("\n".join(current))
            current = []
        current.append(line[:SECTION_LIMIT])
    if current:
        chunks.append("\n".join(current))
    if len(chunks) > MAX_SECTIONS:
        hidden = sum(chunk.count("\n") + 1 for chunk in chunks[MAX_SECTIONS - 1:])
        chunks = [*chunks[:MAX_SECTIONS - 1], f"…외 {hidden}줄"]
    return chunks


def _kst(stamp: str) -> str:
    local = datetime.fromisoformat(stamp).astimezone(KST)
    return f"{local.month}월 {local.day}일 {local:%H:%M}"


def ability_name(key: str) -> str:
    return _data_name("abilities", key) or key


def _data_name(kind: str, key: str | None) -> str | None:
    if not key:
        return None
    return battle_data.table(kind).get(key, {}).get("names", {}).get("ko")
