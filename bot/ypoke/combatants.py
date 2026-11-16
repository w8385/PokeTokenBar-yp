"""Turn an uploaded party member into a battle `Combatant`."""

from ypoke import items, tera_forms
from ypoke.battle import BATTLE_LEVEL, BaseStats, Combatant, MegaForm
from ypoke.mega_stones import mega_form_id
from ypoke.moves import battle_moves
from ypoke.pokeapi import PokeAPIService, base_stats
from ypoke.upload_server import IV_KEYS

DEFAULT_IV = 15


def combatant(pokeapi: PokeAPIService, member: dict) -> Combatant:
    """Raises OSError when PokéAPI is down."""
    pokemon_id = member["pokemon_id"]
    item = tera_forms.usable_item(member.get("held_item"), pokemon_id)
    data = _form_data(pokeapi, pokemon_id, item)
    learnable = pokeapi.attacking_moves(pokemon_id, member["level"], member.get("moves") or ())
    ivs = {key: member["ivs"].get(key, DEFAULT_IV) for key in IV_KEYS}
    return Combatant(
        name=member.get("name") or data["name_ko"],
        level=min(member["level"], BATTLE_LEVEL),
        types=tuple(data["types"]),
        base=base_stats(data),
        ivs=BaseStats(**ivs),
        shiny=member["shiny"],
        moves=battle_moves(learnable, member.get("moves")),
        rental=member.get("rental", False),
        nature=member.get("nature"),
        ability=member.get("ability"),
        item=item,
        mega=_mega(pokeapi, pokemon_id, item),
        pokemon_id=pokemon_id,
        can_evolve=_can_evolve(pokeapi, member),
        tera=pokemon_id == tera_forms.TERAPAGOS,
    )


def _form_data(pokeapi: PokeAPIService, pokemon_id: int, item: str | None) -> dict:
    """The `pokemon()` data the Pokémon fights with: its own, Ogerpon's with the mask's form, Terapagos' Terastal
    form. The name stays the species' own."""
    data = pokeapi.pokemon(pokemon_id)
    form_id = tera_forms.TERASTAL_FORM if pokemon_id == tera_forms.TERAPAGOS else None
    if item in tera_forms.MASKS:
        form_id = tera_forms.MASKS[item][0]
    if form_id is None:
        return data
    return {**data, **{key: value for key, value in pokeapi.pokemon(form_id).items() if key != "name_ko"}}


def _can_evolve(pokeapi: PokeAPIService, member: dict) -> bool:
    """Only Eviolite needs it; a failed lookup counts as fully evolved rather than failing the battle."""
    if member.get("held_item") != items.EVIOLITE:
        return False
    try:
        return pokeapi.can_evolve(member["pokemon_id"])
    except (OSError, ValueError, KeyError, TypeError):
        return False


def _mega(pokeapi: PokeAPIService, pokemon_id: int, item: str | None) -> MegaForm | None:
    if item == items.STELLAR_CRYSTAL:
        data = pokeapi.pokemon(tera_forms.STELLAR_FORM)
        return MegaForm(types=tuple(data["types"]), base=base_stats(data), form_id=tera_forms.STELLAR_FORM,
                        kind="stellar")
    form_id = mega_form_id(item, pokemon_id)
    if form_id is None:
        return None
    data = pokeapi.mega_form(form_id)
    return MegaForm(types=tuple(data["types"]), base=base_stats(data), ability=data["ability"],
                    ability_id=data["ability_id"], form_id=form_id)
