"""Battle result card and turn log, built only from events the simulation produced."""

from collections.abc import Sequence
from dataclasses import dataclass

from ypoke.abilities import NAMES as ABILITY_NAMES
from ypoke.battle import (
    BATTLE_LEVEL, AbilityTrigger, Action, BattleResult, Change, Combatant, Event, ItemHeal, MegaEvolution, SendOut,
    StatusDamage, WeatherDamage, WeatherEnd,
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
WEATHER_ICON = {"sun": "☀️", "rain": "☔", "sandstorm": "🏜️", "hail": "🌨️", "snow": "❄️"}
STATUS_ICON = {
    "burn": "🔥화상", "paralysis": "⚡마비", "poison": "☠️독", "toxic": "☠️맹독", "sleep": "💤잠듦",
    "freeze": "🧊얼음", "confusion": "💫혼란",
}
RESIDUAL_ICON = {"burn": "🔥", "poison": "☠️", "toxic": "☠️"}
BLOCKED_TAG = {"paralysis": "⚡몸이 저려 못 움직임", "sleep": "💤자는 중", "freeze": "🧊얼어서 못 움직임"}
RECOVERED_TAG = {"sleep": "💤깸", "freeze": "🧊풀림", "confusion": "💫풀림"}
STAT_SHORT = {
    "attack": "공격", "defense": "방어", "special_attack": "특공", "special_defense": "특방", "speed": "스피드",
}


@dataclass(frozen=True)
class Card:
    """What the result message shows. `log` is one mrkdwn text per turn (`*N턴*` then one action per line)
    and a `⋯ N턴 생략` text for each gap; `highlights` is the deciding knockout of a full-lineup battle."""

    columns: tuple[str, str]
    title: str = ""
    detail: str = ""
    highlights: tuple[str, ...] = ()
    log: tuple[str, ...] = ()
    sprite: tuple[str, str] | None = None
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
    megas = {(event.side, event.pokemon) for event in result.events if isinstance(event, MegaEvolution)}
    columns = tuple(
        _column(side, trainers[side], roster, result.remaining[side] if side < len(result.remaining) else (), megas)
        for side, roster in enumerate(sides)
    )
    decisive = _decisive_line(result) if len(sides[0]) > 1 or len(sides[1]) > 1 else None
    return Card(
        columns, _title(trainers, result), _detail(sides, result), (decisive,) if decisive else (),
        battle_log(result), _winner_sprite(sides[result.winner], result), practice,
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
            megas: set[tuple[int, str]]) -> str:
    lines = [f"{SIDE_MARKERS[side]} *{trainer}*"]
    for index, member in enumerate(roster):
        hp = hps[index] if index < len(hps) else None
        label = _member_label(member, (side, member.name) in megas)
        if hp is None:
            lines.append(f"{label} {WAITING}")
        elif hp == 0:
            lines.append(f"{label} {FAINTED}")
        else:
            lines.append(f"{label} {bar(hp, 100)} {hp}%")
    return "\n".join(lines)


def _member_label(member: Combatant, mega: bool) -> str:
    label = member.name
    if member.shiny:
        label += "✨"
    if member.rental:
        label += "(대여)"
    if mega:
        label += "(메가)"
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
    icon = RESIDUAL_ICON[event.kind] if isinstance(event, StatusDamage) else WEATHER_ICON[event.weather]
    return f"{event.pokemon} {icon}"


def _faint_side(event: Event) -> int | None:
    """The side whose Pokémon fainted from this event, if any (a knockout and the attacker's own faint)."""
    if isinstance(event, Action):
        if event.knockout:
            return 1 - event.side
        return event.side if event.attacker_fainted else None
    if isinstance(event, (StatusDamage, WeatherDamage)) and event.fainted:
        return event.side
    return None


@dataclass
class _Turn:
    number: int
    lines: list[str]
    essential: bool = False

    def render(self) -> str:
        return "\n".join([f"*{self.number}턴*", *self.lines])


def battle_log(result: BattleResult, budget: int = MAX_LOG_BLOCKS) -> tuple[str, ...]:
    """One text per turn. When the turns do not fit `budget` blocks, the first and last `ends` turns stay with
    every turn that has a faint or a send-out, and each gap becomes one `⋯ N턴 생략` text."""
    turns = _turns(result.events)
    ends = len(turns)
    while True:
        entries = _entries(turns, ends)
        if len(entries) <= budget or ends <= 1:
            return tuple(entries)
        ends -= 1


def _entries(turns: list[_Turn], ends: int) -> list[str]:
    entries: list[str] = []
    skipped = 0
    for index, turn in enumerate(turns):
        if index < ends or index >= len(turns) - ends or turn.essential:
            if skipped:
                entries.append(f"{SKIPPED_MARK} {skipped}턴 생략")
                skipped = 0
            entries.append(turn.render())
        else:
            skipped += 1
    return entries


def _turns(events: list[Event]) -> list[_Turn]:
    """Group events by turn. Entry events (no turn of their own) join the send-out they directly follow;
    those before any turn open turn 1."""
    turns: list[_Turn] = []
    opening: list[str] = []
    sent: dict[int, int] = {}
    for event in events:
        if isinstance(event, (AbilityTrigger, MegaEvolution)):
            current = turns[-1].lines if turns else opening
            if event.side in sent:
                current[sent[event.side]] += f" {_entry_effect(event)}"
            else:
                current.append(_entry_segment(event))
            continue
        if not isinstance(event, SendOut):
            sent = {}
        if not turns or turns[-1].number != event.turn:
            turns.append(_Turn(event.turn, opening))
            opening = []
        turn = turns[-1]
        lines = _event_lines(event)
        if isinstance(event, SendOut):
            sent[event.side] = len(turn.lines)
            turn.essential = True
        elif _faint_side(event) is not None:
            turn.essential = True
        turn.lines += lines
    return turns


def _entry_effect(event: AbilityTrigger | MegaEvolution) -> str:
    if isinstance(event, MegaEvolution):
        return f"메가진화 [{event.ability}]" if event.ability else "메가진화"
    effect = WEATHER_ICON[event.weather] if event.weather else _change_tag(event.change, event.side)
    return f"[{ABILITY_NAMES[event.ability]}] {effect}"


def _entry_segment(event: AbilityTrigger | MegaEvolution) -> str:
    return f"{SIDE_MARKERS[event.side]} {event.pokemon} {_entry_effect(event)}"


def _event_lines(event: Event) -> list[str]:
    """The log lines of one event: what happened, then a faint line for each Pokémon the line does not already
    show fainting (an attack's knocked-out target ends its line with 💥)."""
    if isinstance(event, WeatherEnd):
        return [f"{WEATHER_ICON[event.weather]}끝"]
    marker = SIDE_MARKERS[event.side]
    if isinstance(event, SendOut):
        return [f"↪ {marker} {event.pokemon} 등장"]
    if isinstance(event, (StatusDamage, WeatherDamage)):
        icon = RESIDUAL_ICON[event.kind] if isinstance(event, StatusDamage) else WEATHER_ICON[event.weather]
        return [f"{marker} {event.pokemon} {icon} {event.hp}%", *([_faint_line(event.pokemon)] if event.fainted else [])]
    if isinstance(event, ItemHeal):
        return [f"{marker} {event.pokemon} @{ITEM_NAMES[event.item]} {event.hp}%"]
    lines = [_action_line(event, marker)]
    if event.attacker_fainted:
        lines.append(_faint_line(event.attacker))
    return lines


def _faint_line(name: str) -> str:
    return f"{FAINTED} {name} {FAINTED_TAG}"


def _action_line(event: Action, marker: str) -> str:
    head = " ".join([marker, event.attacker, *(RECOVERED_TAG[kind] for kind in event.recovered)])
    if event.blocked == "confusion":
        return f"{head} 💫혼란 자해 {event.attacker_hp}%"
    if event.blocked:
        return f"{head} {BLOCKED_TAG[event.blocked]}"
    head = f"{head} › {event.move}"
    if event.weather:
        return f"{head} {WEATHER_ICON[event.weather]}"
    if event.failed:
        return f"{head} → 실패"
    if event.missed:
        return f"{head} → 빗나감"
    if event.multiplier == 0:
        return " ".join(filter(None, [head, "→", event.defender, "무효", _ability_tag(event)]))
    hp = FAINTED if event.knockout else f"{event.defender_hp}%"
    return " ".join([f"{head} → {event.defender} {hp}", *_hit_tags(event)[:MAX_TAGS]])


def _hit_tags(event: Action) -> list[str]:
    """In the order they are kept when more than `MAX_TAGS` apply."""
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
    tags += [f"@{ITEM_NAMES[item]}" for item in (event.attacker_item, event.defender_item) if item]
    return tags


def _ability_tag(event: Action) -> str:
    return f"[{ABILITY_NAMES[event.ability]}]" if event.ability else ""


def _change_tag(change: Change | None, acting_side: int) -> str:
    if change is None:
        return ""
    if change.kind in STATUS_ICON:
        return STATUS_ICON[change.kind]
    if change.kind == "thaw":
        return "🧊해동"
    arrows = ("↑" if change.stages > 0 else "↓") * (2 if abs(change.stages) >= 2 else 1)
    return f"{'자신 ' if change.side == acting_side else ''}{STAT_SHORT[change.kind]}{arrows}"
