"""Forms a held item brings: Ogerpon's masks, Terapagos' Terastal and Stellar forms, the origin items of Dialga,
Palkia and Giratina, the rusted items of Zacian and Zamazenta and Arceus' plates (`/pokemon` ids)."""

from ypoke import battle_data, items

OGERPON = 1017
TERAPAGOS = 1024
TERASTAL_FORM = 10276
STELLAR_FORM = 10277
STELLAR_ABILITY = "teraform-zero"
ARCEUS = 493
FORM_ITEM = "form-item"
OGERPON_MASK = "ogerpon-mask"
EFFECT_KEYS = frozenset({FORM_ITEM, OGERPON_MASK, items.STELLAR_CRYSTAL})
# item slug -> (species it works on, the form's `/pokemon` id, the form's kind)
ITEM_FORMS = {slug: (entry["args"]["species"], entry["args"]["form"], entry["args"]["form_kind"])
              for slug, entry in battle_data.with_key("items", FORM_ITEM).items()}

# mask slug -> (form `/pokemon` id or None when the base form already wears it, stat raised by 1 stage on entry)
MASKS: dict[str, tuple[int | None, str]] = {
    slug: (entry["args"]["form"], entry["args"]["stat"])
    for slug, entry in battle_data.with_key("items", OGERPON_MASK).items()
}


def usable_item(item: str | None, pokemon_id: int) -> str | None:
    """A mask works only on Ogerpon, the Stellar Crystal only on Terapagos and an origin or rusted item only on its own
    species; on anyone else it does nothing."""
    if item in items.OGERPON_MASKS and pokemon_id != OGERPON:
        return None
    if item == items.STELLAR_CRYSTAL and pokemon_id != TERAPAGOS:
        return None
    if item in ITEM_FORMS and ITEM_FORMS[item][0] != pokemon_id:
        return None
    return item
