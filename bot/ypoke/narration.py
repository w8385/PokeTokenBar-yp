"""Battle result card and compact turn log, built only from events the simulation produced."""

from collections.abc import Sequence
from dataclasses import dataclass

from ypoke.abilities import NAMES as ABILITY_NAMES
from ypoke.battle import (
    BATTLE_LEVEL, AbilityTrigger, Action, BattleResult, Change, Combatant, Event, ItemHeal, MegaEvolution, SendOut,
    StatusDamage, WeatherDamage, WeatherEnd,
)
from ypoke.items import ITEM_NAMES, known

MAX_TURN_LINES = 24
MAX_LOG_CHARS = 2900
MAX_HIGHLIGHTS = 3
PRACTICE_NOTE = "연습 대결"
SKIPPED_LINE = "⋯"
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
    """The two lineup columns (mrkdwn), up to `MAX_HIGHLIGHTS` highlight lines and an optional note line."""

    columns: tuple[str, str]
    highlights: tuple[str, ...] = ()
    note: str | None = None


def battle_header(
    trainers: tuple[str, str], sides: tuple[Sequence[Combatant], Sequence[Combatant]], result: BattleResult,
    practice: bool = False,
) -> str:
    """`🏆 <winner> 승 · 3:3 · 9턴`; `trainers` are Slack mentions (or "YPoke"), challenger first."""
    header = f"🏆 {trainers[result.winner]} 승 · {len(sides[0])}:{len(sides[1])} · {result.turns}턴"
    return f"{header} · {PRACTICE_NOTE}" if practice else header


def battle_card(
    trainers: tuple[str, str], sides: tuple[Sequence[Combatant], Sequence[Combatant]], result: BattleResult
) -> Card:
    megas = {(event.side, event.pokemon) for event in result.events if isinstance(event, MegaEvolution)}
    columns = tuple(
        _column(side, trainers[side], roster, result.remaining[side] if side < len(result.remaining) else (), megas)
        for side, roster in enumerate(sides)
    )
    return Card(columns, tuple(_highlights(result)[:MAX_HIGHLIGHTS]))


def battle_log(result: BattleResult) -> list[str]:
    """One line per turn. A long battle keeps its first and last `MAX_TURN_LINES // 2` lines plus every faint,
    and drops more of the middle until the log fits `MAX_LOG_CHARS`."""
    lines, essential = [], []
    for turn in _turns(result.events):
        line = turn.render()
        lines.append(line)
        essential.append(bool(turn.entering) or any(FAINTED_TAG in part for part in turn.parts))
    half = MAX_TURN_LINES // 2
    while True:
        keep = [
            index < half or index >= len(lines) - half or essential[index] for index in range(len(lines))
        ] if len(lines) > MAX_TURN_LINES else [True] * len(lines)
        shown: list[str] = []
        for index, line in enumerate(lines):
            if keep[index]:
                shown.append(line)
            elif shown and shown[-1] != SKIPPED_LINE:
                shown.append(SKIPPED_LINE)
        if half == 0 or sum(len(line) + 1 for line in shown) <= MAX_LOG_CHARS:
            return shown
        half -= 1



def _column(side: int, trainer: str, roster: Sequence[Combatant], hps: Sequence[int | None],
            megas: set[tuple[int, str]]) -> str:
    lines = [f"{SIDE_MARKERS[side]} *{trainer}*"]
    for index, member in enumerate(roster):
        hp = hps[index] if index < len(hps) else None
        fate = WAITING if hp is None else FAINTED if hp == 0 else f"{hp}%"
        lines.append(f"{_member_label(member, (side, member.name) in megas)} {fate}")
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


def _highlights(result: BattleResult) -> list[str]:
    """Priority: the faint that ended the battle, super-effective knockouts, critical hits, ability and weather
    moments, Mega Evolutions; each group in battle order."""
    events = result.events
    loser = 1 - result.winner
    decisive = None
    if result.remaining and result.remaining[loser] and all(hp == 0 for hp in result.remaining[loser]):
        decisive = next((event for event in reversed(events) if _faint_side(event) == loser), None)
    chosen: list[Event] = []
    groups = (
        [decisive] if decisive is not None else [],
        [e for e in events if isinstance(e, Action) and e.knockout and e.multiplier > 1],
        [e for e in events if isinstance(e, Action) and e.critical],
        [e for e in events if _is_ability_or_weather_moment(e)],
        [e for e in events if isinstance(e, MegaEvolution)],
    )
    for group in groups:
        chosen += [event for event in group if not any(event is picked for picked in chosen)]
    return [
        _highlight_line(event, decisive is not None and event is decisive) for event in chosen[:MAX_HIGHLIGHTS]
    ]


def _faint_side(event: Event) -> int | None:
    """The side whose Pokémon fainted from this event, if any (a knockout and the attacker's own faint)."""
    if isinstance(event, Action):
        if event.knockout:
            return 1 - event.side
        return event.side if event.attacker_fainted else None
    if isinstance(event, (StatusDamage, WeatherDamage)) and event.fainted:
        return event.side
    return None


def _is_ability_or_weather_moment(event: Event) -> bool:
    return isinstance(event, AbilityTrigger) or (isinstance(event, Action) and bool(event.ability or event.weather))


def _highlight_line(event: Event, decisive: bool) -> str:
    if decisive:
        return f"💥 결정타 {_segment(event)} ({event.turn}턴)"
    if isinstance(event, AbilityTrigger):
        return f"✨ {_entry_segment(event)}"
    if isinstance(event, MegaEvolution):
        return f"🌟 {_entry_segment(event)} ({event.turn}턴)"
    if event.weather:
        return f"{_segment(event)} ({event.turn}턴)"
    if event.ability:
        return f"✨ {_segment(event)} ({event.turn}턴)"
    icon = "🎯" if event.critical and not (event.knockout and event.multiplier > 1) else "⚡"
    return f"{icon} {_segment(event)} ({event.turn}턴)"


class _Turn:
    def __init__(self, number: int | None, parts: list[str]):
        self.number = number
        self.parts = parts
        self.entering: list[tuple[int, str]] = []

    def render(self) -> str:
        line = f"{self.number}턴 " + " · ".join(self.parts)
        if self.entering:
            line += " → " + ", ".join(text for _, text in self.entering)
        return line


def _turns(events: list[Event]) -> list[_Turn]:
    """Group events by turn. Entry events (no turn of their own) join the send-out they follow, or turn 1 at the start."""
    turns: list[_Turn] = []
    opening: list[str] = []
    for event in events:
        if isinstance(event, (AbilityTrigger, MegaEvolution)):
            entering = turns[-1].entering if turns else []
            side = event.side
            slot = next((i for i, (s, _) in enumerate(entering) if s == side), None)
            if slot is None:
                (opening if not turns else turns[-1].parts).append(_entry_segment(event))
            else:
                entering[slot] = (side, f"{entering[slot][1]} {_entry_effect(event)}")
            continue
        number = event.turn
        if not turns or turns[-1].number != number:
            turns.append(_Turn(number, opening))
            opening = []
        turn = turns[-1]
        if isinstance(event, SendOut):
            turn.entering.append((event.side, f"{SIDE_MARKERS[event.side]} {event.pokemon}"))
        else:
            turn.parts.append(_segment(event))
    return turns


def _entry_effect(event: AbilityTrigger | MegaEvolution) -> str:
    if isinstance(event, MegaEvolution):
        return f"메가진화 [{event.ability}]" if event.ability else "메가진화"
    effect = WEATHER_ICON[event.weather] if event.weather else _change_tag(event.change, event.side)
    return f"[{ABILITY_NAMES[event.ability]}] {effect}"


def _entry_segment(event: AbilityTrigger | MegaEvolution) -> str:
    return f"{SIDE_MARKERS[event.side]} {event.pokemon} {_entry_effect(event)}"


def _segment(event: Event) -> str:
    if isinstance(event, WeatherEnd):
        return f"{WEATHER_ICON[event.weather]}끝"
    marker = SIDE_MARKERS[event.side]
    if isinstance(event, (StatusDamage, WeatherDamage)):
        icon = RESIDUAL_ICON[event.kind] if isinstance(event, StatusDamage) else WEATHER_ICON[event.weather]
        return f"{marker} {event.pokemon} {icon} {FAINTED_TAG if event.fainted else f'{event.hp}%'}"
    if isinstance(event, ItemHeal):
        return f"{marker} {event.pokemon} @{ITEM_NAMES[event.item]} {event.hp}%"
    return _action_segment(event, marker)


def _action_segment(event: Action, marker: str) -> str:
    head = " ".join([marker, event.attacker, *(RECOVERED_TAG[kind] for kind in event.recovered)])
    if event.blocked == "confusion":
        tail = FAINTED_TAG if event.attacker_fainted else f"{event.attacker_hp}%"
        return f"{head} 💫혼란 자해 {tail}"
    if event.blocked:
        return f"{head} {BLOCKED_TAG[event.blocked]}"
    head = f"{head} {event.move}"
    if event.weather:
        return f"{head} {WEATHER_ICON[event.weather]}"
    if event.failed:
        return f"{head} → 실패"
    if event.missed:
        return f"{head} → 빗나감"
    if event.multiplier == 0:
        return " ".join(filter(None, [head, "→", event.defender, "무효", _ability_tag(event)]))
    target = f"{event.defender} {FAINTED_TAG if event.knockout else f'{event.defender_hp}%'}"
    return " ".join([f"{head} → {target}", *_hit_tags(event)])


def _hit_tags(event: Action) -> list[str]:
    tags = []
    if event.critical:
        tags.append("급소")
    if event.multiplier > 1:
        tags.append("굉장")
    elif event.multiplier < 1:
        tags.append("별로")
    if event.hits > 1:
        tags.append(f"{event.hits}연타")
    if event.ability:
        tags.append(_ability_tag(event))
    tags += [_change_tag(change, event.side) for change in event.changes]
    if event.drained:
        tags.append("흡수")
    if event.recoil:
        tags.append("반동")
    for item in (event.attacker_item, event.defender_item):
        if item:
            tags.append(f"@{ITEM_NAMES[item]}")
    if event.attacker_fainted and not event.knockout:
        tags.append(f"{event.attacker} {FAINTED_TAG}")
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
