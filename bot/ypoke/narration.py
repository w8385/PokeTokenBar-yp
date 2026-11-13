"""In-game style battle narration built only from events the simulation produced."""

from ypoke.battle import Action, BattleResult, BurnDamage, Change, Combatant

MAX_EVENT_LINES = 24
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


def battle_lines(
    trainers: tuple[str, str],
    combatants: tuple[Combatant, Combatant],
    result: BattleResult,
    practice: bool = False,
) -> list[str]:
    """`trainers` are Slack mentions, challenger first; their particles are always written as "이(가)".

    One line per action and burn tick; a long battle keeps its first and last `MAX_EVENT_LINES // 2`.
    """
    lines = [f"{trainers[1]}에게 {trainers[0]}이(가) 승부를 걸어왔다!"]
    lines += [_send_out_line(trainer, combatant) for trainer, combatant in zip(trainers, combatants)]
    events = [_event_line(event) for event in result.events]
    if len(events) > MAX_EVENT_LINES:
        half = MAX_EVENT_LINES // 2
        events = [*events[:half], SKIPPED_LINE, *events[-half:]]
    lines += events
    win_line = f"{trainers[result.winner]}은(는) 승부에서 이겼다!"
    lines.append(f"{win_line} {PRACTICE_NOTE}" if practice else win_line)
    return lines


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


def _event_line(event: Action | BurnDamage) -> str:
    prefix = f"{event.turn}턴 {SIDE_MARKERS[event.side]}"
    if isinstance(event, BurnDamage):
        tail = f"{with_particle(event.pokemon, ('은', '는'))} 쓰러졌다!" if event.fainted else f"(HP {event.hp}%)"
        return f"{prefix} {with_particle(event.pokemon, ('은', '는'))} 화상 데미지를 입었다! {tail}"
    if not event.move:
        return f"{prefix} {with_particle(event.attacker, ('은', '는'))} 몸이 저려서 움직일 수 없다!"
    parts = [f"{prefix} {event.attacker}의 {event.move}!"]
    if event.missed:
        parts.append("하지만 빗나갔다!")
        return " ".join(parts)
    if event.multiplier == 0:
        parts.append(f"{event.defender}에게는 효과가 없는 것 같다…")
        return " ".join(parts)
    if event.critical:
        parts.append("급소에 맞았다!")
    if event.multiplier > 1:
        parts.append("효과가 굉장했다!")
    elif event.multiplier < 1:
        parts.append("효과가 별로인 듯하다…")
    parts += [_change_text(change) for change in event.changes]
    if event.recoil:
        parts.append(f"{with_particle(event.attacker, ('은', '는'))} 반동으로 데미지를 입었다!")
    if event.knockout:
        parts.append(f"{with_particle(event.defender, ('은', '는'))} 쓰러졌다!")
    elif event.attacker_fainted:
        parts.append(f"{with_particle(event.attacker, ('은', '는'))} 쓰러졌다!")
    else:
        parts.append(f"({event.defender} HP {event.defender_hp}%)")
    return " ".join(parts)


def _change_text(change: Change) -> str:
    if change.kind == "burn":
        return f"{with_particle(change.pokemon, ('은', '는'))} 화상을 입었다!"
    if change.kind == "paralysis":
        return f"{with_particle(change.pokemon, ('은', '는'))} 마비되어 기술이 나오기 어려워졌다!"
    size = "크게 " if abs(change.stages) >= 2 else ""
    direction = "올랐다" if change.stages > 0 else "떨어졌다"
    return f"{change.pokemon}의 {with_particle(STAT_NAMES[change.kind], ('이', '가'))} {size}{direction}!"
