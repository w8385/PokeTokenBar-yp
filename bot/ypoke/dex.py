"""The dex summary the app sends beside the party. Contract: bot/API.md."""

NATIONAL_TOTAL = 1025
# region id -> (Korean name, species count); the ids and ranges are the app's PokedexRegion.
REGIONS = {
    "kanto": ("관동", 151), "johto": ("성도", 100), "hoenn": ("호연", 135), "sinnoh": ("신오", 107),
    "unova": ("하나", 156), "kalos": ("칼로스", 72), "alola": ("알로라", 88), "galar": ("가라르", 96),
    "paldea": ("팔데아", 120),
}


_SPRITES = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork"


def sprite_url(pokemon_id: int, shiny: bool) -> str:
    return f"{_SPRITES}/{'shiny/' if shiny else ''}{pokemon_id}.png"


def normalize_dex(payload: dict) -> dict | None:
    """The valid `dex` of an upload body, or None. Bad parts are dropped, never rejected: it must not fail the party."""
    dex = payload.get("dex")
    if not isinstance(dex, dict) or not (_count(dex.get("owned"), NATIONAL_TOTAL) and _count(dex.get("shiny"), NATIONAL_TOTAL)):
        return None
    regions = dex.get("regions")
    regions = regions if isinstance(regions, dict) else {}
    normalized = {
        "owned": dex["owned"],
        "shiny": dex["shiny"],
        "regions": {key: regions[key] for key, (_, total) in REGIONS.items() if _count(regions.get(key), total)},
    }
    representative = dex.get("representative")
    if isinstance(representative, dict) and _valid_pokemon_id(representative.get("pokemon_id")):
        normalized["representative"] = {
            "pokemon_id": representative["pokemon_id"], "shiny": representative.get("shiny") is True,
        }
    return normalized


def _count(value: object, limit: int) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= limit


def _valid_pokemon_id(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and (1 <= value <= 1025 or 10001 <= value <= 10999)
