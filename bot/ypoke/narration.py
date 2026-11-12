"""In-game style battle narration built only from events the simulation produced."""

from ypoke.battle import BattleResult, Combatant, Hit

KEY_HITS = 3
PRACTICE_NOTE = "(연습 대결 — 전적에 안 남아요)"


def battle_lines(
    trainers: tuple[str, str],
    entries: tuple[list[Combatant], list[Combatant]],
    result: BattleResult,
    practice: bool = False,
) -> list[str]:
    """`trainers` are Slack mentions, challenger first; their particles are always written as "이(가)".

    Every knockout gets a line, plus the opening hit and notable hits up to `KEY_HITS` hit lines.
    """
    lines = [f"{trainers[1]}에게 {trainers[0]}이(가) 승부를 걸어왔다!"]
    lines += [_send_out_line(trainer, entry) for trainer, entry in zip(trainers, entries)]
    lines += [_hit_line(hit) for hit in _key_hits(result.hits)]
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


def _send_out_line(trainer: str, entry: list[Combatant]) -> str:
    if len(entry) == 1:
        return f"{trainer}은(는) {with_particle(entry[0].name, ('을', '를'))} 내보냈다! ({_details(entry[0])})"
    order = " → ".join(f"{combatant.name}({_details(combatant)})" for combatant in entry)
    return f"{trainer}은(는) {order} 순으로 내보낸다!"


def _details(combatant: Combatant) -> str:
    return f"Lv{combatant.level}{' ✨' if combatant.shiny else ''}"


def _key_hits(hits: list[Hit]) -> list[Hit]:
    if not hits:
        return []
    picked = [hit for hit in hits if hit.knockout]
    notable = [hit for hit in hits[1:] if hit.critical or hit.missed or hit.multiplier != 1]
    for hit in [hits[0], *notable]:
        if hit not in picked and (hit is hits[0] or len(picked) < KEY_HITS):
            picked.append(hit)
    return sorted(picked, key=hits.index)


def _hit_line(hit: Hit) -> str:
    parts = [f"{hit.attacker}의 {hit.move}!"]
    if hit.missed:
        parts.append("하지만 빗나갔다!")
    else:
        if hit.critical:
            parts.append("급소에 맞았다!")
        if hit.multiplier > 1:
            parts.append("효과가 굉장했다!")
        elif 0 < hit.multiplier < 1:
            parts.append("효과가 별로인 듯하다…")
    if hit.knockout:
        parts.append(f"{with_particle(hit.defender, ('은', '는'))} 쓰러졌다!")
    return " ".join(parts)
