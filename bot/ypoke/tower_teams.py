"""The battle tower's archetype teams from set 3: competitive team styles built from generic roles, not copied teams.

A family names a role per slot. A team fills each slot with a build of that role: its species, item, moves, ability
and nature, chosen near the set's base-stat target. Every build is our own set for its role.
"""

import random
from typing import NamedTuple

from ypoke.gyms import QUASI_LEGENDARY, SPREAD, _related, species_table

FIRST_SET = 3


class Build(NamedTuple):
    species: int
    item: str
    moves: tuple[int, ...]
    ability: str
    nature: str
    roles: tuple[str, ...]


# Each family lists its slots; a slot takes a build with any of its roles.
FAMILIES = {
    "face": (("hitter",), ("hitter",), ("hitter",)),
    "lead": (("lead",), ("sweeper",), ("sweeper", "hitter")),
    "cycle": (("pivot",), ("pivot",), ("pivot",)),
    "trick-room": (("room-setter",), ("room-hitter",), ("room-hitter",)),
    "rain": (("rain-setter",), ("rain",), ("rain",)),
    "sun": (("sun-setter",), ("sun",), ("sun",)),
    "sand": (("sand-setter",), ("sand",), ("sand",)),
    "snow": (("snow-setter",), ("snow",), ("snow",)),
}
STYLES = {"face": ("face",), "lead": ("lead",), "cycle": ("cycle",), "trick-room": ("trick-room",),
          "weather": ("rain", "sun", "sand", "snow")}

BUILDS = (
    Build(445, "life-orb", (89, 337, 444, 424), "rough-skin", "jolly", ("hitter", "sand")),
    Build(448, "focus-sash", (370, 309, 245, 242), "justified", "adamant", ("hitter",)),
    Build(149, "choice-band", (245, 200, 89, 7), "multiscale", "adamant", ("hitter",)),
    Build(635, "choice-specs", (434, 399, 53, 430), "levitate", "timid", ("hitter",)),
    Build(609, "choice-scarf", (247, 126, 412, 94), "flash-fire", "timid", ("hitter", "sun")),
    Build(94, "focus-sash", (247, 188, 411, 85), "cursed-body", "timid", ("hitter",)),
    Build(65, "life-orb", (94, 247, 411, 412), "magic-guard", "timid", ("hitter",)),
    Build(908, "choice-band", (870, 282, 369, 583), "protean", "jolly", ("hitter", "pivot")),
    Build(887, "choice-specs", (434, 247, 126, 85), "infiltrator", "timid", ("hitter",)),
    Build(1000, "choice-scarf", (874, 247, 411, 85), "good-as-gold", "timid", ("hitter",)),
    Build(212, "choice-band", (418, 369, 282, 370), "technician", "adamant", ("hitter", "pivot")),
    Build(461, "focus-sash", (282, 420, 813, 67), "pressure", "jolly", ("hitter", "snow")),
    Build(376, "assault-vest", (309, 428, 89, 418), "clear-body", "adamant", ("hitter", "room-hitter")),
    Build(663, "focus-sash", (413, 394, 369, 14), "gale-wings", "adamant", ("hitter", "sun")),
    Build(257, "life-orb", (370, 394, 9, 444), "speed-boost", "adamant", ("hitter", "sun")),
    Build(973, "choice-scarf", (413, 370, 369, 675), "scrappy", "jolly", ("hitter", "pivot")),
    Build(373, "lum-berry", (349, 337, 89, 424), "intimidate", "jolly", ("sweeper",)),
    Build(130, "sitrus-berry", (349, 127, 89, 423), "intimidate", "jolly", ("sweeper", "rain")),
    Build(983, "leftovers", (14, 869, 442, 67), "supreme-overlord", "adamant", ("sweeper", "room-hitter")),
    Build(637, "lum-berry", (483, 53, 405, 202), "flame-body", "timid", ("sweeper", "sun")),
    Build(160, "life-orb", (349, 710, 8, 242), "sheer-force", "adamant", ("sweeper", "rain")),
    Build(475, "lum-berry", (14, 533, 348, 427), "sharpness", "jolly", ("sweeper",)),
    Build(248, "weakness-policy", (349, 444, 242, 89), "sand-stream", "adamant", ("sweeper", "sand-setter")),
    Build(778, "life-orb", (14, 583, 421, 425), "disguise", "jolly", ("sweeper",)),
    Build(91, "white-herb", (504, 333, 350, 420), "skill-link", "jolly", ("sweeper", "snow")),
    Build(282, "leftovers", (347, 585, 94, 247), "trace", "timid", ("sweeper",)),
    Build(937, "focus-sash", (14, 891, 370, 809), "flash-fire", "jolly", ("sweeper", "sun")),
    Build(473, "focus-sash", (446, 423, 89, 420), "thick-fat", "jolly", ("lead", "snow")),
    Build(970, "focus-sash", (446, 408, 482, 414), "toxic-debris", "timid", ("lead",)),
    Build(196, "light-clay", (115, 113, 281, 94), "magic-bounce", "timid", ("lead",)),
    Build(553, "focus-sash", (446, 89, 282, 444), "intimidate", "jolly", ("lead", "sand")),
    Build(437, "mental-herb", (433, 446, 360, 89), "levitate", "relaxed", ("lead", "room-setter")),
    Build(823, "leftovers", (369, 355, 413, 776), "pressure", "impish", ("pivot",)),
    Build(80, "rocky-helmet", (503, 303, 94, 281), "regenerator", "bold", ("pivot",)),
    Build(59, "leftovers", (394, 245, 234, 528), "intimidate", "adamant", ("pivot", "sun")),
    Build(36, "life-orb", (585, 273, 53, 446), "magic-guard", "bold", ("pivot", "lead")),
    Build(727, "sitrus-berry", (394, 282, 369, 575), "intimidate", "careful", ("pivot",)),
    Build(591, "black-sludge", (147, 202, 188, 499), "regenerator", "calm", ("pivot", "room-hitter")),
    Build(450, "smooth-rock", (446, 303, 89, 281), "sand-stream", "impish", ("pivot", "sand-setter", "lead")),
    Build(260, "leftovers", (812, 446, 89, 710), "torrent", "relaxed", ("pivot", "rain")),
    Build(186, "damp-rock", (56, 58, 414, 411), "drizzle", "modest", ("rain-setter",)),
    Build(279, "damp-rock", (542, 56, 369, 355), "drizzle", "bold", ("rain-setter",)),
    Build(230, "life-orb", (127, 200, 442, 349), "swift-swim", "adamant", ("rain",)),
    Build(272, "choice-specs", (56, 202, 58, 411), "swift-swim", "modest", ("rain",)),
    Build(834, "white-herb", (504, 710, 444, 242), "swift-swim", "adamant", ("rain",)),
    Build(324, "heat-rock", (284, 76, 414, 446), "drought", "quiet", ("sun-setter", "room-hitter")),
    Build(38, "heat-rock", (126, 76, 473, 417), "drought", "timid", ("sun-setter",)),
    Build(6, "choice-specs", (126, 403, 76, 411), "solar-power", "timid", ("sun",)),
    Build(3, "life-orb", (74, 202, 188, 414), "chlorophyll", "modest", ("sun",)),
    Build(465, "assault-vest", (438, 89, 282, 202), "chlorophyll", "adamant", ("sun",)),
    Build(530, "life-orb", (89, 442, 157, 14), "sand-rush", "adamant", ("sand",)),
    Build(526, "smooth-rock", (446, 444, 89, 153), "sand-stream", "adamant", ("sand-setter", "room-hitter")),
    Build(464, "weakness-policy", (444, 89, 224, 8), "solid-rock", "adamant", ("sand", "room-hitter")),
    Build(460, "icy-rock", (59, 202, 420, 414), "snow-warning", "quiet", ("snow-setter",)),
    Build(614, "life-orb", (556, 276, 453, 14), "slush-rush", "adamant", ("snow",)),
    Build(998, "choice-band", (556, 862, 89, 420), "thermal-exchange", "adamant", ("snow",)),
    Build(873, "lum-berry", (483, 59, 405, 202), "ice-scales", "timid", ("snow",)),
    Build(579, "life-orb", (433, 94, 411, 247), "magic-guard", "quiet", ("room-setter",)),
    Build(858, "mental-herb", (433, 94, 605, 247), "magic-bounce", "quiet", ("room-setter",)),
    Build(563, "leftovers", (433, 247, 261, 776), "mummy", "relaxed", ("room-setter",)),
    Build(143, "choice-band", (34, 89, 242, 484), "thick-fat", "brave", ("room-hitter",)),
    Build(534, "flame-orb", (409, 370, 282, 8), "guts", "brave", ("room-hitter",)),
    Build(901, "toxic-orb", (838, 263, 242, 7), "guts", "brave", ("room-hitter",)),
    Build(68, "expert-belt", (223, 282, 444, 89), "no-guard", "brave", ("room-hitter",)),
    Build(477, "leftovers", (809, 89, 8, 425), "pressure", "brave", ("room-hitter",)),
    Build(750, "assault-vest", (667, 484, 370, 157), "stamina", "brave", ("room-hitter", "sand")),
    Build(323, "choice-specs", (284, 414, 126, 446), "solid-rock", "quiet", ("room-hitter", "sun")),
    Build(150, "choice-specs", (540, 396, 58, 126), "pressure", "timid", ("hitter",)),
    Build(150, "life-orb", (417, 540, 396, 58), "unnerve", "timid", ("sweeper",)),
    Build(384, "lum-berry", (349, 620, 89, 245), "air-lock", "jolly", ("sweeper",)),
    Build(644, "choice-band", (550, 200, 242, 337), "teravolt", "adamant", ("hitter",)),
    Build(643, "choice-specs", (551, 434, 414, 411), "turboblaze", "modest", ("hitter", "sun")),
    Build(717, "life-orb", (613, 399, 411, 369), "dark-aura", "timid", ("hitter", "pivot")),
    Build(798, "focus-sash", (348, 533, 684, 14), "beast-boost", "jolly", ("hitter", "sweeper")),
    Build(794, "leftovers", (370, 8, 89, 339), "beast-boost", "adamant", ("sweeper",)),
    Build(485, "focus-sash", (446, 463, 414, 430), "flash-fire", "timid", ("lead", "sun")),
    Build(381, "choice-scarf", (434, 94, 57, 396), "levitate", "timid", ("hitter", "rain")),
    Build(645, "life-orb", (89, 444, 157, 14), "sand-force", "jolly", ("sand",)),
    Build(249, "leftovers", (177, 105, 347, 414), "multiscale", "bold", ("pivot",)),
    Build(250, "rocky-helmet", (221, 413, 105, 89), "regenerator", "adamant", ("pivot", "sun")),
    Build(488, "leftovers", (433, 236, 94, 585), "levitate", "relaxed", ("room-setter", "pivot")),
    Build(380, "light-clay", (434, 94, 105, 347), "levitate", "timid", ("pivot",)),
    Build(382, "choice-specs", (323, 618, 87, 58), "drizzle", "modest", ("rain-setter",)),
    Build(383, "life-orb", (619, 535, 444, 14), "drought", "adamant", ("sun-setter",)),
    Build(145, "leftovers", (87, 542, 521, 355), "pressure", "timid", ("rain", "pivot")),
    Build(146, "heat-rock", (126, 542, 76, 355), "flame-body", "timid", ("sun",)),
    Build(144, "icy-rock", (59, 542, 573, 355), "snow-cloak", "timid", ("snow",)),
    Build(646, "choice-specs", (59, 434, 414, 573), "pressure", "modest", ("snow", "hitter")),
    Build(1002, "focus-sash", (556, 389, 533, 420), "sword-of-ruin", "jolly", ("snow", "hitter")),
    Build(1003, "leftovers", (89, 877, 446, 484), "vessel-of-ruin", "brave", ("room-hitter", "lead", "sand")),
    Build(805, "life-orb", (360, 444, 89, 433), "beast-boost", "brave", ("room-hitter", "room-setter")),
    Build(896, "choice-band", (556, 667, 370, 484), "chilling-neigh", "brave", ("room-hitter", "snow")),
    Build(992, "assault-vest", (409, 528, 8, 370), "quark-drive", "brave", ("room-hitter",)),
    Build(799, "leftovers", (242, 525, 484, 89), "beast-boost", "brave", ("room-hitter",)),
    Build(800, "weakness-policy", (722, 89, 444, 433), "prism-armor", "brave", ("room-setter", "room-hitter")),
    Build(480, "light-clay", (433, 446, 94, 281), "levitate", "relaxed", ("lead", "room-setter")),
    Build(716, "power-herb", (601, 585, 411, 605), "fairy-aura", "modest", ("sweeper",)),
    Build(491, "life-orb", (417, 399, 188, 411), "bad-dreams", "timid", ("sweeper",)),
    Build(639, "focus-sash", (370, 444, 14, 442), "justified", "jolly", ("sweeper", "sand")),
    Build(785, "choice-specs", (85, 605, 369, 521), "electric-surge", "timid", ("pivot", "hitter")),
    Build(1007, "choice-scarf", (394, 878, 337, 369), "orichalcum-pulse", "jolly", ("sun-setter",)),
    Build(1008, "choice-specs", (879, 434, 315, 521), "hadron-engine", "timid", ("hitter",)),
    Build(888, "lum-berry", (442, 583, 370, 14), "intrepid-sword", "jolly", ("sweeper",)),
    Build(377, "leftovers", (444, 89, 409, 446), "clear-body", "adamant", ("sand", "room-hitter")),
    Build(792, "leftovers", (714, 473, 347, 236), "shadow-shield", "timid", ("sweeper",)),
)

# The owner's fixed teams, the archetype teams that beat the balance tool's teams most evenly: fast hard hitters for
# silver, a Stealth Rock lead and two setup sweepers with two legendaries for gold.
OWNER_TEAMS = {
    "silver": (
        Build(1000, "choice-scarf", (874, 247, 411, 85), "good-as-gold", "timid", ("hitter",)),
        Build(908, "choice-band", (870, 282, 369, 583), "protean", "jolly", ("hitter",)),
        Build(257, "life-orb", (370, 394, 9, 444), "speed-boost", "adamant", ("hitter",)),
    ),
    "gold": (
        Build(485, "focus-sash", (446, 463, 414, 430), "flash-fire", "timid", ("lead",)),
        Build(888, "lum-berry", (442, 583, 370, 14), "intrepid-sword", "jolly", ("sweeper",)),
        Build(445, "life-orb", (89, 337, 444, 424), "rough-skin", "jolly", ("hitter",)),
    ),
}
OWNER_FAMILIES = {"silver": "face", "gold": "lead"}


def team(rng: random.Random, target: int, legends: int) -> tuple[str, tuple[Build, ...]]:
    """A style's family and its three builds, each nearest the base-stat `target` with some spread, `legends` of them
    legendary. A slot is legendary only where its role has a legendary build."""
    style = rng.choice(sorted(STYLES))
    family = rng.choice(STYLES[style])
    slots = FAMILIES[family]
    open_slots = [index for index, roles in enumerate(slots) if _candidates(roles, True)]
    legend_slots = set(rng.sample(open_slots, min(legends, len(open_slots))))
    chosen: list[Build] = []
    for index, roles in enumerate(slots):
        chosen.append(_fill(rng, roles, index in legend_slots, target, chosen))
    return family, tuple(chosen)


def _fill(rng: random.Random, roles: tuple[str, ...], legend: bool, target: int, chosen: list[Build]) -> Build:
    table = species_table()
    fits = [build for build in _candidates(roles, legend)
            if build.item not in {other.item for other in chosen}
            and not any(build.species == other.species or _related(build.species, other.species, table)
                        for other in chosen)]
    scores = {build: abs(table[build.species].total - target) + SPREAD * rng.random() for build in fits}
    return min(fits, key=lambda build: (scores[build], build.species))


def _candidates(roles: tuple[str, ...], legend: bool) -> list[Build]:
    return [build for build in BUILDS if set(roles) & set(build.roles) and legendary(build.species) == legend]


def legendary(species_id: int) -> bool:
    return species_table()[species_id].excluded or species_id in QUASI_LEGENDARY
