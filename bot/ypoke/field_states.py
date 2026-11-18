"""Field and side states by their effect keys (`data/battle/moves.json`), with the Gen 9 numbers their handlers
(`ypoke.effects.field`) use. A terrain or Gravity covers the whole field; a screen, Tailwind, Safeguard, Mist or Lucky
Chant covers the side that set it; a hazard lies on the side of the foe that set it."""

from ypoke import battle_data

TERRAINS = ("electric-terrain", "grassy-terrain", "psychic-terrain", "misty-terrain")
SCREENS = ("reflect", "light-screen", "aurora-veil")
SIDE_STATES = (*SCREENS, "tailwind", "safeguard", "mist", "lucky-chant")
HAZARDS = ("stealth-rock", "spikes", "toxic-spikes", "sticky-web")
MAX_LAYERS = {"stealth-rock": 1, "spikes": 3, "toxic-spikes": 2, "sticky-web": 1}
STATE_TURNS = 5
TAILWIND_TURNS = 4
GRAVITY_TURNS = 5
ROOM_TURNS = 5
EXTENDED_TURNS = 8
SCREEN_MULTIPLIER = 0.5
TAILWIND_SPEED = 2
TERRAIN_BOOST = 5325 / 4096
TERRAIN_HALVED = 0.5
GRAVITY_ACCURACY = 6840 / 4096
GRASSY_HEAL_FRACTION = 16
SPIKES_DAMAGE = (0, 3, 4, 6)
SPIKES_DENOMINATOR = 24
TOXIC_SPIKES_TOXIC_LAYERS = 2
TERRAIN_TYPES = {"electric-terrain": "electric", "grassy-terrain": "grass", "psychic-terrain": "psychic",
                 "misty-terrain": "fairy"}
# Move key: (the terrain it needs, None for any; whose grounding counts, None for nobody's; power multiplier).
TERRAIN_POWER = {
    "rising-voltage": ("electric-terrain", "target", 2.0),
    "expanding-force": ("psychic-terrain", "user", 1.5),
    "misty-explosion": ("misty-terrain", "user", 1.5),
    "psyblade": ("electric-terrain", None, 1.5),
    "terrain-pulse": (None, "user", 2.0),
}
HAZARD_ON_HIT = {"stone-axe": "stealth-rock", "ceaseless-edge": "spikes"}
DEFOGGED = (*SCREENS, "safeguard", "mist")
DEFOG_EVASION = -1
VEIL_WEATHERS = ("hail", "snow")
AI_AILMENT_CHANCE = 30
AI_DROP_CHANCE = 50
AI_HAZE_STAGES = 2
EARTHQUAKE = 89
MAGNITUDE = 222
BULLDOZE = 523
GRASSY_HALVED_MOVES = frozenset({EARTHQUAKE, MAGNITUDE, BULLDOZE})
# Gravity grounds these moves: they cannot be used while it lasts.
GRAVITY_MOVES = frozenset(int(move_id) for move_id, entry in battle_data.table("moves").items()
                          if "gravity" in entry.get("flags", ()))
