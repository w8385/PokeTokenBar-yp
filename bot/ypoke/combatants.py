"""Turn an uploaded party member into a battle `Combatant`."""

from dataclasses import replace

from ypoke import abilities, items, tera_forms
from ypoke.battle import BATTLE_LEVEL, BaseStats, Combatant, MegaForm, Move
from ypoke.mega_stones import PRIMAL_ORBS, ULTRA_BURSTS, mega_form_id, move_mega_form_id
from ypoke.moves import battle_moves
from ypoke.move_effects import IVY_CUDGEL, JUDGMENT, wants_status_moves
from ypoke.pokeapi import PokeAPIService, base_stats
from ypoke.upload_server import IV_KEYS

DEFAULT_IV = 15


def combatant(pokeapi: PokeAPIService, member: dict) -> Combatant:
    """Raises OSError when PokéAPI is down."""
    pokemon_id = member["pokemon_id"]
    item = tera_forms.usable_item(member.get("held_item"), pokemon_id)
    data = _form_data(pokeapi, pokemon_id, item)
    chosen = member.get("moves") or ()
    learnable = pokeapi.attacking_moves(pokemon_id, member.get("learned_at", member["level"]), chosen,
                                        **({"status": True} if wants_status_moves(chosen) else {}),
                                        **({"egg": True} if member.get("mirror_herb") else {}))
    ivs = {key: member["ivs"].get(key, DEFAULT_IV) for key in IV_KEYS}
    moves = battle_moves(learnable, member.get("moves"))
    types = tuple(data["types"])
    plate = items.PLATES.get(item) if pokemon_id == tera_forms.ARCEUS else None
    if plate is not None:
        types = (plate,)
        moves = _retyped(moves, JUDGMENT, plate)
    if pokemon_id == tera_forms.OGERPON and len(types) > 1:
        moves = _retyped(moves, IVY_CUDGEL, types[1])
    return Combatant(
        name=member.get("name") or data["name_ko"],
        level=min(member["level"], BATTLE_LEVEL),
        types=types,
        base=base_stats(data),
        ivs=BaseStats(**ivs),
        shiny=member["shiny"],
        moves=moves,
        rental=member.get("rental", False),
        nature=member.get("nature"),
        ability=data.get("ability_id") if data.get("ability_id") in abilities.NAMES else member.get("ability"),
        item=item,
        mega=_mega(pokeapi, pokemon_id, item, tuple(move.id for move in moves)),
        pokemon_id=pokemon_id,
        can_evolve=_can_evolve(pokeapi, member),
        tera=pokemon_id == tera_forms.TERAPAGOS,
        weight=data.get("weight", 0),
    )


def _retyped(moves: tuple[Move, ...], move_id: int, kind: str) -> tuple[Move, ...]:
    return tuple(replace(move, type=kind) if move.id == move_id else move for move in moves)


def _form_data(pokeapi: PokeAPIService, pokemon_id: int, item: str | None) -> dict:
    """The `pokemon()` data the Pokémon fights with: its own, Ogerpon's with the mask's form, Terapagos' Terastal
    form, an origin or rusted item's form (with its first ability as `"ability_id"`). The name stays the species' own."""
    data = pokeapi.pokemon(pokemon_id)
    if item in tera_forms.ITEM_FORMS:
        return {**data, **{key: value for key, value in pokeapi.mega_form(tera_forms.ITEM_FORMS[item][1]).items()
                           if key != "name_ko"}}
    form_id = tera_forms.TERASTAL_FORM if pokemon_id == tera_forms.TERAPAGOS else None
    if item in tera_forms.MASKS:
        form_id = tera_forms.MASKS[item][0]
    if form_id is None:
        return data
    return {**data, **{key: value for key, value in pokeapi.pokemon(form_id).items() if key != "name_ko"}}


def _can_evolve(pokeapi: PokeAPIService, member: dict) -> bool:
    """Only Eviolite needs it; a failed lookup counts as fully evolved rather than failing the battle. A PvE foe
    brings its own answer."""
    if member.get("held_item") != items.EVIOLITE:
        return False
    if "can_evolve" in member:
        return member["can_evolve"]
    try:
        return pokeapi.can_evolve(member["pokemon_id"])
    except (OSError, ValueError, KeyError, TypeError):
        return False


def _mega(pokeapi: PokeAPIService, pokemon_id: int, item: str | None, move_ids: tuple[int, ...]) -> MegaForm | None:
    if item == items.STELLAR_CRYSTAL:
        data = pokeapi.pokemon(tera_forms.STELLAR_FORM)
        return MegaForm(types=tuple(data["types"]), base=base_stats(data), form_id=tera_forms.STELLAR_FORM,
                        kind="stellar")
    form_id = mega_form_id(item, pokemon_id) or move_mega_form_id(pokemon_id, move_ids, item)
    if form_id is None:
        return None
    data = pokeapi.mega_form(form_id)
    return MegaForm(types=tuple(data["types"]), base=base_stats(data), ability=data["ability"],
                    ability_id=data["ability_id"], form_id=form_id, kind=_mega_kind(item))


def _mega_kind(item: str | None) -> str:
    if item in PRIMAL_ORBS:
        return "primal"
    return "ultra" if item in ULTRA_BURSTS else "mega"
