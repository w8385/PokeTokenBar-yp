"""Terastal-only forms as items: Ogerpon's masks and Terapagos' Terastal and Stellar forms (`/pokemon` ids)."""

from ypoke import items

OGERPON = 1017
TERAPAGOS = 1024
TERASTAL_FORM = 10276
STELLAR_FORM = 10277

# mask slug -> (form `/pokemon` id or None when the base form already wears it, stat raised by 1 stage on entry)
MASKS: dict[str, tuple[int | None, str]] = {
    "teal-mask": (None, "speed"),
    "wellspring-mask": (10273, "special_defense"),
    "hearthflame-mask": (10274, "attack"),
    "cornerstone-mask": (10275, "defense"),
}


def usable_item(item: str | None, pokemon_id: int) -> str | None:
    """A mask works only on Ogerpon and the Stellar Crystal only on Terapagos; on anyone else it does nothing."""
    if item in items.OGERPON_MASKS and pokemon_id != OGERPON:
        return None
    if item == items.STELLAR_CRYSTAL and pokemon_id != TERAPAGOS:
        return None
    return item
