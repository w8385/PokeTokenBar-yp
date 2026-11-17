"""The held items of a PvE team: one per member, none twice in a team, each one whose effect fires for its holder.

Foes have no ability, so an item that only pays off with one (Flame Orb, Toxic Orb) is never given.
"""

from collections.abc import Sequence
from dataclasses import dataclass

from ypoke import items, tera_forms
from ypoke.foe_moves import FoeMove, score
from ypoke.mega_stones import mega_form_id

FRAIL_BULK = 190
BULKY_BULK = 260
STRONG_OFFENSE = 100

_ALWAYS = frozenset({
    items.LIFE_ORB, items.EXPERT_BELT, items.ASSAULT_VEST, items.LEFTOVERS, items.SITRUS_BERRY, items.LUM_BERRY,
    items.FOCUS_SASH, items.ROCKY_HELMET, items.SHELL_BELL, items.SCOPE_LENS, items.RAZOR_CLAW,
    items.QUICK_CLAW, items.BRIGHT_POWDER, items.WEAKNESS_POLICY, items.CHOICE_SCARF,
})


@dataclass(frozen=True)
class Holder:
    species_id: int
    types: tuple[str, ...]
    stats: dict[str, int]
    moves: tuple[FoeMove, ...]
    can_evolve: bool


def assign(holders: Sequence[Holder]) -> list[str]:
    """An item per holder, in order. The holders with the highest base-stat totals choose first."""
    order = sorted(range(len(holders)), key=lambda index: (-sum(holders[index].stats.values()), index))
    taken: set[str] = set()
    chosen: dict[int, str] = {}
    for index in order:
        item = next((item for item in wishes(holders[index]) if item not in taken and fires(item, holders[index])),
                    items.QUICK_CLAW if items.QUICK_CLAW not in taken else items.BRIGHT_POWDER)
        taken.add(item)
        chosen[index] = item
    return [chosen[index] for index in range(len(holders))]


def wishes(holder: Holder) -> list[str]:
    """The items `holder` wants, best first."""
    stats = holder.stats
    physical = stats["attack"] >= stats["special_attack"]
    offense = max(stats["attack"], stats["special_attack"])
    bulk = stats["hp"] + (stats["defense"] + stats["special_defense"]) // 2
    choice = items.CHOICE_BAND if physical else items.CHOICE_SPECS
    band = items.MUSCLE_BAND if physical else items.WISE_GLASSES
    boosts = [item for kind in boosted_types(holder) for item, boosted in items.TYPE_BOOST_ITEMS.items()
              if boosted == kind]
    leftovers = items.BLACK_SLUDGE if "poison" in holder.types else items.LEFTOVERS
    wanted: list[str] = [items.EVIOLITE] if holder.can_evolve else []
    if bulk < FRAIL_BULK and offense >= STRONG_OFFENSE:
        wanted += [items.FOCUS_SASH, items.LIFE_ORB, choice, *boosts[:1], items.EXPERT_BELT]
    elif bulk < FRAIL_BULK:
        wanted += [items.FOCUS_SASH, *boosts[:1], items.SITRUS_BERRY]
    elif bulk >= BULKY_BULK and offense < bulk // 2:
        wanted += [leftovers, items.ASSAULT_VEST, items.SITRUS_BERRY, items.ROCKY_HELMET, items.LUM_BERRY]
    elif offense >= STRONG_OFFENSE:
        wanted += [choice, items.LIFE_ORB, *boosts[:1], items.EXPERT_BELT, items.WEAKNESS_POLICY, band]
    else:
        wanted += [items.ASSAULT_VEST, items.SITRUS_BERRY, *boosts[:1], leftovers, items.SHELL_BELL, band]
    wanted += [items.LUM_BERRY, items.SCOPE_LENS, items.SHELL_BELL, items.WIDE_LENS, *boosts[1:]]
    return wanted


def fires(item: str, holder: Holder) -> bool:
    """Whether `item` does anything for `holder` in the simulation."""
    if items.known(item) is None and mega_form_id(item, holder.species_id) is None:
        return False
    attacking = bool(holder.moves)
    if item == items.EVIOLITE:
        return holder.can_evolve
    if item == items.BLACK_SLUDGE:
        return "poison" in holder.types
    if item in items.TYPE_BOOST_ITEMS:
        return any(move.type == items.TYPE_BOOST_ITEMS[item] for move in holder.moves)
    if item in (items.CHOICE_BAND, items.MUSCLE_BAND):
        return any(move.physical for move in holder.moves)
    if item in (items.CHOICE_SPECS, items.WISE_GLASSES):
        return any(not move.physical for move in holder.moves)
    if item == items.WIDE_LENS:
        return any(move.accuracy is not None and move.accuracy < 100 for move in holder.moves)
    if item in items.OGERPON_MASKS or item == items.STELLAR_CRYSTAL:
        return tera_forms.usable_item(item, holder.species_id) is not None
    if mega_form_id(item, holder.species_id) is not None:
        return True
    return attacking and item in _ALWAYS


def boosted_types(holder: Holder) -> list[str]:
    """The move types a type-boost item may serve, best first: the holder's strongest move, then its own types."""
    ranked = sorted(holder.moves, key=lambda move: (-score(move, holder.types, holder.stats["attack"],
                                                          holder.stats["special_attack"]), move.id))
    kinds = [move.type for index, move in enumerate(ranked) if index == 0 or move.type in holder.types]
    return list(dict.fromkeys(kinds))
