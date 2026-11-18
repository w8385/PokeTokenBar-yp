"""Battle result card and turn log, built only from events the simulation produced."""

from collections.abc import Sequence
from dataclasses import dataclass, field

from ypoke.abilities import NAMES as ABILITY_NAMES
from ypoke.battle import (
    BATTLE_LEVEL, AbilityField, AbilityTrigger, Action, BattleResult, Change, Combatant, Event, FieldEnd, FieldStart,
    FormShift, HazardDamage, HazardHit, ItemEffect, ItemHeal, MegaEvolution, SendOut, StatusDamage, TerrainHeal,
    TrickRoomEnd, VolatileEnd, VolatileTick, WeatherDamage, WeatherEnd, YawnSleep,
)
from ypoke.dex import bar, sprite_url
from ypoke.items import ITEM_NAMES, known

MAX_LOG_BLOCKS = 44
MAX_TAGS = 2
PRACTICE_NOTE = "연습 대결"
SKIPPED_MARK = "⋯"
SIDE_MARKERS = ("🔵", "🔴")
FAINTED = "💥"
FAINTED_TAG = "쓰러짐"
WAITING = "대기"
WEATHER_ICON = {"sun": "☀️", "rain": "☔", "sandstorm": "🏜️", "hail": "🌨️", "snow": "❄️", "strong-winds": "🌀난기류"}
STATUS_ICON = {
    "burn": "🔥화상", "paralysis": "⚡마비", "poison": "☠️독", "toxic": "☠️맹독", "sleep": "💤잠듦",
    "freeze": "🧊얼음", "confusion": "💫혼란",
}
RESIDUAL_ICON = {"burn": "🔥", "poison": "☠️", "toxic": "☠️"}
STATE_LABEL = {
    "electric-terrain": "⚡일렉트릭필드", "grassy-terrain": "🌿그래스필드", "psychic-terrain": "🔮사이코필드",
    "misty-terrain": "🌫️미스트필드", "reflect": "🛡️리플렉터", "light-screen": "🛡️빛의장막", "aurora-veil": "🛡️오로라베일",
    "stealth-rock": "🪨스텔스록", "spikes": "📌압정", "toxic-spikes": "☠️독압정", "sticky-web": "🕸️끈적끈적네트",
    "tailwind": "🍃순풍", "safeguard": "✨신비의부적", "mist": "🌁흰안개", "lucky-chant": "🍀주술", "gravity": "🌍중력",
}
BLOCKED_TAG = {
    "paralysis": "⚡몸이 저려 못 움직임", "sleep": "💤자는 중", "freeze": "🧊얼어서 못 움직임",
    "gravity": "🌍중력 때문에 기술을 못 씀", "psychic-terrain": "🔮사이코필드에 막힘",
    "protect": "🛡️방어에 막힘", "kings-shield": "🛡️킹실드에 막힘", "spiky-shield": "🌵니들가드에 막힘",
    "baneful-bunker": "☠️토치카에 막힘", "obstruct": "🛡️블로킹에 막힘", "silk-trap": "🕸️실크트랩에 막힘",
    "burning-bulwark": "🔥화염의수호에 막힘", "mat-block": "🛡️마룻바닥세워막기에 막힘",
    "quick-guard": "🛡️퍼스트가드에 막힘", "crafty-shield": "🛡️트릭가드에 막힘", "substitute": "🧸대타에 막힘",
}
RECOVERED_TAG = {"sleep": "💤깸", "freeze": "🧊풀림", "confusion": "💫풀림"}
FORM_CAPTION = {
    "mask": "가면", "terastal": "테라스탈폼", "stellar": "스텔라폼", "origin": "오리진폼", "crowned-sword": "검왕의모습",
    "crowned-shield": "방패왕의모습",
}
ITEM_EFFECT_TEXT = {"cure": "상태 회복", "restore": "능력 회복", "first": "선제공격", "burn": "🔥화상", "toxic": "☠️맹독"}
TRICK_ROOM_ICON = "🔀"
ROCK_ICON = "🪨"
EFFECT_TEXT = {
    "trick-room": f"{TRICK_ROOM_ICON}공간이 뒤틀렸다", "trick-room-off": f"{TRICK_ROOM_ICON}공간이 돌아왔다",
    "stealth-rock": f"{ROCK_ICON}상대 쪽에 돌이 떠 있다", "swords-dance": "⚔️공격이 크게 올랐다",
    "electric-terrain": "⚡일렉트릭필드가 깔렸다", "grassy-terrain": "🌿그래스필드가 깔렸다",
    "psychic-terrain": "🔮사이코필드가 깔렸다", "misty-terrain": "🌫️미스트필드가 깔렸다",
    "reflect": "🛡️물리 피해가 줄어든다", "light-screen": "🛡️특수 피해가 줄어든다", "aurora-veil": "🛡️받는 피해가 줄어든다",
    "spikes": "📌상대 쪽에 압정이 깔렸다", "toxic-spikes": "☠️상대 쪽에 독압정이 깔렸다",
    "sticky-web": "🕸️상대 쪽에 끈적끈적네트가 깔렸다", "tailwind": "🍃순풍이 분다",
    "safeguard": "✨상태이상을 막는다", "mist": "🌁능력이 떨어지지 않는다", "lucky-chant": "🍀급소를 막는다",
    "gravity": "🌍중력이 강해졌다", "haze": "🌫️모든 능력 변화가 사라졌다", "defog": "💨안개를 걷어냈다",
    "court-change": "🔄양쪽 필드를 바꿨다", "tidy-up": "🧹주변을 정리했다 (공격·스피드↑)",
    "psych-up": "🪞상대의 능력 변화를 따라 했다", "topsy-turvy": "🙃상대의 능력 변화가 뒤집혔다",
    "stage-swap": "🔁상대와 능력 변화를 바꿨다", "stat-swap": "🔁능력치가 바뀌었다",
    "wish": "🌠소원을 빌었다", "aqua-ring": "💧물의 고리를 둘렀다", "ingrain": "🌱뿌리를 박았다",
    "heal-bell": "🔔동료의 상태이상이 나았다", "healing-wish": "🌙몸을 바쳐 다음 동료를 회복시킨다",
    "memento": "🖤몸을 바쳤다 →", "revival-blessing": "✨",
    **dict.fromkeys(("protect", "kings-shield", "spiky-shield", "baneful-bunker", "obstruct", "silk-trap",
                     "burning-bulwark", "mat-block"), "🛡️방어 태세"),
    "quick-guard": "🛡️선제공격을 막는다", "crafty-shield": "🛡️변화 기술을 막는다", "endure": "💪버티기 태세",
    "substitute": "🧸대타를 세웠다", "shed-tail": "🧸꼬리를 잘라 대타를 남겼다",
}
# Effects whose line shows HP after the move: the attacker's, or the defender's ({foe} {defender}%).
HP_TEXT = {
    "heal": "💚{attacker}%", "rest": "💚{attacker}%", "heal-foe": "→ {foe} 💚{defender}%",
    "pain-split": "→ 체력을 나눴다 {attacker}% · {foe} {defender}%",
}
FORM_CHANGE = {"mega": ("메가진화", "메가"), "primal": ("원시회귀", "원시"), "ultra": ("울트라버스트", "울트라")}
STAT_SHORT = {
    "attack": "공격", "defense": "방어", "special_attack": "특공", "special_defense": "특방", "speed": "스피드",
    "accuracy": "명중", "evasion": "회피",
}
CHANGES_IN_TEXT = frozenset({"swords-dance", "tidy-up"})
VOLATILE_LABEL = {
    "wish": "🌠소원", "aqua-ring": "💧물의고리", "ingrain": "🌱뿌리박기", "healing-wish": "🌙치유소원",
    "substitute": "🧸대타", "shed-tail": "🧸대타 이어받음",
}
VOLATILE_END_TEXT = {"substitute": "부서졌다"}


Image = tuple[str, str]


@dataclass(frozen=True)
class Card:
    """What the result message shows. `log` is one mrkdwn text per turn (`*N턴*` then one action per line)
    and a `⋯ N턴 생략` text for each gap; `log_images` holds, per log text, the Mega form images shown beside it;
    `highlights` is the deciding knockout of a full-lineup battle."""

    columns: tuple[str, str]
    title: str = ""
    detail: str = ""
    highlights: tuple[str, ...] = ()
    log: tuple[str, ...] = ()
    sprite: tuple[str, str] | None = None
    log_images: tuple[tuple[Image, ...], ...] = ()
    practice: bool = False
    note: str | None = None


def battle_header(
    trainers: tuple[str, str], sides: tuple[Sequence[Combatant], Sequence[Combatant]], result: BattleResult,
    practice: bool = False,
) -> str:
    """`🏆 <winner> 승 · 3:3 · 9턴`; `trainers` are Slack mentions (or "YPoke"), challenger first."""
    header = f"{_title(trainers, result)} · {_detail(sides, result)}"
    return f"{header} · {PRACTICE_NOTE}" if practice else header


def battle_card(
    trainers: tuple[str, str], sides: tuple[Sequence[Combatant], Sequence[Combatant]], result: BattleResult,
    practice: bool = False,
) -> Card:
    megas = {(event.side, event.pokemon): event.kind for event in result.events if isinstance(event, MegaEvolution)}
    columns = tuple(
        _column(side, trainers[side], roster, result.remaining[side] if side < len(result.remaining) else (), megas)
        for side, roster in enumerate(sides)
    )
    decisive = _decisive_line(result) if len(sides[0]) > 1 or len(sides[1]) > 1 else None
    entries = _log_entries(result, MAX_LOG_BLOCKS)
    return Card(
        columns, _title(trainers, result), _detail(sides, result), (decisive,) if decisive else (),
        tuple(text for text, _ in entries), _winner_sprite(sides[result.winner], result),
        tuple(images for _, images in entries), practice,
    )


def _title(trainers: tuple[str, str], result: BattleResult) -> str:
    return f"🏆 {trainers[result.winner]} 승"


def _detail(sides: tuple[Sequence[Combatant], Sequence[Combatant]], result: BattleResult) -> str:
    return f"{len(sides[0])}:{len(sides[1])} · {result.turns}턴"


def _winner_sprite(roster: Sequence[Combatant], result: BattleResult) -> tuple[str, str] | None:
    """The image URL and name of the winner's Pokémon that was still standing last."""
    hps = result.remaining[result.winner] if result.winner < len(result.remaining) else ()
    standing = [index for index, hp in enumerate(hps) if hp and index < len(roster)]
    if not standing or roster[standing[-1]].pokemon_id is None:
        return None
    member = roster[standing[-1]]
    return sprite_url(member.pokemon_id, member.shiny), member.name


def _column(side: int, trainer: str, roster: Sequence[Combatant], hps: Sequence[int | None],
            megas: dict[tuple[int, str], str]) -> str:
    lines = [f"{SIDE_MARKERS[side]} *{trainer}*"]
    for index, member in enumerate(roster):
        hp = hps[index] if index < len(hps) else None
        label = _member_label(member, megas.get((side, member.name)))
        if hp is None:
            lines.append(f"{label} {WAITING}")
        elif hp == 0:
            lines.append(f"{label} {FAINTED}")
        else:
            lines.append(f"{label} {bar(hp, 100)} {hp}%")
    return "\n".join(lines)


def _member_label(member: Combatant, mega: str | None) -> str:
    label = member.name
    if member.shiny:
        label += "✨"
    if member.rental:
        label += "(대여)"
    if mega:
        label += f"({FORM_CHANGE[mega][1]})"
    if member.level != BATTLE_LEVEL:
        label += f" Lv{member.level}"
    if known(member.item):
        label += f" @{ITEM_NAMES[member.item]}"
    return label


def _decisive_line(result: BattleResult) -> str | None:
    """The faint that ended the battle; none when the turn limit ended it."""
    loser = 1 - result.winner
    if not (result.remaining and result.remaining[loser] and all(hp == 0 for hp in result.remaining[loser])):
        return None
    event = next((event for event in reversed(result.events) if _faint_side(event) == loser), None)
    if event is None:
        return None
    return f"{FAINTED} 결정타 {_decisive_text(event)}"


def _decisive_text(event: Event) -> str:
    if isinstance(event, Action):
        return f"{event.attacker} 💫혼란 자해" if event.blocked == "confusion" else f"{event.attacker} {event.move}"
    if isinstance(event, ItemHeal):
        return f"{event.pokemon} @{ITEM_NAMES[event.item]}"
    if isinstance(event, HazardDamage):
        return f"{event.pokemon} {ROCK_ICON}스텔스록"
    if isinstance(event, HazardHit):
        return f"{event.pokemon} {STATE_LABEL[event.hazard]}"
    if isinstance(event, VolatileTick):
        return f"{event.pokemon} {VOLATILE_LABEL[event.kind]}"
    icon = RESIDUAL_ICON[event.kind] if isinstance(event, StatusDamage) else WEATHER_ICON[event.weather]
    return f"{event.pokemon} {icon}"


def _faint_side(event: Event) -> int | None:
    """The side whose Pokémon fainted from this event, if any (a knockout and the attacker's own faint)."""
    if isinstance(event, Action):
        if event.knockout:
            return 1 - event.side
        return event.side if event.attacker_fainted else None
    if isinstance(event, (StatusDamage, WeatherDamage, ItemHeal, HazardDamage, HazardHit, VolatileTick)) and event.fainted:
        return event.side
    return None


@dataclass
class _Turn:
    number: int
    lines: list[str]
    essential: bool = False
    images: list[Image] = field(default_factory=list)

    def render(self) -> str:
        return "\n".join([f"*{self.number}턴*", *self.lines])


def battle_log(result: BattleResult, budget: int = MAX_LOG_BLOCKS) -> tuple[str, ...]:
    """One text per turn. When the turns do not fit `budget` blocks, the first and last `ends` turns stay with
    every turn that has a faint or a send-out, and each gap becomes one `⋯ N턴 생략` text."""
    return tuple(text for text, _ in _log_entries(result, budget))


def _log_entries(result: BattleResult, budget: int) -> list[tuple[str, tuple[Image, ...]]]:
    turns = _turns(result.events)
    ends = len(turns)
    while True:
        entries = _entries(turns, ends)
        if len(entries) <= budget or ends <= 1:
            return entries
        ends -= 1


def battle_turns(result: BattleResult) -> list[tuple[int, list[str]]]:
    """Every turn's log lines in order; unlike `battle_log` no turn is left out."""
    return [(turn.number, turn.lines) for turn in _turns(result.events)]


def split_side(line: str) -> tuple[int | None, str]:
    """The side a log line is about (0 or 1, None when it names no side) and the line without its marker."""
    arrow = "↪ " if line.startswith("↪ ") else ""
    body = line.removeprefix(arrow)
    for side, marker in enumerate(SIDE_MARKERS):
        if body.startswith(marker):
            return side, f"{arrow}{body.removeprefix(marker).lstrip()}"
    return None, line


def _entries(turns: list[_Turn], ends: int) -> list[tuple[str, tuple[Image, ...]]]:
    entries: list[tuple[str, tuple[Image, ...]]] = []
    skipped = 0
    for index, turn in enumerate(turns):
        if index < ends or index >= len(turns) - ends or turn.essential:
            if skipped:
                entries.append((f"{SKIPPED_MARK} {skipped}턴 생략", ()))
                skipped = 0
            entries.append((turn.render(), tuple(turn.images)))
        else:
            skipped += 1
    return entries


def _turns(events: list[Event]) -> list[_Turn]:
    """Group events by turn. Entry events (no turn of their own) join the send-out they directly follow;
    those before any turn open turn 1."""
    turns: list[_Turn] = []
    opening: list[str] = []
    opening_images: list[Image] = []
    sent: dict[int, int] = {}
    for event in events:
        if isinstance(event, FormShift):
            (turns[-1].lines if turns else opening).append(_form_line(event))
            if event.form_id is not None:
                (turns[-1].images if turns else opening_images).append(
                    (sprite_url(event.form_id, False), f"{event.pokemon} {FORM_CAPTION[event.kind]}"))
            continue
        if isinstance(event, (AbilityTrigger, MegaEvolution)):
            current = turns[-1].lines if turns else opening
            if event.side in sent:
                current[sent[event.side]] += f" {_entry_effect(event)}"
            else:
                current.append(_entry_segment(event))
            if isinstance(event, MegaEvolution) and event.form_id is not None:
                (turns[-1].images if turns else opening_images).append(
                    (sprite_url(event.form_id, False), f"{event.pokemon} {FORM_CHANGE[event.kind][0]}"))
            continue
        if not isinstance(event, SendOut):
            sent = {}
        if not turns or turns[-1].number != event.turn:
            turns.append(_Turn(event.turn, opening, images=opening_images))
            opening, opening_images = [], []
        turn = turns[-1]
        lines = _event_lines(event)
        if isinstance(event, SendOut):
            sent[event.side] = len(turn.lines)
            turn.essential = True
        elif _faint_side(event) is not None:
            turn.essential = True
        turn.lines += lines
    return turns


def _form_line(event: FormShift) -> str:
    marker = SIDE_MARKERS[event.side]
    if event.kind == "mask":
        tag = _change_tag(event.change, event.side)
        return f"{marker} {event.pokemon}의 가면이 빛났다!{f' {tag}' if tag else ''}"
    return f"{marker} {event.pokemon}{_topic_particle(event.pokemon)} {FORM_CAPTION[event.kind]}이 되었다!"


def _topic_particle(name: str) -> str:
    last = ord(name[-1])
    if not 0xAC00 <= last <= 0xD7A3:
        return "은(는)"
    return "은" if (last - 0xAC00) % 28 else "는"


def _entry_effect(event: AbilityTrigger | MegaEvolution) -> str:
    if isinstance(event, MegaEvolution):
        word = FORM_CHANGE[event.kind][0]
        return f"{word} [{event.ability}]" if event.ability else word
    if isinstance(event, AbilityField) and event.terrain:
        effect = STATE_LABEL[event.terrain]
    elif isinstance(event, AbilityField):
        effect = f"{'·'.join(STATE_LABEL[key] for key in event.cleared)} 사라짐"
    else:
        effect = WEATHER_ICON[event.weather] if event.weather else _change_tag(event.change, event.side)
    return f"[{ABILITY_NAMES[event.ability]}] {effect}"


def _entry_segment(event: AbilityTrigger | MegaEvolution) -> str:
    return f"{SIDE_MARKERS[event.side]} {event.pokemon} {_entry_effect(event)}"


def _event_lines(event: Event) -> list[str]:
    """The log lines of one event: what happened, then a faint line for each Pokémon the line does not already
    show fainting (an attack's knocked-out target ends its line with 💥)."""
    if isinstance(event, WeatherEnd):
        return [f"{WEATHER_ICON[event.weather]}끝"]
    if isinstance(event, TrickRoomEnd):
        return [f"{TRICK_ROOM_ICON}트릭룸 끝"]
    if isinstance(event, FieldEnd):
        side = f"{SIDE_MARKERS[event.side]} " if event.side >= 0 else ""
        return [f"{side}{STATE_LABEL[event.kind]} {f'사라짐 ({event.move})' if event.move else '끝'}"]
    marker = SIDE_MARKERS[event.side]
    if isinstance(event, SendOut):
        return [f"↪ {marker} {event.pokemon} 등장"]
    if isinstance(event, HazardDamage):
        return [f"{marker} {event.pokemon} {ROCK_ICON}스텔스록 {event.hp}%",
                *([_faint_line(event.pokemon)] if event.fainted else [])]
    if isinstance(event, FieldStart):
        return [f"{marker} 쪽에 {STATE_LABEL[event.kind]} 깔림"]
    if isinstance(event, HazardHit):
        return [_hazard_line(event, marker), *([_faint_line(event.pokemon)] if event.fainted else [])]
    if isinstance(event, TerrainHeal):
        return [f"{marker} {event.pokemon} {STATE_LABEL['grassy-terrain']} {event.hp}%"]
    if isinstance(event, YawnSleep):
        return [f"{marker} {event.pokemon} 💤잠듦 (하품)"]
    if isinstance(event, (StatusDamage, WeatherDamage)):
        icon = RESIDUAL_ICON[event.kind] if isinstance(event, StatusDamage) else WEATHER_ICON[event.weather]
        return [f"{marker} {event.pokemon} {icon} {event.hp}%", *([_faint_line(event.pokemon)] if event.fainted else [])]
    if isinstance(event, ItemHeal):
        return [f"{marker} {event.pokemon} @{ITEM_NAMES[event.item]} {event.hp}%",
                *([_faint_line(event.pokemon)] if event.fainted else [])]
    if isinstance(event, ItemEffect):
        return [f"{marker} {event.pokemon} @{ITEM_NAMES[event.item]} {ITEM_EFFECT_TEXT[event.effect]}"]
    if isinstance(event, VolatileTick):
        shown = f"{event.count}" if event.count is not None else f"{event.hp}%"
        return [f"{marker} {event.pokemon} {VOLATILE_LABEL[event.kind]} {shown}",
                *([_faint_line(event.pokemon)] if event.fainted else [])]
    if isinstance(event, VolatileEnd):
        return [f"{marker} {event.pokemon} {VOLATILE_LABEL[event.kind]} {VOLATILE_END_TEXT.get(event.kind, '끝')}"]
    lines = [_action_line(event, marker)]
    if event.attacker_fainted:
        lines.append(_faint_line(event.attacker))
    return lines


def _hazard_line(event: HazardHit, marker: str) -> str:
    head = f"{marker} {event.pokemon} {STATE_LABEL[event.hazard]}"
    if event.cleared:
        return f"{head} 흡수"
    return f"{head} {_change_tag(event.change, event.side)}" if event.change else f"{head} {event.hp}%"


def _faint_line(name: str) -> str:
    return f"{FAINTED} {name} {FAINTED_TAG}"


def _action_line(event: Action, marker: str) -> str:
    head = " ".join([marker, event.attacker, *(RECOVERED_TAG[kind] for kind in event.recovered)])
    if event.blocked == "confusion":
        return f"{head} 💫혼란 자해 {event.attacker_hp}%"
    if event.blocked and event.move:
        tags = [_change_tag(change, event.side) for change in event.changes]
        return " ".join([f"{head} › {event.move} → {BLOCKED_TAG[event.blocked]}", *tags])
    if event.blocked:
        return f"{head} {BLOCKED_TAG[event.blocked]}"
    head = f"{head} › {event.move}"
    if event.failed and event.weather:
        return f"{head} → 실패 ({WEATHER_ICON[event.weather]})"
    if event.weather:
        return f"{head} {WEATHER_ICON[event.weather]}"
    if event.effect == "yawn":
        return f"{head} → {event.defender} 졸음"
    if event.effect == "thunder-wave":
        return f"{head} → {event.defender} {STATUS_ICON['paralysis']}"
    if event.effect in HP_TEXT:
        text = HP_TEXT[event.effect].format(attacker=event.attacker_hp, defender=event.defender_hp, foe=event.defender)
        return " ".join([head, text, *(_change_tag(change, event.side) for change in event.changes)])
    if event.effect in CHANGES_IN_TEXT or event.effect and not event.changes:
        return f"{head} {EFFECT_TEXT[event.effect]}"
    if event.effect:
        tags = [_change_tag(change, event.side) for change in event.changes]
        return " ".join(filter(None, [head, EFFECT_TEXT.get(event.effect, "→"), *tags]))
    if event.failed:
        return f"{head} → 실패"
    if event.missed:
        return f"{head} → 빗나감"
    if event.multiplier == 0:
        return " ".join(filter(None, [head, "→", event.defender, "무효", _ability_tag(event)]))
    hp = FAINTED if event.knockout else f"{event.defender_hp}%"
    item_tags = [f"@{ITEM_NAMES[item]}" for item in (event.attacker_item, event.defender_item) if item]
    pivot = ["↩교체"] if event.pivoted else []
    return " ".join([f"{head} → {event.defender} {hp}", *_hit_tags(event)[:MAX_TAGS], *item_tags, *pivot])


def _hit_tags(event: Action) -> list[str]:
    """In the order they are kept when more than `MAX_TAGS` apply; a held item that triggered is always shown."""
    tags = []
    if event.critical:
        tags.append("급소")
    if event.multiplier > 1:
        tags.append("효과 굉장")
    elif event.multiplier < 1:
        tags.append("효과 별로")
    if event.ability:
        tags.append(_ability_tag(event))
    tags += [_change_tag(change, event.side) for change in event.changes]
    if event.hits > 1:
        tags.append(f"{event.hits}연타")
    if event.drained:
        tags.append("흡수")
    if event.recoil:
        tags.append("반동")
    return tags


def _ability_tag(event: Action) -> str:
    return f"[{ABILITY_NAMES[event.ability]}]" if event.ability else ""


def _change_tag(change: Change | None, acting_side: int) -> str:
    if change is None:
        return ""
    if change.kind in STATUS_ICON:
        return STATUS_ICON[change.kind]
    if change.kind == "cure":
        return f"{'자신 ' if change.side == acting_side else ''}상태 회복"
    if change.kind == "thaw":
        return "🧊해동"
    if change.kind == "revive":
        return f"{change.pokemon} 부활"
    arrows = ("↑" if change.stages > 0 else "↓") * (2 if abs(change.stages) >= 2 else 1)
    return f"{'자신 ' if change.side == acting_side else ''}{STAT_SHORT[change.kind]}{arrows}"
