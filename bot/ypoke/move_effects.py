"""Moves the battle gives an effect beyond damage, by PokéAPI id. A status move not listed here is never offered."""

TRICK_ROOM = 433
STEALTH_ROCK = 446
YAWN = 281
THUNDER_WAVE = 86
U_TURN = 369
VOLT_SWITCH = 521
FLIP_TURN = 812
SELF_DESTRUCT = 120
EXPLOSION = 153
JUDGMENT = 449
IVY_CUDGEL = 904
DRAGON_ASCENT = 620
# Punching Glove boosts these.
PUNCH_MOVES = frozenset({5, 7, 8, 9, 183, 223, 264, 309, 325, 359, 409, 418, 612, 665, 721, 742, 817, 838, 857, 889})

STATUS_MOVES = {TRICK_ROOM: "trick-room", STEALTH_ROCK: "stealth-rock", YAWN: "yawn", THUNDER_WAVE: "thunder-wave"}
EFFECTS = {
    **STATUS_MOVES, U_TURN: "pivot", VOLT_SWITCH: "pivot", FLIP_TURN: "pivot", SELF_DESTRUCT: "self-ko",
    EXPLOSION: "self-ko",
}


def wants_status_moves(move_ids) -> bool:
    """Whether a chosen move list names a status move, so its learnset lookup must include them."""
    return any(move_id in STATUS_MOVES for move_id in move_ids or ())
