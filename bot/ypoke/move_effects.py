"""Moves the battle gives an effect beyond damage, by PokéAPI id (`data/battle/moves.json`). A status move without a
status effect key is never offered."""

from ypoke import battle_data

TRICK_ROOM = 433
STEALTH_ROCK = 446
YAWN = 281
THUNDER_WAVE = 86
SWORDS_DANCE = 14
U_TURN = 369
VOLT_SWITCH = 521
FLIP_TURN = 812
SELF_DESTRUCT = 120
EXPLOSION = 153
JUDGMENT = 449
IVY_CUDGEL = 904
DRAGON_ASCENT = 620
FLOWER_TRICK = 870
STATUS_EFFECTS = (
    "trick-room", "stealth-rock", "swords-dance", "yawn", "thunder-wave",
    "electric-terrain", "grassy-terrain", "psychic-terrain", "misty-terrain", "reflect", "light-screen", "aurora-veil",
    "spikes", "toxic-spikes", "sticky-web", "tailwind", "safeguard", "mist", "lucky-chant", "gravity", "haze", "defog",
    "court-change", "tidy-up",
)
# Damaging moves the chooser may pick for their effect, like a status move.
CHOSEN_DAMAGE_EFFECTS = ("rapid-spin", "mortal-spin")
DAMAGE_EFFECTS = ("pivot", "self-ko", *CHOSEN_DAMAGE_EFFECTS)
# Keys found by the move's id rather than its `effect`.
ID_KEYS = frozenset({
    "always-crit", "never-miss", "rising-voltage", "expanding-force", "terrain-pulse", "grassy-glide",
    "misty-explosion", "psyblade", "steel-roller", "ice-spinner", "stone-axe", "ceaseless-edge", "screen-breaker",
})
EFFECT_KEYS = frozenset({*STATUS_EFFECTS, *DAMAGE_EFFECTS, *ID_KEYS, "damage", "struggle", "judgment",
                         "ivy-cudgel"})
# Punching Glove boosts these.
PUNCH_MOVES = frozenset(int(move_id) for move_id, entry in battle_data.table("moves").items()
                        if "punch" in entry.get("flags", ()))

STATUS_MOVES = {move_id: key for key in STATUS_EFFECTS for move_id in battle_data.with_key("moves", key)}
EFFECTS = {**STATUS_MOVES, **{move_id: key for key in DAMAGE_EFFECTS for move_id in battle_data.with_key("moves", key)}}


def wants_status_moves(move_ids) -> bool:
    """Whether a chosen move list names a status move, so its learnset lookup must include them."""
    return any(move_id in STATUS_MOVES for move_id in move_ids or ())
