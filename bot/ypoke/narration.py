"""In-game style battle narration built only from events the simulation produced."""

from ypoke.battle import BattleResult, Combatant, Hit

KEY_HITS = 3
PRACTICE_NOTE = "(연습 대결 — 전적에 안 남아요)"


def battle_lines(
    trainers: tuple[str, str],
    combatants: tuple[Combatant, Combatant],
    result: BattleResult,
    practice: bool = False,
) -> list[str]:
    """`trainers` are Slack mentions, challenger first; their particles are always written as "이(가)"."""
    lines = [f"{trainers[1]}에게 {trainers[0]}이(가) 승부를 걸어왔다!"]
    for trainer, combatant in zip(trainers, combatants):
        details = f"Lv{combatant.level}{' ✨' if combatant.shiny else ''}"
        lines.append(f"{trainer}은(는) {with_particle(combatant.name, ('을', '를'))} 내보냈다! ({details})")
    lines += [_hit_line(combatants[hit.attacker_side], hit) for hit in _key_hits(result.hits)]
    if result.hits and result.hits[-1].knockout:
        loser = combatants[1 - result.winner]
        lines.append(f"{with_particle(loser.name, ('은', '는'))} 쓰러졌다!")
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


def _key_hits(hits: list[Hit]) -> list[Hit]:
    if not hits:
        return []
    notable = [hit for hit in hits[1:-1] if hit.critical or hit.multiplier != 1]
    picked = []
    for hit in [hits[-1], hits[0], *notable]:
        if hit not in picked and len(picked) < KEY_HITS:
            picked.append(hit)
    return sorted(picked, key=hits.index)


def _hit_line(attacker: Combatant, hit: Hit) -> str:
    parts = [f"{attacker.name}의 {hit.move}!"]
    if hit.critical:
        parts.append("급소에 맞았다!")
    if hit.multiplier > 1:
        parts.append("효과가 굉장했다!")
    elif 0 < hit.multiplier < 1:
        parts.append("효과가 별로인 듯하다…")
    return " ".join(parts)
