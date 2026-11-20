"""The lineup rules every battle applies to an uploaded party, whatever app sent it.

Species clause: one Pokémon per national species, so forms, regional forms and Megas of one species count once.
Item clause: one holder per held item; a later member holding the same item fights without it. A species-bound item
(a mask, an origin item) counts only on its own species, where it does something. Both keep the first in order.
"""

import json
from dataclasses import dataclass
from pathlib import Path

from ypoke.tera_forms import usable_item

SPECIES_NOTE = "같은 포켓몬이 여럿이라 한 마리씩만 나왔어요"
ITEM_NOTE = "같은 도구는 한 마리만 들고 나왔어요"
FORM_SPECIES = {int(key): value for key, value in
                json.loads(Path(__file__).with_name("form_species.json").read_text()).items()}


@dataclass(frozen=True)
class Lineup:
    """`members` is the party in its order with duplicate items taken off; `kept` are the indices that fight."""

    members: tuple[dict, ...]
    kept: tuple[int, ...]
    unequipped: tuple[int, ...]

    @property
    def fighters(self) -> list[dict]:
        return [self.members[index] for index in self.kept]

    def notes(self, trainer: str, size: int) -> tuple[str, ...]:
        """The card lines saying what the rules changed among the first `size` fighters of `trainer`'s side."""
        taken = self.kept[:size]
        dropped = taken != tuple(range(min(size, len(self.members))))
        unequipped = any(index in taken for index in self.unequipped)
        return tuple(f"{trainer}: {note}" for note, applied in ((SPECIES_NOTE, dropped), (ITEM_NOTE, unequipped))
                     if applied)


def lineup(party: list[dict]) -> Lineup:
    """The species clause, then the item clause among the members that are left."""
    kept = _first_of_each_species(party)
    members = [dict(member) for member in party]
    unequipped = _take_off_duplicate_items(members, kept)
    return Lineup(tuple(members), kept, unequipped)


def _first_of_each_species(party: list[dict]) -> tuple[int, ...]:
    seen: set[int] = set()
    kept = []
    for index, member in enumerate(party):
        species = species_id(member["pokemon_id"])
        if species not in seen:
            seen.add(species)
            kept.append(index)
    return tuple(kept)


def species_id(pokemon_id: int) -> int:
    """The national species of a `/pokemon` id; an id the table does not know counts as its own species."""
    return FORM_SPECIES.get(pokemon_id, pokemon_id)


def _take_off_duplicate_items(members: list[dict], kept: tuple[int, ...]) -> tuple[int, ...]:
    seen: set[str] = set()
    unequipped = []
    for index in kept:
        item = usable_item(members[index].get("held_item"), members[index]["pokemon_id"])
        if item is None:
            continue
        if item in seen:
            del members[index]["held_item"]
            unequipped.append(index)
        else:
            seen.add(item)
    return tuple(unequipped)
