"""Original 64x64 pixel trainer sprites, one per gym, Elite Four, champion, hidden boss and hideout battle.

    python3 scripts/generate-trainer-sprites.py                                # assets/trainers/<battle id>.png
    python3 scripts/generate-trainer-sprites.py --sheet kanto out.png          # contact sheet of one region
    python3 scripts/generate-trainer-sprites.py --sheet kanto out.png --art D  # the same sheet from the PNGs in D
"""

import argparse
import colorsys
import hashlib
import random
import sys
from dataclasses import dataclass, replace
from functools import cache, reduce
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bot"))

from ypoke import gym_data, gyms, tower  # noqa: E402

SIZE = 64
CX = 32
FLOOR = 62
OUTLINE = (24, 18, 32)
WHITE = (248, 246, 240)
EYE_LINE = (36, 24, 32)
GOLD = (226, 178, 58)
SILVER = (200, 206, 220)
SHEET_FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
SHEET_SCALE = 4

TYPE_COLORS = {
    "normal": (176, 168, 140), "fire": (226, 92, 44), "water": (60, 124, 220), "electric": (240, 196, 40),
    "grass": (76, 168, 72), "ice": (120, 204, 220), "fighting": (184, 54, 44), "poison": (150, 72, 170),
    "ground": (200, 160, 88), "flying": (126, 146, 230), "psychic": (238, 88, 146), "bug": (150, 178, 36),
    "rock": (166, 142, 76), "ghost": (104, 82, 150), "dragon": (90, 64, 220), "dark": (84, 70, 64),
    "steel": (150, 156, 178), "fairy": (236, 146, 192),
}
SKINS = ((255, 226, 192), (246, 204, 164), (228, 178, 132), (198, 140, 98), (150, 98, 66), (102, 66, 48))
HAIR_COLORS = (
    (40, 34, 42), (78, 50, 36), (124, 80, 46), (156, 66, 40), (226, 188, 100), (210, 112, 54), (58, 74, 146),
    (42, 134, 138), (74, 140, 84), (114, 74, 156), (228, 128, 168), (198, 202, 216), (180, 48, 60),
)
ELDER_HAIRS = ((216, 216, 222), (162, 162, 170), (238, 238, 242))
EYE_COLORS = ((96, 60, 42), (54, 94, 172), (52, 126, 78), (86, 94, 108), (170, 114, 38), (106, 66, 148))
NEUTRALS = ((236, 228, 208), (64, 66, 80), (72, 96, 148), (178, 158, 114), (240, 240, 244), (114, 84, 64),
            (46, 46, 56), (110, 118, 136))
SHOES = ((54, 46, 60), (120, 80, 56), (236, 236, 240), (44, 52, 82))

FEMALE_HAIR = ("ponytail", "long", "bob", "bun", "twintails", "swept", "curly", "short", "spiky")
MALE_HAIR = ("spiky", "buzz", "swept", "short", "mohawk", "curly", "long", "bun", "ponytail")
CROWN_COVERING = ("cap", "beanie", "sunhat", "hardhat", "bandana", "beret")
POSES = {
    "hips": ("hip", "hip"), "point": ("point", "hip"), "crossed": ("cross", "cross"), "raise": ("raise", "down"),
    "fist": ("fist", "down"), "present": ("present", "hip"),
}
AGES = {"kid": (40, 10, 6), "teen": (48, 13, 7), "adult": (52, 15, 8), "elder": (50, 14, 8)}
SHOULDERS = {"slim": 7, "normal": 8, "broad": 10}
HIPS = {"slim": 5, "normal": 6, "broad": 7}

# Per type: garments to choose from, the prop the leader always carries, the headwear about half of them wear.
GYM_THEMES = {
    "normal": (("cardigan", "tee"), "scarf", "beret"),
    "fire": (("jacket", "tee"), "gloves", "headband"),
    "water": (("wetsuit", "tee"), "belt", "goggles"),
    "electric": (("hoodie", "jacket"), "gloves", "goggles"),
    "grass": (("tee", "overalls"), "apron", "sunhat"),
    "ice": (("coat",), "scarf", "beanie"),
    "fighting": (("gi",), "gloves", "headband"),
    "poison": (("hoodie", "jacket"), "mask", "beanie"),
    "ground": (("overalls", "vest"), "gloves", "bandana"),
    "flying": (("jacket",), "scarf", "goggles"),
    "psychic": (("robe", "dress"), "shawl", "headband"),
    "bug": (("vest", "tee"), "belt", "cap"),
    "rock": (("jacket", "vest"), "gloves", "hardhat"),
    "ghost": (("robe", "cardigan"), "scarf", "beret"),
    "dragon": (("vest", "jacket"), "cape", "headband"),
    "dark": (("jacket", "hoodie"), "gloves", "cap"),
    "steel": (("overalls", "coat"), "gloves", "goggles"),
    "fairy": (("dress", "cardigan"), "belt", "ribbon"),
}
# One per `tower.TRAINERS` row, in order: the trade each trainer dresses for.
TOWER_THEMES = ("rock", "grass", "steel", "fire", "psychic", "flying", "fairy", "water", "ground", "ghost", "normal",
                "electric")
TOWER_OWNER_COAT = 5
CHAMPION_COLORS = (
    ((238, 232, 214), GOLD), ((36, 112, 116), SILVER), ((128, 34, 52), GOLD), ((40, 96, 64), GOLD),
    ((44, 70, 150), SILVER), ((100, 58, 120), SILVER), ((200, 176, 128), (40, 132, 136)), ((70, 80, 98), (204, 120, 70)),
    ((244, 244, 246), (176, 40, 56)),
)
CHAMPION_ACCENTS = ("sash", "epaulettes", "scarf", "sash", "epaulettes", "scarf", "sash", "epaulettes", "scarf")
HIDDEN_GLOWS = ((120, 236, 255), (255, 120, 210), (150, 255, 140), (255, 210, 90), (190, 150, 255),
                (255, 130, 100), (120, 200, 255), (230, 255, 120), (255, 160, 240))
ORG_HEADGEAR = ("beret", "hood", "bandana", "cap", "goggles", "hood", "beret", "bandana", "cap")
ORG_EMBLEMS = ("bolt", "diamond", "chevron", "bars", "star", "hex", "cross", "wave", "fang")
EMBLEMS = {
    "bolt": ((2, 0), (3, 0), (1, 1), (2, 1), (1, 2), (2, 2), (3, 2), (2, 3), (1, 4)),
    "diamond": ((2, 0), (1, 1), (2, 1), (3, 1), (0, 2), (1, 2), (3, 2), (4, 2), (1, 3), (2, 3), (3, 3), (2, 4)),
    "chevron": ((0, 0), (4, 0), (0, 1), (1, 1), (3, 1), (4, 1), (1, 2), (2, 2), (3, 2), (2, 3)),
    "bars": ((0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (1, 4), (2, 4), (3, 4)),
    "star": ((2, 0), (2, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (2, 3), (1, 4), (3, 4)),
    "hex": ((1, 0), (2, 0), (3, 0), (0, 1), (4, 1), (0, 2), (2, 2), (4, 2), (0, 3), (4, 3), (1, 4), (2, 4), (3, 4)),
    "cross": ((0, 0), (4, 0), (1, 1), (3, 1), (2, 2), (1, 3), (3, 3), (0, 4), (4, 4)),
    "wave": ((0, 1), (1, 0), (2, 1), (3, 0), (4, 1), (0, 3), (1, 2), (2, 3), (3, 2), (4, 3)),
    "fang": ((0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (0, 1), (2, 1), (4, 1), (0, 2), (4, 2), (0, 3)),
}


@dataclass(frozen=True)
class Battle:
    id: str
    kind: str
    types: tuple[str, ...]
    label: str


@dataclass(frozen=True)
class Outfit:
    top: tuple
    sleeves: str = "long"
    collar: str = "none"
    outer: tuple | None = None
    outer_length: str = "waist"
    outer_sleeves: bool = True
    bib: tuple | None = None
    lower: str = "pants"
    lower_color: tuple = (64, 66, 92)
    shoes: tuple = SHOES[0]
    boots: bool = False
    belt: tuple | None = None
    gloves: tuple | None = None
    scarf: tuple | None = None
    apron: tuple | None = None
    shawl: tuple | None = None
    cape: tuple | None = None
    tie: tuple | None = None
    sash: tuple | None = None
    epaulettes: tuple | None = None
    trim: tuple | None = None
    emblem: tuple | None = None
    ragged: bool = False


@dataclass(frozen=True)
class Look:
    gender: str
    age: str
    build: str
    skin: tuple
    hair: tuple
    hair_style: str
    eyes: tuple
    pose: str
    mirror: bool
    outfit: Outfit
    headwear: str = "none"
    headwear_color: tuple = (0, 0, 0)
    glasses: tuple | None = None
    mask: tuple | None = None
    facial_hair: str = "none"
    mouth: str = "smile"
    brows: str = "flat"
    glow: tuple | None = None


@dataclass(frozen=True)
class Person:
    gender: str
    skin: tuple
    hair: tuple
    hair_style: str
    eyes: tuple
    build: str
    pose: str
    mirror: bool
    headwear: bool


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sheet", nargs=2, metavar=("REGION", "OUT"), help="write a contact sheet instead")
    parser.add_argument("--art", type=Path, help="with --sheet: lay out the PNGs of this directory instead")
    parser.add_argument("--out", type=Path, default=ROOT / "assets" / "trainers")
    args = parser.parse_args()
    if args.sheet:
        region_id, out = args.sheet
        contact_sheet(region_id, args.art).save(out)
        return
    args.out.mkdir(parents=True, exist_ok=True)
    for region in gyms.regions():
        for battle_id, image in sprites(region).items():
            image.save(args.out / f"{battle_id}.png", optimize=True)
    for battle_id, image in tower_sprites().items():
        image.save(args.out / f"{battle_id}.png", optimize=True)


def sprites(region: gyms.Region) -> dict[str, Image.Image]:
    """Every battle id of `region` (the hidden boss included) mapped to its sprite."""
    return {battle_id: draw(look) for battle_id, look in cast(region).items()}


def contact_sheet(region_id: str, art: Path | None = None) -> Image.Image:
    region = next(region for region in gyms.regions() if region.id == region_id)
    battles = roster(region)
    looks = cast(region)
    rows = [[b for b in battles if b.kind == "gym"], [b for b in battles if b.kind in ("elite", "champion", "hidden")],
            [b for b in battles if b.kind in ("grunt", "admin", "boss")]]
    cell, label, gap = SIZE * SHEET_SCALE, 46, 16
    width = 8 * (cell + gap) + gap
    sheet = Image.new("RGBA", (width, len(rows) * (cell + label + gap) + gap), (236, 232, 226, 255))
    pen = ImageDraw.Draw(sheet)
    big, small = ImageFont.truetype(SHEET_FONT, 17), ImageFont.truetype(SHEET_FONT, 13)
    for row, battles_in_row in enumerate(rows):
        top = gap + row * (cell + label + gap)
        for column, battle in enumerate(battles_in_row):
            left = gap + column * (cell + gap)
            image = stored(art / f"{battle.id}.png") if art else draw(looks[battle.id])
            if image:
                sheet.alpha_composite(image.resize((cell, cell), Image.NEAREST), (left, top))
            pen.text((left + cell // 2, top + cell + 4), battle.label, font=big, fill=(40, 34, 48), anchor="ma")
            kind = battle.kind + (f" · {'/'.join(battle.types)}" if battle.types else "")
            pen.text((left + cell // 2, top + cell + 26), kind, font=small, fill=(110, 100, 120), anchor="ma")
    return sheet


def stored(path: Path) -> Image.Image | None:
    if not path.exists():
        return None
    image = Image.open(path).convert("RGBA")
    return image if image.size == (SIZE, SIZE) else image.resize((SIZE, SIZE), Image.NEAREST)


def roster(region: gyms.Region) -> list[Battle]:
    """The region's battles in sheet order. The hidden boss is drawn from its id alone, whether or not the bot
    lists it yet."""
    hidden = Battle(f"{region.id}-hidden", "hidden", (), "???")
    listed = [Battle(o.id, o.kind, o.types, o.trainer.name["ko"]) for o in (*region.gyms, *region.elite)
              if o.id != hidden.id]
    hideout = [Battle(o.id, o.kind, o.types, o.trainer.name["ko"]) for o in region.hideout if o.id != hidden.id]
    return [*listed, hidden, *hideout]


def cast(region: gyms.Region) -> dict[str, Look]:
    """Deals every trainer of the region a person from region-seeded decks, so genders, skin tones, hair and poses
    spread evenly and no two share a silhouette, then dresses them by role."""
    battles = roster(region)
    deck = random.Random(f"trainer-sprites:{region.id}")
    count = len(battles)
    genders = dealt(deck, ("f", "m"), count)
    skins = dealt(deck, SKINS, count)
    hairs = dealt(deck, HAIR_COLORS, count)
    eyes = dealt(deck, EYE_COLORS, count)
    builds = dealt(deck, tuple(SHOULDERS), count)
    poses = dealt(deck, tuple(POSES), count)
    mirrors = dealt(deck, (False, True), count)
    headwear = dealt(deck, (False, True), count)
    styles = {"f": dealt(deck, FEMALE_HAIR, count), "m": dealt(deck, MALE_HAIR, count)}
    ages = {"gym": dealt(deck, ("kid", "teen", "teen", "adult", "adult", "adult", "elder", "adult"), 8),
            "elite": dealt(deck, ("teen", "adult", "adult", "elder"), 4)}
    region_index = list(gym_data.ORG_TYPES).index(region.id)
    looks = {}
    for index, battle in enumerate(battles):
        gender = genders[index]
        person = Person(gender, skins[index], hairs[index], styles[gender].pop(), eyes[index], builds[index],
                        poses[index], mirrors[index], headwear[index])
        age = ages[battle.kind].pop() if battle.kind in ages else ("adult" if battle.kind != "grunt" else "teen")
        looks[battle.id] = dress(battle, person, age, region.id, region_index)
    return looks


def tower_sprites() -> dict[str, Image.Image]:
    """The battle tower's trainers and its owner, mapped to their sprites."""
    return {battle_id: draw(look) for battle_id, look in tower_cast().items()}


def tower_cast() -> dict[str, Look]:
    """The tower's trainers dressed like a gym leader of their trade's theme, and the owner in a champion's coat."""
    battles = [Battle(f"tower-{index}", "gym", (theme,), row[0])
               for index, (row, theme) in enumerate(zip(tower.TRAINERS, TOWER_THEMES), 1)]
    battles.append(Battle(tower.OWNER_ID, "champion", (), tower.OWNER[0]))
    deck = random.Random("trainer-sprites:tower")
    count = len(battles)
    genders, skins, hairs = dealt(deck, ("f", "m"), count), dealt(deck, SKINS, count), dealt(deck, HAIR_COLORS, count)
    eyes, builds, poses = dealt(deck, EYE_COLORS, count), dealt(deck, tuple(SHOULDERS), count), dealt(deck, tuple(POSES), count)
    mirrors, headwear = dealt(deck, (False, True), count), dealt(deck, (False, True), count)
    styles = {"f": dealt(deck, FEMALE_HAIR, count), "m": dealt(deck, MALE_HAIR, count)}
    ages = dealt(deck, ("teen", "adult", "adult", "elder"), count)
    looks = {}
    for index, battle in enumerate(battles):
        gender = genders[index]
        person = Person(gender, skins[index], hairs[index], styles[gender].pop(), eyes[index], builds[index],
                        poses[index], mirrors[index], headwear[index])
        age = "adult" if battle.kind == "champion" else ages[index]
        looks[battle.id] = dress(battle, person, age, "kanto", TOWER_OWNER_COAT)
    return looks


def dealt(deck: random.Random, items: tuple, count: int) -> list:
    """`count` items cycling through `items` as evenly as possible, shuffled."""
    order = list(range(len(items)))
    deck.shuffle(order)
    pool = [items[order[index % len(items)]] for index in range(count)]
    deck.shuffle(pool)
    return pool


def dress(battle: Battle, person: Person, age: str, region_id: str, region_index: int) -> Look:
    rng = random.Random(int.from_bytes(hashlib.sha256(battle.id.encode()).digest()[:8], "big"))
    hair = rng.choice(ELDER_HAIRS) if age == "elder" else person.hair
    base = Look(person.gender, age, person.build, person.skin, hair, person.hair_style, person.eyes, person.pose,
                person.mirror, Outfit(top=NEUTRALS[0]), mouth=rng.choice(("smile", "smile", "flat", "smirk", "grin")),
                brows=rng.choice(("flat", "sharp", "soft")))
    if age in ("adult", "elder") and person.gender == "m" and rng.random() < 0.45:
        base = replace(base, facial_hair=rng.choice(("mustache", "beard", "stubble")))
    if age != "kid" and rng.random() < 0.2:
        base = replace(base, glasses=rng.choice(((46, 40, 52), (150, 40, 50), (200, 170, 60))))
    org_main, org_trim = sorted((TYPE_COLORS[name] for name in gym_data.ORG_TYPES[region_id]), key=sum)
    if battle.kind == "gym":
        return gym_leader(base, battle.types[0], person, rng)
    if battle.kind == "elite":
        return elite(base, battle.types[0], rng)
    if battle.kind == "champion":
        return champion(base, region_index, rng)
    if battle.kind == "hidden":
        return hidden_boss(base, region_index)
    if battle.kind == "grunt":
        pose, mirror = ("point", False) if battle.id.endswith("-1") else ("fist", True)
        return grunt(replace(base, pose=pose, mirror=mirror), org_main, org_trim, region_index)
    if battle.kind == "admin":
        return admin(base, org_main, org_trim, region_index)
    return boss(base, org_main, org_trim, region_index, rng)


def gym_leader(look: Look, type_name: str, person: Person, rng: random.Random) -> Look:
    garments, prop, head = GYM_THEMES[type_name]
    garments = tuple(g for g in garments if g != "dress" or look.gender == "f") or ("tee",)
    color = TYPE_COLORS[type_name]
    second = rng.choice([n for n in NEUTRALS if distance(n, color) > 90])
    outfit = garment(rng.choice(garments), color, second, lift(color, 0.45), look.gender, rng)
    outfit = with_prop(outfit, prop, color, second)
    if prop == "mask":
        look = replace(look, mask=shade(color, 0.6))
    look = replace(look, outfit=outfit)
    if person.headwear and head:
        look = replace(look, headwear=head, headwear_color=shade(color, 0.85) if head != "goggles" else second)
    return look


def garment(kind: str, main: tuple, second: tuple, accent: tuple, gender: str, rng: random.Random) -> Outfit:
    skirt = gender == "f" and rng.random() < 0.5
    lower = ("skirt" if skirt else rng.choice(("pants", "pants", "shorts")), second if not skirt else shade(main, 0.7))
    shoes = rng.choice(SHOES)
    if kind == "tee":
        return Outfit(top=main, sleeves="short", collar="v", lower=lower[0], lower_color=lower[1], shoes=shoes)
    if kind == "jacket":
        return Outfit(top=second, outer=main, outer_length="waist", lower=lower[0], lower_color=lower[1],
                      shoes=shoes, trim=accent)
    if kind == "hoodie":
        return Outfit(top=main, collar="hood", lower=lower[0], lower_color=lower[1], shoes=shoes, trim=accent)
    if kind == "wetsuit":
        return Outfit(top=main, lower="pants", lower_color=shade(main, 0.6), shoes=shoes, trim=accent, boots=True)
    if kind == "coat":
        return Outfit(top=second, outer=main, outer_length="knee", collar="high", lower="pants",
                      lower_color=shade(second, 0.6), shoes=shoes, boots=True, trim=accent)
    if kind == "gi":
        return Outfit(top=lift(main, 0.75), sleeves="short", collar="cross", lower="pants",
                      lower_color=lift(main, 0.75), belt=shade(main, 0.5), shoes=(198, 150, 104), trim=main)
    if kind == "overalls":
        return Outfit(top=second, sleeves="short", bib=main, lower="pants", lower_color=main, shoes=shoes,
                      boots=True)
    if kind == "vest":
        return Outfit(top=second, sleeves="short", outer=main, outer_length="hip", outer_sleeves=False,
                      lower=lower[0], lower_color=lower[1] if lower[0] != "skirt" else shade(second, 0.6), shoes=shoes)
    if kind == "robe":
        return Outfit(top=main, sleeves="wide", collar="cross", lower="longskirt", lower_color=main,
                      sash=accent, shoes=shoes, trim=accent)
    if kind == "cardigan":
        return Outfit(top=second, outer=main, outer_length="hip", lower=lower[0], lower_color=lower[1], shoes=shoes)
    return Outfit(top=main, sleeves="short", collar="v", lower="skirt", lower_color=main, belt=accent, shoes=shoes)


def with_prop(outfit: Outfit, prop: str, color: tuple, second: tuple) -> Outfit:
    dark = shade(color, 0.55)
    if prop == "scarf":
        return replace(outfit, scarf=lift(color, 0.25) if outfit.top != color else second)
    if prop == "gloves":
        return replace(outfit, gloves=dark)
    if prop == "belt":
        return replace(outfit, belt=dark)
    if prop == "apron":
        return replace(outfit, apron=second if outfit.top != second else lift(color, 0.6))
    if prop == "shawl":
        return replace(outfit, shawl=lift(color, 0.5))
    if prop == "cape":
        return replace(outfit, cape=dark)
    return outfit


def elite(look: Look, type_name: str, rng: random.Random) -> Look:
    color = TYPE_COLORS[type_name]
    main = shade(color, rng.choice((0.5, 0.62, 0.75)))
    accent = rng.choice((GOLD, SILVER, lift(color, 0.55)))
    inner = rng.choice(((240, 240, 244), (40, 40, 50), lift(color, 0.7)))
    kinds = ("gown", "suit", "longcoat") if look.gender == "f" else ("suit", "longcoat", "robe")
    kind = rng.choice(kinds)
    if kind == "gown":
        outfit = Outfit(top=main, collar="high", lower="longskirt", lower_color=main, trim=accent, belt=accent,
                        shoes=SHOES[0])
    elif kind == "suit":
        outfit = Outfit(top=inner, outer=main, outer_length="hip", collar="v", lower="pants",
                        lower_color=shade(main, 0.7), tie=accent, shoes=SHOES[0], trim=None)
    elif kind == "robe":
        outfit = Outfit(top=main, sleeves="wide", collar="cross", lower="longskirt", lower_color=shade(main, 0.8),
                        sash=accent, trim=accent, shoes=SHOES[1])
    else:
        outfit = Outfit(top=inner, outer=main, outer_length="knee", collar="high", lower="pants",
                        lower_color=shade(main, 0.6), trim=accent, boots=True, shoes=SHOES[0])
    if rng.random() < 0.5:
        outfit = replace(outfit, gloves=accent if accent != GOLD else (240, 240, 244))
    if kind != "longcoat" and rng.random() < 0.35:
        outfit = replace(outfit, cape=shade(main, 0.7))
    pose = look.pose if look.pose != "raise" else "crossed"
    return replace(look, outfit=outfit, pose=pose, mouth=rng.choice(("smirk", "flat", "smile")))


def champion(look: Look, region_index: int, rng: random.Random) -> Look:
    coat, accent = CHAMPION_COLORS[region_index]
    inner = (40, 40, 52) if sum(coat) > 500 else (238, 236, 230)
    outfit = Outfit(top=inner, outer=coat, outer_length="ankle", collar="high", lower="pants",
                    lower_color=shade(coat, 0.55) if sum(coat) > 500 else (52, 52, 64), trim=accent, boots=True,
                    shoes=SHOES[0], gloves=accent if rng.random() < 0.5 else None)
    accent_kind = CHAMPION_ACCENTS[region_index]
    if accent_kind == "sash":
        outfit = replace(outfit, sash=accent)
    elif accent_kind == "epaulettes":
        outfit = replace(outfit, epaulettes=accent, cape=shade(coat, 0.75))
    else:
        outfit = replace(outfit, scarf=accent)
    style = look.hair_style
    if (style == "long" and look.hair == HAIR_COLORS[4]) or (style == "spiky" and look.hair == HAIR_COLORS[12]):
        look = replace(look, hair=HAIR_COLORS[1])
    pose = look.pose if look.pose in ("hips", "point", "present", "crossed") else "present"
    return replace(look, outfit=outfit, pose=pose, mouth="smile", brows="sharp", headwear="none", facial_hair="none")


def hidden_boss(look: Look, region_index: int) -> Look:
    glow = HIDDEN_GLOWS[region_index]
    cloak = (34, 32, 50)
    outfit = Outfit(top=(52, 48, 70), outer=cloak, outer_length="ankle", collar="high", lower="longskirt",
                    lower_color=cloak, trim=shade(glow, 0.7), cape=(28, 26, 40), ragged=True,
                    gloves=(30, 28, 40), shoes=SHOES[0])
    pose = "raise" if region_index % 2 == 0 else "present"
    return replace(look, outfit=outfit, pose=pose, headwear="hood", headwear_color=cloak, glow=glow,
                        mask=(220, 220, 230), glasses=None, facial_hair="none", age="adult")


def grunt(look: Look, main: tuple, trim: tuple, region_index: int) -> Look:
    uniform = shade(main, 0.5)
    outfit = Outfit(top=uniform, lower="pants", lower_color=shade(uniform, 0.7), belt=trim, boots=True,
                    shoes=(40, 38, 50), gloves=shade(trim, 0.7), emblem=(ORG_EMBLEMS[region_index], trim))
    headgear = ORG_HEADGEAR[region_index]
    pose = look.pose if look.pose in ("point", "fist", "hips") else "fist"
    return replace(look, outfit=outfit, pose=pose, headwear=headgear, headwear_color=shade(trim, 0.8),
                        mouth="grin", brows="sharp", glasses=None)


def admin(look: Look, main: tuple, trim: tuple, region_index: int) -> Look:
    uniform = shade(main, 0.42)
    outfit = Outfit(top=shade(main, 0.6), outer=uniform, outer_length="hip", collar="high", lower="pants",
                    lower_color=shade(uniform, 0.7), trim=trim, epaulettes=trim, boots=True, shoes=(40, 38, 50),
                    gloves=trim, emblem=(ORG_EMBLEMS[region_index], trim))
    pose = look.pose if look.pose in ("point", "crossed", "hips") else "crossed"
    return replace(look, outfit=outfit, pose=pose, mouth="smirk", brows="sharp", headwear="none")


def boss(look: Look, main: tuple, trim: tuple, region_index: int, rng: random.Random) -> Look:
    coat = shade(main, 0.3)
    outfit = Outfit(top=shade(trim, 0.45), outer=coat, outer_length="knee", collar="high", lower="pants",
                    lower_color=(34, 32, 44), trim=trim, cape=shade(trim, 0.4), boots=True, shoes=(34, 32, 44),
                    gloves=(34, 32, 44), emblem=(ORG_EMBLEMS[region_index], trim))
    pose = look.pose if look.pose in ("point", "present", "raise") else "point"
    return replace(look, outfit=outfit, pose=pose, mouth="smirk", brows="sharp", headwear="none",
                        age="elder" if look.age == "elder" or rng.random() < 0.3 else "adult")


def draw(look: Look) -> Image.Image:
    figure = Figure()
    body = Body.of(look)
    back_layer(figure, look, body)
    legs(figure, look, body)
    torso(figure, look, body)
    arms(figure, look, body)
    neckwear(figure, look, body)
    head(figure, look, body)
    return figure.render(look.mirror)


@dataclass(frozen=True)
class Body:
    top: int
    chin: int
    shoulder_y: int
    hip_y: int
    shoulder: int
    hip: int
    leg: int
    upper_arm: int
    forearm: int

    @property
    def x0(self) -> int:
        return CX - 7

    @property
    def x1(self) -> int:
        return CX + 6

    @property
    def ankle(self) -> int:
        return FLOOR - 3

    @property
    def knee(self) -> int:
        return self.hip_y + (self.ankle - self.hip_y) * 9 // 20

    @staticmethod
    def of(look: Look) -> "Body":
        height, torso_length, arm = AGES[look.age]
        top = FLOOR - height + 1
        chin = top + 12
        shoulder = SHOULDERS[look.build] - (1 if look.gender == "f" else 0) - (2 if look.age == "kid" else 0)
        hip = HIPS[look.build] - (1 if look.age == "kid" else 0)
        leg = 5 if look.build == "broad" else 4
        return Body(top, chin, chin + 2, chin + 2 + torso_length, max(shoulder, 6), hip, leg, arm, arm)


def back_layer(figure: "Figure", look: Look, body: Body) -> None:
    outfit = look.outfit
    if outfit.cape:
        bottom = body.ankle if look.age != "kid" else body.ankle - 2
        width = body.shoulder + 4
        figure.paint(poly_mask([(CX - body.shoulder, body.shoulder_y - 1), (CX + body.shoulder - 1, body.shoulder_y - 1),
                                (CX + width + 1, bottom), (CX - width - 2, bottom)]), outfit.cape)
    if look.headwear == "hood":
        figure.paint(ellipse_mask((body.x0 - 3, body.top - 4, body.x1 + 3, body.chin + 4)), look.headwear_color)
        return
    if outfit.collar == "hood":
        figure.paint(ellipse_mask((CX - 7, body.shoulder_y - 3, CX + 6, body.shoulder_y + 3)), shade(outfit.top, 0.85))
    hair_back(figure, look, body)


def hair_back(figure: "Figure", look: Look, body: Body) -> None:
    style, x0, x1, top = look.hair_style, body.x0, body.x1, body.top
    if style == "long":
        bottom = body.shoulder_y + (9 if look.gender == "f" else 4)
        figure.paint(poly_mask([(x0 - 1, top + 2), (x1 + 1, top + 2), (x1 + 3, bottom), (x0 - 3, bottom)]), look.hair,
                     gloss=True)
    elif style == "bob":
        figure.paint(rect_mask((x0 - 2, top + 2, x1 + 2, body.chin + 1)), look.hair, gloss=True)
    elif style == "curly":
        figure.paint(ellipse_mask((x0 - 4, top - 4, x1 + 4, top + 15)), look.hair, gloss=True)
    elif style == "ponytail":
        figure.paint(union(ellipse_mask((x1 - 2, top - 1, x1 + 3, top + 4)),
                           poly_mask([(x1 + 1, top + 2), (x1 + 5, top + 4), (x1 + 4, body.chin + 6), (x1 + 1, body.chin + 3)])),
                     look.hair, gloss=True)
    elif style == "twintails":
        for side_x in (x0 - 4, x1 + 1):
            figure.paint(poly_mask([(side_x + 1, top + 2), (side_x + 3, top + 2), (side_x + 4, body.chin + 7),
                                    (side_x, body.chin + 7)]), look.hair, gloss=True)


def legs(figure: "Figure", look: Look, body: Body) -> None:
    outfit = look.outfit
    leg_ink = outfit.lower_color if outfit.lower == "pants" else look.skin
    left = poly_mask([(CX - body.hip, body.hip_y - 1), (CX - 1, body.hip_y - 1), (CX - 3, body.ankle),
                      (CX - 2 - body.leg, body.ankle)])
    right = left.transpose(Image.FLIP_LEFT_RIGHT)
    figure.paint(union(left, right), leg_ink)
    if outfit.lower == "shorts":
        figure.paint(ImageChops.multiply(union(left, right), rect_mask((0, 0, SIZE, body.knee))), outfit.lower_color)
    if outfit.lower in ("skirt", "longskirt"):
        bottom = body.knee + 2 if outfit.lower == "skirt" else body.ankle
        flare = 3 if outfit.lower == "skirt" else 5
        hem = poly_mask([(CX - body.hip, body.hip_y - 2), (CX + body.hip - 1, body.hip_y - 2),
                         (CX + body.hip - 1 + flare, bottom), (CX - body.hip - flare, bottom)])
        if outfit.ragged:
            hem = minus(hem, zigzag(CX - body.hip - flare, CX + body.hip + flare, bottom))
        figure.paint(hem, outfit.lower_color)
    shoe_top = FLOOR - (6 if outfit.boots else 2)
    shoe = rect_mask((CX - 3 - body.leg, shoe_top, CX - 2, FLOOR))
    figure.paint(union(shoe, shoe.transpose(Image.FLIP_LEFT_RIGHT)), outfit.shoes)
    if outfit.outer and outfit.outer_length in ("knee", "ankle"):
        coat_tails(figure, outfit, body)


def coat_tails(figure: "Figure", outfit: Outfit, body: Body) -> None:
    bottom = body.knee + 4 if outfit.outer_length == "knee" else body.ankle - 1
    flare = 3 if outfit.outer_length == "knee" else 5
    left = poly_mask([(CX - body.hip - 1, body.hip_y - 2), (CX - 2, body.hip_y - 2), (CX - 3, bottom),
                      (CX - body.hip - 1 - flare, bottom)])
    right = left.transpose(Image.FLIP_LEFT_RIGHT)
    tails = union(left, right)
    if outfit.ragged:
        tails = minus(tails, zigzag(CX - body.hip - flare - 2, CX + body.hip + flare + 2, bottom))
    figure.paint(tails, outfit.outer)
    if outfit.trim:
        edge = minus(tails, shifted(tails, 0, -1))
        figure.paint(edge, outfit.trim, seam=False, flat=True)


def torso(figure: "Figure", look: Look, body: Body) -> None:
    outfit = look.outfit
    figure.paint(rect_mask((CX - 2, body.chin - 1, CX + 1, body.shoulder_y + 1)), look.skin, soft=True)
    shoulder, hip, y0, y1 = body.shoulder, body.hip, body.shoulder_y, body.hip_y
    waist = hip - (1 if look.gender == "f" else 0)
    chest = poly_mask([(CX - shoulder + 1, y0), (CX + shoulder - 2, y0), (CX + shoulder - 1, y0 + 2),
                       (CX + waist - 1, y0 + (y1 - y0) * 2 // 3), (CX + hip - 1, y1), (CX - hip, y1),
                       (CX - waist, y0 + (y1 - y0) * 2 // 3), (CX - shoulder, y0 + 2)])
    figure.paint(chest, outfit.top)
    if outfit.collar == "v":
        figure.paint(poly_mask([(CX - 2, y0), (CX + 1, y0), (CX, y0 + 3), (CX - 1, y0 + 3)]), look.skin, seam=False)
    if outfit.collar == "cross":
        figure.paint(union(line_mask([(CX - 3, y0), (CX + 1, y0 + 5)], 1), line_mask([(CX + 2, y0), (CX - 1, y0 + 4)], 1)),
                     outfit.trim or shade(outfit.top, 0.6), seam=False, flat=True)
    if outfit.bib:
        figure.paint(union(rect_mask((CX - hip + 1, y0 + 4, CX + hip - 2, y1)),
                           line_mask([(CX - hip + 1, y0), (CX - hip + 1, y0 + 4)], 1),
                           line_mask([(CX + hip - 2, y0), (CX + hip - 2, y0 + 4)], 1)), outfit.bib)
    if outfit.apron:
        figure.paint(poly_mask([(CX - hip + 1, y0 + 4), (CX + hip - 2, y0 + 4), (CX + hip - 1, body.knee + 1),
                                (CX - hip, body.knee + 1)]), outfit.apron)
    if outfit.outer:
        opening = poly_mask([(CX - 3, y0 - 1), (CX + 2, y0 - 1), (CX, y0 + (y1 - y0) * 2 // 3), (CX - 1, y0 + (y1 - y0) * 2 // 3)])
        if outfit.outer_length != "waist" or not outfit.outer_sleeves:
            opening = union(opening, rect_mask((CX - 1, y0 + (y1 - y0) * 2 // 3, CX, y1 + 1)))
        hem = y1 + (2 if outfit.outer_length in ("hip", "knee", "ankle") else 0)
        jacket = poly_mask([(CX - shoulder, y0), (CX + shoulder - 1, y0), (CX + shoulder - 1, y0 + 3),
                            (CX + hip, hem), (CX - hip - 1, hem), (CX - shoulder, y0 + 3)])
        figure.paint(minus(jacket, opening), outfit.outer)
        if outfit.trim:
            figure.paint(minus(dilated(opening), opening), outfit.trim, seam=False, flat=True)
    if outfit.tie:
        figure.paint(poly_mask([(CX - 1, y0), (CX, y0), (CX + 1, y0 + 7), (CX - 1, y0 + 8), (CX - 2, y0 + 7)]), outfit.tie,
                     seam=False, flat=True)
    if outfit.belt:
        figure.paint(rect_mask((CX - hip, y1 - 1, CX + hip - 1, y1)), outfit.belt, seam=False, flat=True)
        figure.paint(rect_mask((CX - 2, y1 - 1, CX + 1, y1)), lift(outfit.belt, 0.55), seam=False, flat=True)
    if outfit.sash:
        figure.paint(line_mask([(CX - shoulder + 1, y0 + 1), (CX + hip - 1, y1 - 1)], 3), outfit.sash, seam=False)
    if outfit.emblem:
        emblem(figure, outfit.emblem, CX + 2 if outfit.outer else CX - 3, y0 + 4)
    if outfit.collar == "high":
        figure.paint(poly_mask([(CX - 5, y0 - 3), (CX + 4, y0 - 3), (CX + 4, y0 + 1), (CX - 5, y0 + 1)]),
                     outfit.outer or outfit.top)
        if outfit.trim:
            figure.paint(rect_mask((CX - 5, y0 - 3, CX + 4, y0 - 3)), outfit.trim, seam=False, flat=True)
    if outfit.epaulettes:
        for x in (CX - shoulder - 1, CX + shoulder - 3):
            figure.paint(rect_mask((x, y0 - 1, x + 3, y0 + 1)), outfit.epaulettes, seam=False)


def emblem(figure: "Figure", mark: tuple, x: int, y: int) -> None:
    shape, color = mark
    figure.paint(pixel_mask([(x + dx, y + dy) for dx, dy in EMBLEMS[shape]]), lift(color, 0.2), seam=False, flat=True)


def arms(figure: "Figure", look: Look, body: Body) -> None:
    left_pose, right_pose = POSES[look.pose]
    order = ((-1, left_pose), (1, right_pose))
    if left_pose == "cross":
        order = ((1, right_pose), (-1, left_pose))
    for side, pose in order:
        arm(figure, look, body, side, pose)


ARM_POSES = {
    "down": ((0.18, 1.0), (0.04, 1.0)),
    "hip": ((0.8, 0.7), (-0.75, 0.7)),
    "point": ((1.0, -0.12), (1.0, -0.22)),
    "raise": ((0.75, -0.65), (0.08, -1.0)),
    "cross": ((0.2, 1.0), (-1.0, -0.12)),
    "fist": ((0.3, 1.0), (-0.45, -1.0)),
    "present": ((0.6, 0.8), (1.0, -0.15)),
}


def arm(figure: "Figure", look: Look, body: Body, side: int, pose: str) -> None:
    outfit = look.outfit
    shoulder = (CX - body.shoulder + 2 if side < 0 else CX + body.shoulder - 3, body.shoulder_y + 2)
    upper, fore = ARM_POSES[pose]
    upper_length = body.upper_arm * (0.75 if pose == "cross" else 1)
    fore_length = (body.shoulder * 2 - 2) if pose == "cross" else body.forearm * (0.8 if pose == "fist" else 1)
    elbow = step(shoulder, upper, upper_length, side)
    hand = step(elbow, fore, fore_length, side)
    sleeve = outfit.outer if outfit.outer and outfit.outer_sleeves else outfit.top
    width = 2.5 if outfit.sleeves == "wide" else 2
    if outfit.sleeves == "short":
        figure.paint(capsule_mask([shoulder, elbow, hand], 1.6), look.skin, soft=True)
        figure.paint(capsule_mask([shoulder, middle(shoulder, elbow, 0.55)], 2), sleeve)
    else:
        figure.paint(capsule_mask([shoulder, elbow, middle(elbow, hand, 0.82)], width), sleeve)
    if outfit.shawl:
        figure.paint(capsule_mask([shoulder, middle(shoulder, elbow, 0.4)], 2.4), outfit.shawl)
    hand_ink = outfit.gloves or look.skin
    figure.paint(ellipse_mask((round(hand[0]) - 2, round(hand[1]) - 2, round(hand[0]) + 1, round(hand[1]) + 1)), hand_ink,
                 soft=True)
    if pose == "point":
        tip = step(hand, fore, 3, side)
        figure.paint(line_mask([hand, tip], 1), hand_ink, seam=False)


def step(origin: tuple, direction: tuple, length: float, side: int) -> tuple:
    dx, dy = direction[0] * side, direction[1]
    norm = (dx * dx + dy * dy) ** 0.5
    return origin[0] + dx / norm * length, origin[1] + dy / norm * length


def middle(a: tuple, b: tuple, t: float) -> tuple:
    return a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t


def neckwear(figure: "Figure", look: Look, body: Body) -> None:
    outfit = look.outfit
    y0 = body.shoulder_y
    if outfit.shawl:
        figure.paint(poly_mask([(CX - body.shoulder, y0 - 1), (CX + body.shoulder - 1, y0 - 1),
                                (CX + body.shoulder, y0 + 4), (CX, y0 + 7), (CX - 1, y0 + 7), (CX - body.shoulder - 1, y0 + 4)]),
                     outfit.shawl)
    if outfit.scarf:
        figure.paint(union(rect_mask((CX - 5, y0 - 2, CX + 4, y0 + 1)),
                           poly_mask([(CX + 1, y0 + 1), (CX + 4, y0 + 1), (CX + 5, y0 + 9), (CX + 2, y0 + 9)])), outfit.scarf)


def head(figure: "Figure", look: Look, body: Body) -> None:
    x0, x1, top = body.x0, body.x1, body.top
    skull = ellipse_mask((x0, top, x1, top + 12))
    skin = look.skin if not look.glow else shade(look.skin, 0.32)
    figure.paint(union(rect_mask((x0 - 1, top + 6, x0, top + 8)), rect_mask((x1, top + 6, x1 + 1, top + 8))), skin, soft=True)
    figure.paint(skull, skin, soft=True)
    face(figure, look, body)
    if look.headwear == "hood":
        hood = minus(ellipse_mask((x0 - 3, top - 4, x1 + 3, body.chin + 4)), ellipse_mask((x0 + 1, top + 1, x1 - 1, body.chin + 3)))
        figure.paint(hood, look.headwear_color)
        if look.outfit.trim:
            figure.paint(minus(dilated(ellipse_mask((x0 + 1, top + 1, x1 - 1, body.chin + 3))),
                               ellipse_mask((x0 + 1, top + 1, x1 - 1, body.chin + 3))), look.outfit.trim, seam=False, flat=True)
        return
    hair_front(figure, look, body)
    brows(figure, look, body)
    headwear(figure, look, body)


def face(figure: "Figure", look: Look, body: Body) -> None:
    top = body.top
    lid, iris = top + 5, top + 6
    if look.glow:
        figure.paint(union(rect_mask((CX - 5, iris, CX - 3, iris)), rect_mask((CX + 2, iris, CX + 4, iris))), look.glow,
                     seam=False, flat=True)
        figure.paint(rect_mask((CX - 5, top + 8, CX + 4, top + 12)), look.mask, seam=False)
        return
    narrow = look.age == "elder"
    for left, outer in ((CX - 5, CX - 5), (CX + 2, CX + 4)):
        figure.paint(rect_mask((left, lid, left + 2, lid)), EYE_LINE, seam=False, flat=True)
        iris_x = left + 1 if outer == left else left
        figure.paint(rect_mask((outer, iris, outer, iris if narrow else iris + 1)), WHITE, seam=False, flat=True)
        figure.paint(rect_mask((iris_x, iris, iris_x + 1, iris if narrow else iris + 1)), look.eyes, seam=False, flat=True)
        if not narrow:
            figure.paint(rect_mask((iris_x, iris + 1, iris_x, iris + 1)), shade(look.eyes, 0.45), seam=False, flat=True)
            figure.paint(rect_mask((iris_x + 1, iris, iris_x + 1, iris)), WHITE, seam=False, flat=True)
        if look.gender == "f" and look.age != "elder":
            lash = left - 1 if outer == left else left + 3
            figure.paint(rect_mask((lash, lid - 1, lash, lid)), EYE_LINE, seam=False, flat=True)
    line = ink(look.skin).line
    figure.paint(rect_mask((CX, top + 8, CX, top + 8)), ink(look.skin).lo, seam=False, flat=True)
    figure.paint(pixel_mask(mouth_pixels(look.mouth, top + 10)), line, seam=False, flat=True)
    if look.mouth == "grin":
        figure.paint(rect_mask((CX - 1, top + 10, CX, top + 10)), WHITE, seam=False, flat=True)
    if look.age == "kid":
        figure.paint(union(rect_mask((CX - 6, top + 8, CX - 5, top + 8)), rect_mask((CX + 4, top + 8, CX + 5, top + 8))),
                     lift((232, 110, 120), 0.2), seam=False, flat=True)
    facial_hair(figure, look, top)
    if look.glasses:
        frames = minus(union(rect_mask((CX - 6, lid - 1, CX - 2, iris + 2)), rect_mask((CX + 1, lid - 1, CX + 5, iris + 2)),
                             rect_mask((CX - 2, lid, CX + 1, lid))),
                       union(rect_mask((CX - 5, lid, CX - 3, iris + 1)), rect_mask((CX + 2, lid, CX + 4, iris + 1))))
        figure.paint(frames, look.glasses, seam=False, flat=True)
    if look.mask:
        figure.paint(poly_mask([(body.x0 + 1, top + 8), (body.x1 - 1, top + 8), (body.x1 - 2, top + 12), (body.x0 + 2, top + 12)]),
                     look.mask, seam=False)


def mouth_pixels(mouth: str, y: int) -> list[tuple]:
    if mouth == "smile":
        return [(CX - 2, y - 1), (CX - 1, y), (CX, y), (CX + 1, y - 1)]
    if mouth == "smirk":
        return [(CX - 1, y), (CX, y), (CX + 1, y - 1)]
    if mouth == "grin":
        return [(CX - 2, y - 1), (CX - 1, y - 1), (CX, y - 1), (CX + 1, y - 1), (CX - 2, y), (CX + 1, y)]
    return [(CX - 1, y), (CX, y)]


def facial_hair(figure: "Figure", look: Look, top: int) -> None:
    if look.facial_hair == "mustache":
        figure.paint(rect_mask((CX - 3, top + 9, CX + 2, top + 9)), look.hair, seam=False, flat=True)
    elif look.facial_hair == "beard":
        beard = union(rect_mask((CX - 7, top + 6, CX - 6, top + 10)), rect_mask((CX + 5, top + 6, CX + 6, top + 10)),
                      poly_mask([(CX - 6, top + 10), (CX + 5, top + 10), (CX + 3, top + 14), (CX - 4, top + 14)]),
                      rect_mask((CX - 3, top + 9, CX + 2, top + 9)))
        figure.paint(minus(beard, rect_mask((CX - 1, top + 10, CX, top + 10))), look.hair, seam=False)
    elif look.facial_hair == "stubble":
        figure.paint(pixel_mask([(x, top + 11 + (x % 2)) for x in range(CX - 4, CX + 4)]), ink(look.skin).lo,
                     seam=False, flat=True)


def hair_front(figure: "Figure", look: Look, body: Body) -> None:
    style, x0, x1, top = look.hair_style, body.x0, body.x1, body.top
    if look.headwear in CROWN_COVERING and style in ("spiky", "mohawk", "swept", "bun"):
        style = "short"
    if style == "buzz":
        cap = minus(ellipse_mask((x0, top - 1, x1, top + 8)), rect_mask((x0 + 1, top + 3, x1 - 1, top + 13)))
        figure.paint(cap, look.hair)
        return
    if style == "mohawk":
        figure.paint(minus(ellipse_mask((x0, top - 1, x1, top + 8)), rect_mask((x0 + 1, top + 3, x1 - 1, top + 13))),
                     shade(look.hair, 0.6))
        figure.paint(poly_mask([(CX - 2, top + 3), (CX - 3, top - 3), (CX - 1, top - 1), (CX, top - 5), (CX + 1, top - 1),
                                (CX + 3, top - 3), (CX + 2, top + 3)]), look.hair, gloss=True)
        return
    cap = ellipse_mask((x0 - 1, top - 2, x1 + 1, top + 9))
    if style == "curly":
        cap = union(*(ellipse_mask((x, top - 3 + (x % 3), x + 4, top + 3 + (x % 3))) for x in range(x0 - 2, x1, 3)), cap)
    if style == "spiky":
        cap = union(cap, poly_mask([(x0 - 2, top + 5), (x0 - 3, top - 2), (x0 + 1, top - 1), (x0 + 2, top - 5), (CX - 2, top - 2),
                                    (CX, top - 7), (CX + 2, top - 2), (x1 - 2, top - 5), (x1 - 1, top - 1), (x1 + 3, top - 2),
                                    (x1 + 2, top + 5)]))
    if style == "swept":
        cap = union(cap, poly_mask([(x0, top + 1), (x0 + 2, top - 4), (CX + 2, top - 5), (x1 + 2, top - 2), (x1 + 2, top + 3)]))
    if style == "bun":
        cap = union(cap, ellipse_mask((CX - 4, top - 6, CX + 3, top + 0)))
    figure.paint(minus(cap, face_window(style, x0, x1, top)), look.hair, gloss=True)
    if style in ("ponytail", "twintails", "bun"):
        tie = {"ponytail": (x1 - 1, top + 1, x1 + 1, top + 2), "twintails": (x0 - 3, top + 3, x0 - 1, top + 4),
               "bun": (CX - 3, top - 1, CX + 2, top - 1)}[style]
        figure.paint(rect_mask(tie), lift(look.eyes, 0.3), seam=False, flat=True)
        if style == "twintails":
            figure.paint(rect_mask((x1 + 2, top + 3, x1 + 4, top + 4)), lift(look.eyes, 0.3), seam=False, flat=True)


def face_window(style: str, x0: int, x1: int, top: int) -> Image.Image:
    bottom = top + 16
    if style in ("bob", "short"):
        edge = [(x0 + 1, top + 4), (x1 - 1, top + 4)] if style == "bob" else [(x0 + 1, top + 5), (CX - 3, top + 3), (x1 - 1, top + 3)]
    elif style == "swept":
        edge = [(x0 + 1, top + 5), (CX - 1, top + 4), (x1 - 1, top + 2)]
    elif style in ("long", "ponytail", "twintails"):
        edge = [(x0 + 1, top + 5), (CX - 2, top + 3), (CX - 1, top + 2), (CX, top + 2), (CX + 1, top + 3), (x1 - 1, top + 5)]
    elif style == "spiky":
        edge = [(x0 + 1, top + 4), (x0 + 3, top + 5), (CX - 2, top + 2), (CX, top + 5), (CX + 2, top + 2), (x1 - 3, top + 5),
                (x1 - 1, top + 4)]
    else:
        edge = [(x0 + 1, top + 4), (CX - 3, top + 3), (CX, top + 4), (CX + 3, top + 3), (x1 - 1, top + 4)]
    return poly_mask([*edge, (x1 - 1, bottom), (x0 + 1, bottom)])


def brows(figure: "Figure", look: Look, body: Body) -> None:
    y = body.top + 3
    color = shade(look.hair, 0.55) if sum(look.hair) < 600 else (120, 116, 124)
    for outer, inner in ((CX - 5, CX - 3), (CX + 4, CX + 2)):
        mid = (outer + inner) // 2 if outer < inner else (outer + inner + 1) // 2
        if look.brows == "sharp":
            pixels = [(outer, y), (mid, y), (inner, y + 1)]
        elif look.brows == "soft":
            pixels = [(outer, y + 1), (mid, y), (inner, y)]
        else:
            pixels = [(outer, y), (mid, y), (inner, y)]
        figure.paint(pixel_mask(pixels), color, seam=False, flat=True)


def headwear(figure: "Figure", look: Look, body: Body) -> None:
    gear, color, x0, x1, top = look.headwear, look.headwear_color, body.x0, body.x1, body.top
    if gear == "cap":
        figure.paint(ImageChops.multiply(ellipse_mask((x0 - 1, top - 4, x1 + 1, top + 6)), rect_mask((0, 0, SIZE, top + 2))), color)
        figure.paint(rect_mask((x0 - 1, top + 2, x1 + 4, top + 3)), shade(color, 0.8))
    elif gear == "beanie":
        figure.paint(ImageChops.multiply(ellipse_mask((x0 - 1, top - 5, x1 + 1, top + 7)), rect_mask((0, 0, SIZE, top + 3))), color)
        figure.paint(rect_mask((x0 - 1, top + 1, x1 + 1, top + 3)), shade(color, 0.8), seam=False)
        figure.paint(ellipse_mask((CX - 2, top - 7, CX + 1, top - 4)), lift(color, 0.5))
    elif gear == "sunhat":
        figure.paint(ellipse_mask((x0 - 6, top, x1 + 6, top + 4)), color)
        figure.paint(ellipse_mask((x0 + 1, top - 5, x1 - 1, top + 3)), color)
        figure.paint(rect_mask((x0 + 1, top + 1, x1 - 1, top + 1)), lift(color, 0.5), seam=False, flat=True)
    elif gear == "hardhat":
        figure.paint(ImageChops.multiply(ellipse_mask((x0 - 1, top - 5, x1 + 1, top + 6)), rect_mask((0, 0, SIZE, top + 2))), color)
        figure.paint(rect_mask((x0 - 2, top + 2, x1 + 2, top + 3)), shade(color, 0.85))
        figure.paint(rect_mask((CX - 1, top - 4, CX, top + 1)), lift(color, 0.4), seam=False, flat=True)
    elif gear == "headband":
        figure.paint(union(rect_mask((x0 - 1, top + 1, x1 + 1, top + 2)),
                           poly_mask([(x1, top + 1), (x1 + 5, top + 4), (x1 + 4, top + 6), (x1, top + 3)])), color, seam=False)
    elif gear == "bandana":
        figure.paint(union(ImageChops.multiply(ellipse_mask((x0 - 1, top - 3, x1 + 1, top + 7)), rect_mask((0, 0, SIZE, top + 2))),
                           poly_mask([(x1, top + 1), (x1 + 4, top + 5), (x1 + 2, top + 6), (x1, top + 3)])), color)
    elif gear == "goggles":
        figure.paint(rect_mask((x0 - 1, top + 1, x1 + 1, top + 2)), (52, 48, 60), seam=False, flat=True)
        for left in (CX - 6, CX + 1):
            figure.paint(ellipse_mask((left, top - 1, left + 4, top + 3)), color)
            figure.paint(rect_mask((left + 1, top, left + 2, top + 1)), (220, 240, 255), seam=False, flat=True)
    elif gear == "ribbon":
        figure.paint(union(poly_mask([(x1 - 3, top - 1), (x1 - 7, top - 4), (x1 - 7, top + 2)]),
                           poly_mask([(x1 - 3, top - 1), (x1 + 1, top - 4), (x1 + 1, top + 2)])), color)
    elif gear == "beret":
        figure.paint(ellipse_mask((x0 - 2, top - 4, x1 + 3, top + 2)), color)
        figure.paint(rect_mask((x0 - 1, top + 1, x1 + 1, top + 2)), shade(color, 0.7), seam=False, flat=True)


class Figure:
    """A label canvas: every painted part gets its own id and ink, so the render can shade each part and draw a
    line where a part overlaps an earlier one."""

    def __init__(self):
        self.labels = Image.new("L", (SIZE, SIZE), 0)
        self.inks: list = [None]
        self.seams: list[bool] = [False]

    def paint(self, mask: Image.Image, color: tuple, seam: bool = True, flat: bool = False, soft: bool = False,
              gloss: bool = False) -> None:
        self.inks.append((ink(tuple(color[:3])), flat, soft, gloss))
        self.seams.append(seam)
        self.labels.paste(len(self.inks) - 1, (0, 0, SIZE, SIZE), mask)

    def render(self, mirror: bool) -> Image.Image:
        labels = self.labels.transpose(Image.FLIP_LEFT_RIGHT) if mirror else self.labels
        grid = labels.load()
        image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        pixels = image.load()
        for y in range(SIZE):
            x = 0
            while x < SIZE:
                part = grid[x, y]
                end = x
                while end + 1 < SIZE and grid[end + 1, y] == part:
                    end += 1
                if part:
                    for column in range(x, end + 1):
                        pixels[column, y] = (*self._color(grid, column, y, x, end), 255)
                x = end + 1
        return outlined(image)

    def _color(self, grid, x: int, y: int, start: int, end: int) -> tuple:
        part = grid[x, y]
        palette, flat, soft, gloss = self.inks[part]
        if self.seams[part] and any(0 < grid[nx, ny] < part for nx, ny in neighbours(x, y)):
            return palette.line
        if flat:
            return palette.mid
        length = end - start + 1
        band = max(1, length // (6 if soft else 4)) if length >= 3 else 0
        if x > end - band or (length >= 3 and y + 1 < SIZE and grid[x, y + 1] != part):
            return palette.lo
        if gloss and y > 0 and grid[x, y - 1] != part:
            return palette.hi
        if length >= 6 and x == start + 1:
            return palette.hi
        return palette.mid


@dataclass(frozen=True)
class Ink:
    hi: tuple
    mid: tuple
    lo: tuple
    line: tuple


@cache
def ink(color: tuple) -> Ink:
    return Ink(tone(color, 1.12, 0.08, 0.85, 0.14), tuple(color), tone(color, 0.74, 0, 1.12, 0.72),
               tone(color, 0.48, 0, 1.2, 0.72))


def tone(color: tuple, value: float, add: float, saturation: float, hue: float) -> tuple:
    h, s, v = colorsys.rgb_to_hsv(*(channel / 255 for channel in color))
    if s > 0.08:
        gap = (hue - h + 0.5) % 1 - 0.5
        h = (h + gap * 0.12) % 1
    s, v = min(1, s * saturation), min(1, v * value + add)
    return tuple(round(channel * 255) for channel in colorsys.hsv_to_rgb(h, s, v))


def outlined(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    ring = minus(dilated(alpha), alpha)
    result = image.copy()
    result.paste((*OUTLINE, 255), (0, 0, SIZE, SIZE), ring)
    return result


def neighbours(x: int, y: int):
    return [(nx, ny) for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)) if 0 <= nx < SIZE and 0 <= ny < SIZE]


def blank() -> Image.Image:
    return Image.new("L", (SIZE, SIZE), 0)


def poly_mask(points: list) -> Image.Image:
    mask = blank()
    ImageDraw.Draw(mask).polygon([(round(x), round(y)) for x, y in points], fill=255)
    return mask


def ellipse_mask(box: tuple) -> Image.Image:
    mask = blank()
    ImageDraw.Draw(mask).ellipse(box, fill=255)
    return mask


def rect_mask(box: tuple) -> Image.Image:
    mask = blank()
    ImageDraw.Draw(mask).rectangle(box, fill=255)
    return mask


def pixel_mask(points: list) -> Image.Image:
    mask = blank()
    ImageDraw.Draw(mask).point(points, fill=255)
    return mask


def line_mask(points: list, width: int) -> Image.Image:
    mask = blank()
    ImageDraw.Draw(mask).line([(round(x), round(y)) for x, y in points], fill=255, width=width)
    return mask


def capsule_mask(points: list, radius: float) -> Image.Image:
    mask = blank()
    pen = ImageDraw.Draw(mask)
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        length = max(((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5, 0.01)
        nx, ny = -(by - ay) / length * radius, (bx - ax) / length * radius
        pen.polygon([(round(ax + nx), round(ay + ny)), (round(bx + nx), round(by + ny)), (round(bx - nx), round(by - ny)),
                     (round(ax - nx), round(ay - ny))], fill=255)
    for x, y in points:
        pen.ellipse((round(x - radius), round(y - radius), round(x + radius) - 1, round(y + radius) - 1), fill=255)
    return mask


def zigzag(left: int, right: int, bottom: int) -> Image.Image:
    return poly_mask([(left, bottom + 1), *((x, bottom - 2 * ((x - left) // 3 % 2)) for x in range(left, right + 1, 3)),
                      (right, bottom + 1)])


def union(*masks: Image.Image) -> Image.Image:
    return reduce(ImageChops.lighter, masks)


def minus(mask: Image.Image, cut: Image.Image) -> Image.Image:
    return ImageChops.subtract(mask, cut)


def shifted(mask: Image.Image, dx: int, dy: int) -> Image.Image:
    return ImageChops.offset(mask, dx, dy)


def dilated(mask: Image.Image) -> Image.Image:
    return union(mask, *(ImageChops.offset(mask, dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))))


def shade(color: tuple, factor: float) -> tuple:
    return tuple(int(channel * factor) for channel in color[:3])


def lift(color: tuple, amount: float) -> tuple:
    return tuple(int(channel + (255 - channel) * amount) for channel in color[:3])


def distance(a: tuple, b: tuple) -> float:
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


if __name__ == "__main__":
    main()
