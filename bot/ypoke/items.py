"""Held items: PokéAPI item slugs the battle simulation understands. Anything else is ignored."""

LEFTOVERS = "leftovers"
CHOICE_SCARF = "choice-scarf"
CHOICE_BAND = "choice-band"
FOCUS_SASH = "focus-sash"
LIFE_ORB = "life-orb"
EXPERT_BELT = "expert-belt"
CHARCOAL = "charcoal"

ITEM_NAMES = {
    LEFTOVERS: "먹다남은음식",
    CHOICE_SCARF: "구애스카프",
    CHOICE_BAND: "구애머리띠",
    FOCUS_SASH: "기합의띠",
    LIFE_ORB: "생명의구슬",
    EXPERT_BELT: "달인의띠",
    CHARCOAL: "목탄",
}
CHOICE_ITEMS = frozenset({CHOICE_SCARF, CHOICE_BAND})
TYPE_BOOST_ITEMS = {CHARCOAL: "fire"}
LEFTOVERS_FRACTION = 16
LIFE_ORB_RECOIL_FRACTION = 10
CHOICE_MULTIPLIER = 1.5
LIFE_ORB_MULTIPLIER = 1.3
BOOST_MULTIPLIER = 1.2


def known(item: str | None) -> str | None:
    return item if item in ITEM_NAMES else None


def stat_multiplier(item: str | None, key: str) -> float:
    if item == CHOICE_SCARF and key == "speed" or item == CHOICE_BAND and key == "attack":
        return CHOICE_MULTIPLIER
    return 1.0


def damage_multiplier(item: str | None, move_type: str | None, effectiveness: float) -> float:
    if item == LIFE_ORB:
        return LIFE_ORB_MULTIPLIER
    if item == EXPERT_BELT and effectiveness > 1:
        return BOOST_MULTIPLIER
    if move_type is not None and TYPE_BOOST_ITEMS.get(item) == move_type:
        return BOOST_MULTIPLIER
    return 1.0
