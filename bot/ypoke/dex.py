"""The dex summary the app sends beside the party. Contract: bot/API.md."""

NATIONAL_TOTAL = 1025
# region id -> (Korean name, species count); the ids and ranges are the app's PokedexRegion.
REGIONS = {
    "kanto": ("관동", 151), "johto": ("성도", 100), "hoenn": ("호연", 135), "sinnoh": ("신오", 107),
    "unova": ("하나", 156), "kalos": ("칼로스", 72), "alola": ("알로라", 88), "galar": ("가라르", 96),
    "paldea": ("팔데아", 120),
}


BAR_CELLS = 10
FALLBACK_PER_LINE = 3
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


def progress(summary: dict) -> list[tuple[str, int, int]]:
    """(label, owned, total) per region in National Dex order, then 전국. A region the app left out counts as 0."""
    rows = [(name, summary["regions"].get(key, 0), total) for key, (name, total) in REGIONS.items()]
    return rows + [("전국", summary["owned"], NATIONAL_TOTAL)]


def percent(owned: int, total: int) -> int:
    """Rounded half up; a started set never reads 0% and an unfinished one never reads 100%."""
    return _scaled(owned, total, 100)


def bar(owned: int, total: int) -> str:
    filled = _scaled(owned, total, BAR_CELLS)
    return "▰" * filled + "▱" * (BAR_CELLS - filled)


def _scaled(owned: int, total: int, scale: int) -> int:
    value = (owned * scale * 2 + total) // (total * 2)
    if owned >= total:
        return scale
    return min(max(value, 1 if owned else 0), scale - 1)


def progress_fields(summary: dict) -> list[str]:
    """One Block Kit section field per row of `progress`, two lines each."""
    return [
        f"*{name}*  {owned}/{total}{' ✅' if owned == total else ''}\n{bar(owned, total)} {percent(owned, total)}%"
        for name, owned, total in progress(summary)
    ]


def progress_lines(summary: dict) -> list[str]:
    """The plain-text fallback: `FALLBACK_PER_LINE` regions a line."""
    cells = [f"{name} {owned}/{total}{' ✅' if owned == total else ''}" for name, owned, total in progress(summary)]
    return [" · ".join(cells[start:start + FALLBACK_PER_LINE]) for start in range(0, len(cells), FALLBACK_PER_LINE)]
