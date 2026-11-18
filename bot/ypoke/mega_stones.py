"""Mega Stones: held-item slug -> (base `/pokemon` id, Mega form `/pokemon` id). One stone per Pokémon with a Mega form."""

from ypoke import battle_data

MEGA_STONE = "mega-stone"
PRIMAL_ORB = "primal-orb"
ULTRA_BURST = "ultra-burst"
DRAGON_ASCENT = "dragon-ascent"
ITEM_EFFECT_KEYS = frozenset({MEGA_STONE, PRIMAL_ORB, ULTRA_BURST})


def _forms(kind: str, key: str) -> dict:
    return {name: (entry["args"]["species"], entry["args"]["form"])
            for name, entry in battle_data.with_key(kind, key).items()}


MEGA_STONES: dict[str, tuple[int, int]] = _forms("items", MEGA_STONE)
# Primal Reversion works like a Mega Evolution here and takes the same once-per-battle slot.
PRIMAL_ORBS: dict[str, tuple[int, int]] = _forms("items", PRIMAL_ORB)
# Ultra Burst also takes the Mega Evolution slot.
ULTRA_BURSTS: dict[str, tuple[int, int]] = _forms("items", ULTRA_BURST)
# species -> (the move that lets it Mega Evolve with no stone, its Mega form `/pokemon` id)
MOVE_MEGAS = {species: (move_id, form) for move_id, (species, form) in _forms("moves", DRAGON_ASCENT).items()}


def move_mega_form_id(pokemon_id: int, move_ids: tuple[int, ...], item: str | None) -> int | None:
    """Mega Rayquaza: the Mega form id when the Pokémon knows its move and holds no Mega Stone, else None."""
    entry = MOVE_MEGAS.get(pokemon_id)
    if entry is None or entry[0] not in move_ids or item in MEGA_STONES:
        return None
    return entry[1]


def mega_form_id(item: str | None, pokemon_id: int) -> int | None:
    """The Mega (Primal, Ultra) form `/pokemon` id when `item` is the stone, orb or crystal of `pokemon_id`, else None."""
    entry = MEGA_STONES.get(item or "") or PRIMAL_ORBS.get(item or "") or ULTRA_BURSTS.get(item or "")
    return entry[1] if entry and entry[0] == pokemon_id else None
