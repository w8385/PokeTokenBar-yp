"""Forms a held item brings: Ogerpon's masks, Terapagos' Terastal and Stellar forms, the origin items of Dialga,
Palkia and Giratina and Arceus' plates (`/pokemon` ids)."""

from ypoke import items

OGERPON = 1017
TERAPAGOS = 1024
TERASTAL_FORM = 10276
STELLAR_FORM = 10277
ARCEUS = 493
# item slug -> (species it works on, its Origin Forme `/pokemon` id)
ORIGIN_FORMS = {"adamant-crystal": (483, 10245), "lustrous-globe": (484, 10246), "griseous-core": (487, 10007)}

# mask slug -> (form `/pokemon` id or None when the base form already wears it, stat raised by 1 stage on entry)
MASKS: dict[str, tuple[int | None, str]] = {
    "teal-mask": (None, "speed"),
    "wellspring-mask": (10273, "special_defense"),
    "hearthflame-mask": (10274, "attack"),
    "cornerstone-mask": (10275, "defense"),
}


def usable_item(item: str | None, pokemon_id: int) -> str | None:
    """A mask works only on Ogerpon, the Stellar Crystal only on Terapagos and an origin item only on its own
    species; on anyone else it does nothing."""
    if item in items.OGERPON_MASKS and pokemon_id != OGERPON:
        return None
    if item == items.STELLAR_CRYSTAL and pokemon_id != TERAPAGOS:
        return None
    if item in ORIGIN_FORMS and ORIGIN_FORMS[item][0] != pokemon_id:
        return None
    return item
