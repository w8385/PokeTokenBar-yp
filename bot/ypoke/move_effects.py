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
    "sleep-talk", "transform", "trick-room", "stealth-rock", "swords-dance", "yawn", "thunder-wave",
    "electric-terrain", "grassy-terrain", "psychic-terrain", "misty-terrain", "reflect", "light-screen", "aurora-veil",
    "spikes", "toxic-spikes", "sticky-web", "tailwind", "safeguard", "mist", "lucky-chant", "gravity", "haze", "defog",
    "court-change", "tidy-up",
    "protect", "kings-shield", "spiky-shield", "baneful-bunker", "obstruct", "silk-trap", "burning-bulwark",
    "mat-block", "quick-guard", "crafty-shield", "endure",
    "healing-wish", "memento", "revival-blessing", "heal", "weather-heal", "roost", "swallow", "strength-sap",
    "pain-split", "purify", "rest", "wish", "heal-bell", "refresh", "aqua-ring", "ingrain", "heal-foe",
    "substitute", "shed-tail",
    "inflict", "swagger", "toxic-thread", "psycho-shift",
    "destiny-bond", "grudge", "perish-song", "leech-seed", "curse", "nightmare", "taunt", "encore", "disable",
    "torment", "spite", "heal-block", "embargo", "foresight", "miracle-eye", "lock-on", "telekinesis", "magnet-rise",
    "imprison", "electrify", "powder", "ion-deluge", "magic-coat", "snatch", "octolock", "tar-shot", "mud-sport",
    "water-sport", "focus-energy", "laser-focus",
    "conversion", "conversion-2", "camouflage", "reflect-type", "soak", "magic-powder", "trick-or-treat",
    "forests-curse", "gastro-acid", "simple-beam", "worry-seed", "entrainment", "skill-swap", "role-play", "doodle",
    "trick", "switcheroo", "bestow", "recycle", "corrosive-gas", "teatime", "stuff-cheeks", "magic-room", "wonder-room",
    "teleport", "parting-shot", "chilly-reception",
    "mirror-move", "copycat", "me-first", "nature-power", "mimic", "sketch",
    "stages", "growth", "stockpile", "charge", "no-retreat", "take-heart", "plus-minus", "grass-boost",
    "venom-drench", "acupressure", "psych-up", "topsy-turvy", "stage-swap", "stat-swap",
    "baton-pass", "metronome", "assist",
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
# They pass a Substitute.
SOUND_MOVES = frozenset(int(move_id) for move_id, entry in battle_data.table("moves").items()
                        if "sound" in entry.get("flags", ()))
# Grass types are immune to them.
POWDER_MOVES = frozenset(int(move_id) for move_id, entry in battle_data.table("moves").items()
                         if "powder" in entry.get("flags", ()))

STATUS_MOVES = {move_id: key for key in STATUS_EFFECTS for move_id in battle_data.with_key("moves", key)}
EFFECTS = {**STATUS_MOVES, **{move_id: key for key in DAMAGE_EFFECTS for move_id in battle_data.with_key("moves", key)}}


def wants_status_moves(move_ids) -> bool:
    """Whether a chosen move list names a status move, so its learnset lookup must include them."""
    return any(move_id in STATUS_MOVES for move_id in move_ids or ())
