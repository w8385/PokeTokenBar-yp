"""In-game style battle narration built only from events the simulation produced."""

from collections.abc import Sequence

from ypoke.abilities import NAMES as ABILITY_NAMES
from ypoke.battle import (
    AbilityTrigger, Action, BattleResult, Change, Combatant, Event, SendOut, StatusDamage, WeatherDamage,
    WeatherEnd,
)

MAX_EVENT_LINES = 24
MAX_LOG_CHARS = 2900
PRACTICE_NOTE = "(연습 대결 — 전적에 안 남아요)"
SKIPPED_LINE = "⋯"
RENTAL_PREFIX = "대여 포켓몬 "
STAT_NAMES = {
    "attack": "공격",
    "defense": "방어",
    "special_attack": "특수공격",
    "special_defense": "특수방어",
    "speed": "스피드",
}
SIDE_MARKERS = ("🔵", "🔴")
WEATHER_START = {
    "sun": "햇살이 강해졌다!",
    "rain": "비가 내리기 시작했다!",
    "sandstorm": "모래바람이 불기 시작했다!",
    "hail": "싸라기눈이 내리기 시작했다!",
    "snow": "눈이 내리기 시작했다!",
}
WEATHER_END = {
    "sun": "햇살이 원래대로 돌아왔다!",
    "rain": "비가 그쳤다!",
    "sandstorm": "모래바람이 가라앉았다!",
    "hail": "싸라기눈이 그쳤다!",
    "snow": "눈이 그쳤다!",
}
ABILITY_EFFECT = {
    "levitate": "땅 타입 기술이 맞지 않는다!",
    "sturdy": "간신히 버텼다!",
    "immunity": "독에 걸리지 않는다!",
    "limber": "마비되지 않는다!",
    "insomnia": "잠들지 않는다!",
    "water-veil": "화상을 입지 않는다!",
}
WEATHER_DAMAGE = {"sandstorm": "모래바람에 휩싸였다!", "hail": "싸라기눈에 맞았다!"}
STATUS_TEXT = {
    "burn": "화상을 입었다!",
    "paralysis": "마비되어 기술이 나오기 어려워졌다!",
    "poison": "독에 걸렸다!",
    "toxic": "맹독에 걸렸다!",
    "sleep": "잠들어 버렸다!",
    "freeze": "얼어붙었다!",
    "confusion": "혼란에 빠졌다!",
}
STATUS_DAMAGE_TEXT = {"burn": "화상", "poison": "독", "toxic": "독"}
BLOCKED_TEXT = {
    "paralysis": "몸이 저려서 움직일 수 없다!",
    "sleep": "쿨쿨 잠들어 있다!",
    "freeze": "얼어서 움직일 수 없다!",
}


def battle_lines(
    trainers: tuple[str, str],
    sides: tuple[Combatant | Sequence[Combatant], Combatant | Sequence[Combatant]],
    result: BattleResult,
    practice: bool = False,
) -> list[str]:
    """`trainers` are Slack mentions, challenger first; their particles are always written as "이(가)".

    One line per event. A long battle keeps its first and last `MAX_EVENT_LINES // 2` lines plus every send-out
    and faint line, and drops more of the middle until the log fits `MAX_LOG_CHARS`.
    """
    rosters = tuple((side,) if isinstance(side, Combatant) else tuple(side) for side in sides)
    lines = [f"{trainers[1]}에게 {trainers[0]}이(가) 승부를 걸어왔다!"]
    lines += [_send_out_line(trainer, roster[0]) for trainer, roster in zip(trainers, rosters)]
    lines += [_roster_line(side, roster) for side, roster in enumerate(rosters) if len(roster) > 1]
    win_line = f"{trainers[result.winner]}은(는) 승부에서 이겼다!"
    closing = f"{win_line} {PRACTICE_NOTE}" if practice else win_line
    budget = MAX_LOG_CHARS - sum(len(line) + 1 for line in (*lines, closing))
    return [*lines, *_event_lines(result.events, budget), closing]


def _event_lines(events: list[Event], budget: int) -> list[str]:
    lines = [_event_line(event) for event in events]
    essential = [isinstance(event, (SendOut, AbilityTrigger)) or _faints(event) for event in events]
    half = MAX_EVENT_LINES // 2
    while True:
        keep = [
            index < half or index >= len(lines) - half or essential[index] for index in range(len(lines))
        ] if len(lines) > MAX_EVENT_LINES else [True] * len(lines)
        shown = []
        for index, line in enumerate(lines):
            if keep[index]:
                shown.append(line)
            elif shown and shown[-1] != SKIPPED_LINE:
                shown.append(SKIPPED_LINE)
        if half == 0 or sum(len(line) + 1 for line in shown) <= budget:
            return shown
        half -= 1


def _faints(event: Event) -> bool:
    return isinstance(event, Action) and (event.knockout or event.attacker_fainted) or (
        isinstance(event, (StatusDamage, WeatherDamage)) and event.fainted
    )


def _roster_line(side: int, roster: Sequence[Combatant]) -> str:
    return f"{SIDE_MARKERS[side]} " + " → ".join(combatant.name for combatant in roster)


def with_particle(word: str, pair: tuple[str, str]) -> str:
    """Attach `pair[0]` after a final consonant, `pair[1]` after a vowel, or "pair[0](pair[1])" if unknown."""
    last = word[-1:] or " "
    if "가" <= last <= "힣":
        has_final = (ord(last) - ord("가")) % 28 != 0
        return word + (pair[0] if has_final else pair[1])
    return f"{word}{pair[0]}({pair[1]})"


def _send_out_line(trainer: str, combatant: Combatant) -> str:
    details = f"Lv{combatant.level}{' ✨' if combatant.shiny else ''}"
    name = f"{RENTAL_PREFIX}{combatant.name}" if combatant.rental else combatant.name
    return f"{trainer}은(는) {with_particle(name, ('을', '를'))} 내보냈다! ({details})"


def _event_line(event: Event) -> str:
    if isinstance(event, WeatherEnd):
        return f"{event.turn}턴 {WEATHER_END[event.weather]}"
    if isinstance(event, AbilityTrigger):
        effect = WEATHER_START[event.weather] if event.weather else _change_text(event.change)
        return f"{SIDE_MARKERS[event.side]} {event.pokemon}의 {ABILITY_NAMES[event.ability]}! {effect}"
    prefix = f"{event.turn}턴 {SIDE_MARKERS[event.side]}"
    if isinstance(event, SendOut):
        return f"{prefix} 가라, {event.pokemon}!"
    if isinstance(event, StatusDamage):
        name = with_particle(event.pokemon, ("은", "는"))
        tail = f"{name} 쓰러졌다!" if event.fainted else f"(HP {event.hp}%)"
        return f"{prefix} {name} {STATUS_DAMAGE_TEXT[event.kind]} 데미지를 입었다! {tail}"
    if isinstance(event, WeatherDamage):
        name = with_particle(event.pokemon, ("은", "는"))
        tail = f"{name} 쓰러졌다!" if event.fainted else f"(HP {event.hp}%)"
        return f"{prefix} {name} {WEATHER_DAMAGE[event.weather]} {tail}"
    parts = [prefix, *(_recovered_text(event.attacker, kind) for kind in event.recovered)]
    if event.blocked:
        parts.append(_blocked_text(event))
        return " ".join(parts)
    parts.append(f"{event.attacker}의 {event.move}!")
    if event.weather:
        return " ".join([*parts, WEATHER_START[event.weather]])
    if event.failed:
        return " ".join([*parts, "하지만 실패했다!"])
    if event.missed:
        parts.append("하지만 빗나갔다!")
        return " ".join(parts)
    if event.multiplier == 0:
        parts.append(_ability_text(event) if event.ability else f"{event.defender}에게는 효과가 없는 것 같다…")
        return " ".join(parts)
    if event.critical:
        parts.append("급소에 맞았다!")
    if event.multiplier > 1:
        parts.append("효과가 굉장했다!")
    elif event.multiplier < 1:
        parts.append("효과가 별로인 듯하다…")
    if event.hits > 1:
        parts.append(f"{event.hits}번 맞았다!")
    if event.ability:
        parts.append(_ability_text(event))
    parts += [_change_text(change) for change in event.changes]
    if event.drained:
        parts.append(f"{event.defender}에게서 체력을 흡수했다!")
    if event.recoil:
        parts.append(f"{with_particle(event.attacker, ('은', '는'))} 반동으로 데미지를 입었다!")
    if event.knockout:
        parts.append(f"{with_particle(event.defender, ('은', '는'))} 쓰러졌다!")
    elif event.attacker_fainted:
        parts.append(f"{with_particle(event.attacker, ('은', '는'))} 쓰러졌다!")
    else:
        parts.append(f"({event.defender} HP {event.defender_hp}%)")
    return " ".join(parts)


def _ability_text(event: Action) -> str:
    return f"{event.defender}의 {ABILITY_NAMES[event.ability]}! {ABILITY_EFFECT.get(event.ability, '')}".rstrip()


def _recovered_text(pokemon: str, kind: str) -> str:
    return {
        "sleep": f"{with_particle(pokemon, ('은', '는'))} 눈을 떴다!",
        "freeze": f"{pokemon}의 얼음이 녹았다!",
        "confusion": f"{pokemon}의 혼란이 풀렸다!",
    }[kind]


def _blocked_text(event: Action) -> str:
    name = with_particle(event.attacker, ("은", "는"))
    if event.blocked == "confusion":
        tail = f"{name} 쓰러졌다!" if event.attacker_fainted else f"({event.attacker} HP {event.attacker_hp}%)"
        return f"{name} 혼란에 빠져 자신을 공격했다! {tail}"
    return f"{name} {BLOCKED_TEXT[event.blocked]}"


def _change_text(change: Change) -> str:
    if change.kind in STATUS_TEXT:
        return f"{with_particle(change.pokemon, ('은', '는'))} {STATUS_TEXT[change.kind]}"
    if change.kind == "thaw":
        return f"{change.pokemon}의 얼음이 녹았다!"
    size = "크게 " if abs(change.stages) >= 2 else ""
    direction = "올랐다" if change.stages > 0 else "떨어졌다"
    return f"{change.pokemon}의 {with_particle(STAT_NAMES[change.kind], ('이', '가'))} {size}{direction}!"
