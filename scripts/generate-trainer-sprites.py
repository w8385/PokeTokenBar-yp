"""Original 64x64 pixel trainer sprites, one per gym, Elite Four, champion and hideout battle, drawn from its id.

    python3 scripts/generate-trainer-sprites.py                         # assets/trainers/<battle id>.png
    python3 scripts/generate-trainer-sprites.py --sheet kanto out.png   # contact sheet of one region
"""

import argparse
import hashlib
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bot"))

from ypoke import gym_data, gyms  # noqa: E402

CANVAS = 32
SCALE = 2
OUTLINE = (28, 22, 36, 255)
SHOE = (52, 44, 60, 255)
GOLD = (232, 182, 52, 255)
SHEET_FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

TYPE_COLORS = {
    "normal": (168, 168, 120), "fire": (232, 110, 48), "water": (72, 130, 224), "electric": (240, 200, 48),
    "grass": (92, 176, 80), "ice": (126, 208, 216), "fighting": (192, 56, 48), "poison": (160, 76, 168),
    "ground": (212, 176, 96), "flying": (140, 152, 232), "psychic": (248, 96, 150), "bug": (160, 184, 40),
    "rock": (176, 156, 80), "ghost": (112, 88, 152), "dragon": (96, 56, 240), "dark": (96, 80, 72),
    "steel": (160, 160, 184), "fairy": (240, 150, 190),
}
SKINS = [(255, 219, 172), (241, 194, 150), (224, 172, 125), (198, 134, 96), (141, 85, 58), (96, 60, 42)]
HAIRS = [
    (40, 30, 28), (86, 52, 30), (160, 98, 44), (214, 170, 70), (190, 60, 50), (70, 90, 180), (110, 190, 140),
    (220, 220, 230), (150, 80, 170),
]
HAIR_STYLES = ("short", "long", "spiky", "bun", "bob", "bald")
BUILDS = {"slim": (12, 19, 9, 22), "normal": (11, 20, 8, 23), "broad": (10, 21, 7, 24)}
EYES = ("dot", "wide", "visor")


@dataclass(frozen=True)
class Look:
    skin: tuple
    hair: tuple
    hair_style: str
    eyes: str
    outfit: tuple
    trim: tuple
    pants: tuple
    body: str
    headgear: str
    emblem: tuple | None
    cape: tuple | None = None
    masked: bool = False
    build: str = "normal"
    extra: str = "none"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sheet", nargs=2, metavar=("REGION", "OUT"), help="write a contact sheet instead")
    parser.add_argument("--out", type=Path, default=ROOT / "assets" / "trainers")
    args = parser.parse_args()
    if args.sheet:
        region_id, out = args.sheet
        contact_sheet(region_id).save(out)
        return
    args.out.mkdir(parents=True, exist_ok=True)
    for region in gyms.regions():
        for opponent in (*region.gyms, *region.elite, *region.hideout):
            sprite(opponent, region).save(args.out / f"{opponent.id}.png", optimize=True)


def sprite(opponent: gyms.Opponent, region: gyms.Region) -> Image.Image:
    small = draw(look_of(opponent, region))
    return small.resize((CANVAS * SCALE, CANVAS * SCALE), Image.NEAREST)


def contact_sheet(region_id: str) -> Image.Image:
    region = next(region for region in gyms.regions() if region.id == region_id)
    rows = [region.gyms, region.elite, region.hideout]
    scale, label = 4, 46
    cell = CANVAS * scale
    width, gap = 8 * (cell + 16) + 16, 12
    sheet = Image.new("RGBA", (width, len(rows) * (cell + label + gap) + gap), (236, 232, 226, 255))
    pen = ImageDraw.Draw(sheet)
    big, small = ImageFont.truetype(SHEET_FONT, 17), ImageFont.truetype(SHEET_FONT, 13)
    for row, opponents in enumerate(rows):
        top = gap + row * (cell + label + gap)
        for column, opponent in enumerate(opponents):
            left = 16 + column * (cell + 16)
            art = draw(look_of(opponent, region)).resize((CANVAS * scale, CANVAS * scale), Image.NEAREST)
            sheet.alpha_composite(art, (left, top))
            pen.text((left + cell // 2, top + cell + 4), opponent.trainer.name["ko"], font=big, fill=(40, 34, 48), anchor="ma")
            kind = opponent.kind + (f" · {'/'.join(opponent.types)}" if opponent.types else "")
            pen.text((left + cell // 2, top + cell + 26), kind, font=small, fill=(110, 100, 120), anchor="ma")
    return sheet


def look_of(opponent: gyms.Opponent, region: gyms.Region) -> Look:
    rolls = Rolls(opponent.id)
    skin, hair = rolls.pick(SKINS), rolls.pick(HAIRS)
    style, eyes = rolls.pick(HAIR_STYLES), rolls.pick(EYES)
    org_main, org_trim = (TYPE_COLORS[name] for name in gym_data.ORG_TYPES[region.id])
    pants = (64, 66, 92, 255)
    if opponent.kind == "gym":
        accent = TYPE_COLORS[opponent.types[0]]
        return Look(skin, hair, style, eyes, shade(accent, 0.78), lift(accent, 0.45), pants,
                    rolls.pick(("vest", "coat", "plain", "skirt")), rolls.pick(("none", "headband", "cap")),
                    lift(accent, 0.25), build=rolls.pick(tuple(BUILDS)), extra=rolls.pick(("none", "scarf", "glasses", "pack")))
    if opponent.kind == "elite":
        accent = TYPE_COLORS[opponent.types[0]]
        return Look(skin, hair, style, eyes, shade(accent, 0.5), lift(accent, 0.3), (44, 42, 62, 255), "coat",
                    rolls.pick(("none", "visor", "hat")), accent, build=rolls.pick(tuple(BUILDS)),
                    extra=rolls.pick(("none", "scarf", "glasses")))
    if opponent.kind == "champion":
        return Look(skin, hair, "short", "wide", (238, 232, 216, 255), GOLD, (72, 74, 110, 255), "plain", "crown", GOLD,
                    cape=(150, 40, 56, 255))
    if opponent.kind == "grunt":
        return Look(skin, hair, "short", "dot", shade(org_main, 0.45), org_trim, (38, 36, 52, 255), "plain",
                    rolls.pick(("hood", "cap")), org_trim, masked=True)
    if opponent.kind == "admin":
        return Look(skin, hair, rolls.pick(("spiky", "long", "bob")), "wide", shade(org_main, 0.7), org_trim,
                    (38, 36, 52, 255), "coat", "none", org_trim)
    return Look(skin, hair, "short", "dot", (40, 36, 52, 255), org_trim, (30, 28, 44, 255), "plain", "hat", org_main,
                cape=shade(org_main, 0.55))


def draw(look: Look) -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    pen = ImageDraw.Draw(image)
    cape(pen, look)
    legs(pen, look)
    torso(pen, look)
    head(pen, look)
    return outlined(image)


def cape(pen: ImageDraw.ImageDraw, look: Look) -> None:
    if look.extra == "pack":
        pen.rectangle((5, 15, 9, 24), fill=shade(look.trim, 0.6))
    if look.cape:
        pen.polygon([(10, 14), (21, 14), (25, 29), (6, 29)], fill=look.cape)


def legs(pen: ImageDraw.ImageDraw, look: Look) -> None:
    pen.rectangle((12, 24, 15, 28), fill=look.pants)
    pen.rectangle((17, 24, 20, 28), fill=look.pants)
    pen.rectangle((11, 29, 15, 30), fill=SHOE)
    pen.rectangle((16, 29, 20, 30), fill=SHOE)


def torso(pen: ImageDraw.ImageDraw, look: Look) -> None:
    bottom = 27 if look.body == "coat" else 24
    left, right, arm_left, arm_right = BUILDS[look.build]
    pen.rectangle((left, 15, right, bottom), fill=look.outfit)
    pen.rectangle((arm_left, 16, left - 1, 22), fill=look.outfit)
    pen.rectangle((right + 1, 16, arm_right, 22), fill=look.outfit)
    pen.rectangle((arm_left, 23, left - 1, 24), fill=look.skin)
    pen.rectangle((right + 1, 23, arm_right, 24), fill=look.skin)
    if look.body == "skirt":
        pen.polygon([(left, 24), (right, 24), (right + 3, 28), (left - 3, 28)], fill=shade(look.outfit, 0.85))
        pen.line((left, 23, right, 23), fill=look.trim)
    if look.body == "vest":
        pen.rectangle((14, 15, 17, 23), fill=look.trim)
    elif look.body == "coat":
        pen.rectangle((13, 15, 18, 16), fill=look.trim)
        pen.line((15, 17, 15, bottom), fill=shade(look.outfit, 0.7))
    elif look.body == "plain":
        pen.rectangle((left, 22, right, 23), fill=look.trim)
    if look.emblem:
        pen.rectangle((14, 18, 17, 21), fill=look.emblem)
        pen.rectangle((15, 19, 16, 20), fill=lift(look.emblem, 0.6))


def head(pen: ImageDraw.ImageDraw, look: Look) -> None:
    hooded = look.headgear == "hood"
    if hooded:
        pen.ellipse((8, 2, 23, 16), fill=look.outfit)
    elif look.hair_style in ("long", "bob"):
        pen.rectangle((9, 5, 22, 16 if look.hair_style == "long" else 12), fill=look.hair)
    pen.rectangle((14, 14, 17, 15), fill=look.skin)
    pen.ellipse((10, 4, 21, 14), fill=look.skin)
    if look.extra == "scarf":
        pen.rectangle((12, 14, 19, 15), fill=look.trim)
        pen.rectangle((18, 16, 20, 19), fill=look.trim)
    face(pen, look)
    if not hooded:
        hair(pen, look)
    headgear(pen, look)


def face(pen: ImageDraw.ImageDraw, look: Look) -> None:
    dark = (36, 28, 40, 255)
    if look.extra == "glasses":
        pen.rectangle((12, 8, 14, 10), outline=OUTLINE)
        pen.rectangle((17, 8, 19, 10), outline=OUTLINE)
        pen.point((15, 9), fill=OUTLINE)
        pen.point([(13, 9), (18, 9)], fill=dark)
    elif look.eyes == "visor":
        pen.rectangle((11, 8, 20, 9), fill=look.trim)
    elif look.eyes == "wide":
        for x in (13, 18):
            pen.rectangle((x, 8, x, 10), fill=dark)
    else:
        pen.point([(13, 9), (18, 9)], fill=dark)
    if look.masked:
        pen.rectangle((11, 11, 20, 13), fill=look.trim)
    else:
        pen.point([(15, 12), (16, 12)], fill=shade(look.skin, 0.6))


def hair(pen: ImageDraw.ImageDraw, look: Look) -> None:
    style = look.hair_style
    if style == "bald":
        return
    if style == "spiky":
        pen.polygon([(10, 8), (9, 3), (12, 5), (14, 1), (16, 4), (19, 1), (20, 5), (23, 3), (21, 8), (19, 6), (12, 6)], fill=look.hair)
        return
    pen.polygon([(10, 8), (10, 5), (12, 3), (19, 3), (21, 5), (21, 8), (19, 6), (12, 6)], fill=look.hair)
    if style == "bun":
        pen.ellipse((14, 1, 17, 3), fill=look.hair)


def headgear(pen: ImageDraw.ImageDraw, look: Look) -> None:
    gear = look.headgear
    if gear == "cap":
        pen.rectangle((10, 3, 21, 6), fill=look.outfit)
        pen.rectangle((9, 6, 22, 7), fill=shade(look.outfit, 0.75))
        pen.rectangle((14, 4, 17, 5), fill=look.trim)
    elif gear == "headband":
        pen.rectangle((10, 6, 21, 7), fill=look.trim)
    elif gear == "hood":
        pen.rectangle((10, 4, 21, 6), fill=look.outfit)
        pen.rectangle((14, 4, 17, 5), fill=look.trim)
    elif gear == "hat":
        pen.rectangle((11, 2, 20, 6), fill=look.outfit)
        pen.rectangle((6, 6, 25, 7), fill=look.outfit)
        pen.rectangle((11, 5, 20, 5), fill=look.trim)
    elif gear == "crown":
        pen.polygon([(11, 5), (11, 2), (13, 3), (16, 1), (19, 3), (21, 2), (21, 5)], fill=GOLD)


def outlined(image: Image.Image) -> Image.Image:
    pixels, result = image.load(), image.copy()
    out = result.load()
    for y in range(CANVAS):
        for x in range(CANVAS):
            if pixels[x, y][3]:
                continue
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < CANVAS and 0 <= ny < CANVAS and pixels[nx, ny][3]:
                    out[x, y] = OUTLINE
                    break
    return result


class Rolls:
    def __init__(self, key: str):
        self._digest = hashlib.sha256(key.encode()).digest()
        self._index = 0

    def pick(self, items):
        value = self._digest[self._index % len(self._digest)]
        self._index += 1
        return items[value % len(items)]


def shade(color: tuple, factor: float) -> tuple:
    return (*(int(channel * factor) for channel in color[:3]), 255)


def lift(color: tuple, amount: float) -> tuple:
    return (*(int(channel + (255 - channel) * amount) for channel in color[:3]), 255)


if __name__ == "__main__":
    main()
