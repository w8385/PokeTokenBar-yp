#!/usr/bin/env python3
"""Compares two folders of PNGs and reports which files differ and by how much.

    python3 scripts/png-diff.py BEFORE AFTER [--tolerance N] [--sheet DIR] [--noise DIR_A DIR_B]

A pixel differs when any channel moves by more than N (default 0). Needs Pillow.
With --sheet, a before | after | diff strip is written for every differing file.
With --noise, pixels that already differ between two renders of the same code (clocks, animation
phase) are ignored, widened by two pixels.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--tolerance", type=int, default=0)
    parser.add_argument("--sheet", type=Path)
    parser.add_argument("--noise", type=Path, nargs=2, metavar=("A", "B"))
    args = parser.parse_args()

    left, right = pngs(args.before), pngs(args.after)
    noise_a, noise_b = (pngs(d) for d in args.noise) if args.noise else ({}, {})
    only_before = sorted(set(left) - set(right))
    only_after = sorted(set(right) - set(left))
    identical, differing = 0, []
    for name in sorted(set(left) & set(right)):
        noise = noise_mask(noise_a.get(name), noise_b.get(name), args.tolerance)
        changed, total, box, diff = compare(left[name], right[name], args.tolerance, noise)
        if changed == 0:
            identical += 1
            continue
        differing.append((name, changed, total, box))
        if args.sheet and diff is not None:
            strip(left[name], right[name], diff, args.sheet / name)

    print(f"identical: {identical}  differing: {len(differing)}  only before: {len(only_before)}  only after: {len(only_after)}")
    for name, changed, total, box in differing:
        where = "size changed" if changed < 0 else f"{changed} px ({changed * 100 / total:.3f}%) in {box}"
        print(f"DIFF {name}: {where}")
    for name in only_before:
        print(f"ONLY-BEFORE {name}")
    for name in only_after:
        print(f"ONLY-AFTER {name}")
    return 1 if differing or only_before or only_after else 0


def pngs(root: Path) -> dict[str, Path]:
    return {str(p.relative_to(root)): p for p in sorted(root.rglob("*.png"))}


def binary_mask(diff: Image.Image, tolerance: int) -> Image.Image:
    """255 where any RGBA channel differs by more than `tolerance`, else 0."""
    channels = [band.point(lambda v: 255 if v > tolerance else 0) for band in diff.split()]
    mask = channels[0]
    for band in channels[1:]:
        mask = ImageChops.lighter(mask, band)
    return mask


def noise_mask(first: Path | None, second: Path | None, tolerance: int) -> Image.Image | None:
    if first is None or second is None:
        return None
    with Image.open(first) as a, Image.open(second) as b:
        if a.size != b.size:
            return None
        diff = ImageChops.difference(a.convert("RGBA"), b.convert("RGBA"))
        return binary_mask(diff, tolerance).filter(ImageFilter.MaxFilter(5))


def compare(before: Path, after: Path, tolerance: int,
            noise: Image.Image | None = None) -> tuple[int, int, tuple[int, int, int, int] | None, Image.Image | None]:
    with Image.open(before) as a, Image.open(after) as b:
        a, b = a.convert("RGBA"), b.convert("RGBA")
        if a.size != b.size:
            return -1, max(a.width * a.height, b.width * b.height), None, None
        diff = ImageChops.difference(a, b)
        mask = binary_mask(diff, tolerance)
        if noise is not None and noise.size == mask.size:
            mask = ImageChops.subtract(mask, noise)
        box = mask.getbbox()
        changed = mask.histogram()[255] if box else 0
        return changed, a.width * a.height, box, diff if box else None


def strip(before: Path, after: Path, diff: Image.Image, out: Path) -> None:
    with Image.open(before) as a, Image.open(after) as b:
        a, b = a.convert("RGBA"), b.convert("RGBA")
        sheet = Image.new("RGBA", (a.width * 3 + 20, a.height), (255, 255, 255, 255))
        sheet.paste(a, (0, 0))
        sheet.paste(b, (a.width + 10, 0))
        amplified = diff.point(lambda v: min(255, v * 8))
        sheet.paste(amplified.convert("RGB"), (a.width * 2 + 20, 0))
        out.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(out)


if __name__ == "__main__":
    sys.exit(main())
