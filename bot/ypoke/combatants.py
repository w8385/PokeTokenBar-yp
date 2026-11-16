"""Turn an uploaded party member into a battle `Combatant`."""

from ypoke import items
from ypoke.battle import BATTLE_LEVEL, BaseStats, Combatant, MegaForm
from ypoke.mega_stones import mega_form_id
from ypoke.moves import battle_moves
from ypoke.pokeapi import PokeAPIService, base_stats
from ypoke.upload_server import IV_KEYS

DEFAULT_IV = 15


def combatant(pokeapi: PokeAPIService, member: dict) -> Combatant:
    """Raises OSError when PokéAPI is down."""
    data = pokeapi.pokemon(member["pokemon_id"])
    learnable = pokeapi.attacking_moves(member["pokemon_id"], member["level"], member.get("moves") or ())
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
        item=member.get("held_item"),
        mega=_mega(pokeapi, member),
        pokemon_id=member["pokemon_id"],
        can_evolve=_can_evolve(pokeapi, member),
    )


def _can_evolve(pokeapi: PokeAPIService, member: dict) -> bool:
    """Only Eviolite needs it; a failed lookup counts as fully evolved rather than failing the battle."""
    if member.get("held_item") != items.EVIOLITE:
        return False
    try:
        return pokeapi.can_evolve(member["pokemon_id"])
    except (OSError, ValueError, KeyError, TypeError):
        return False


def _mega(pokeapi: PokeAPIService, member: dict) -> MegaForm | None:
    form_id = mega_form_id(member.get("held_item"), member["pokemon_id"])
    if form_id is None:
        return None
    data = pokeapi.mega_form(form_id)
    return MegaForm(types=tuple(data["types"]), base=base_stats(data), ability=data["ability"],
                    ability_id=data["ability_id"], form_id=form_id)
