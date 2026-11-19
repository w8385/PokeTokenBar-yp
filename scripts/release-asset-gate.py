#!/usr/bin/env python3
"""README asset gate shared by release.sh and fork-release.sh.

    python3 scripts/release-asset-gate.py <base-ref> [<head-ref>]

Exit 0: assets are current. Exit 1: warnings, such as a changed screen whose screenshots were not
redrawn. Exit 2: a UI feat since <base-ref> without a new README image. The callers decide what a
warning does; fork-release.sh stops on both.

A screen whose images did not all change still passes when PTB_README_FRESH_DIR holds a
`ReadmeScreenshotTests` render of <head-ref> that matches every committed variant (png-diff, with
PTB_README_NOISE_DIR as a second render that marks clock and animation noise).
"""
import fnmatch
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

UI_ROOT = "Sources/PokeTokenBar/UI/"
READMES = ("README.md", "README.ko.md", "README.ja.md")
README_IMAGE_RE = re.compile(r"^assets/(screenshot-[^/]+\.(png|gif)|settings[^/]*\.png|[^/]+\.gif)$")
LANGUAGE_SUFFIX_RE = re.compile(r"-(ko|ja)$")
FEAT_RE = re.compile(r"^feat(ure)?(\([^)]*\))?!?:", re.I)
REMOVED_TOOLS = ("ccusage",)

# UI file glob (relative to UI_ROOT) -> README image families that draw that screen. A screen is fresh when
# at least one of its families had every language variant changed in range. Unlisted files fall back to
# "some README image changed".
SCREENS = (
    ("ShopView.swift", ("screenshot-shop", "screenshot-held-items", "screenshot-shop-search")),
    ("BattleGroupChips.swift", ("screenshot-held-items",)),
    ("ScoutView.swift", ("screenshot-shop",)),
    ("MachineShopSection.swift", ("screenshot-shop",)),
    ("ItemCategoryChips.swift", ("screenshot-shop", "screenshot-bag")),
    ("BagView.swift", ("screenshot-bag", "screenshot-held-items")),
    ("HeldItemSections.swift", ("screenshot-held-items",)),
    ("BoxView.swift", ("screenshot-collection-box",)),
    ("BoxFilterPanel.swift", ("screenshot-collection-box", "screenshot-box-chips")),
    ("BoxScopeChips.swift", ("screenshot-collection-box", "screenshot-box-chips")),
    ("MoveNameLabel.swift", ("screenshot-move-order", "screenshot-status-moves", "screenshot-gym-replay")),
    ("BoxDetailView.swift", ("screenshot-pokemon-profile", "screenshot-exp-share", "screenshot-nature-picker",
                             "screenshot-miracle-trade")),
    ("MiracleTradeControls.swift", ("screenshot-miracle-trade",)),
    ("PokemonDetailParts.swift", ("screenshot-pokemon-profile", "screenshot-nature-picker")),
    ("NaturePicker.swift", ("screenshot-nature-picker",)),
    ("BoxTrainingControls.swift", ("screenshot-nature-picker",)),
    ("MoveTrainingSection.swift", ("screenshot-pokemon-profile", "screenshot-move-order", "screenshot-status-moves",
                                   "screenshot-egg-moves")),
    ("ExpShareSlot.swift", ("screenshot-exp-share",)),
    ("GymReplayView.swift", ("screenshot-gym-replay",)),
    ("GymResultView.swift", ("screenshot-gym-replay", "screenshot-hidden-boss")),
    ("Gym*.swift", ("screenshot-gyms",)),
    ("Battle*.swift", ("screenshot-battle",)),
    ("SettingsView.swift", ("settings", "screenshot-provider-settings")),
    ("SettingsTab.swift", ("settings", "screenshot-provider-settings")),
    ("DifficultySettingsSection.swift", ("screenshot-difficulty",)),
    ("UsageRecapView.swift", ("screenshot-usage-recap",)),
    ("ActivityHeatmap.swift", ("screenshot-activity-views", "screenshot-home")),
    ("ActivityVisualization.swift", ("screenshot-activity-views", "screenshot-home")),
    ("PopoverView.swift", ("screenshot-home",)),
    ("CompanionView.swift", ("screenshot-home", "screenshot-collection-pokedex", "screenshot-dex-next-evolution",
                             "screenshot-move-on", "screenshot-pet-xp")),
    ("UnownedSpeciesDetailView.swift", ("screenshot-collection-pokedex", "screenshot-pokemon-forms",
                                        "screenshot-dex-next-evolution")),
    ("FloatingPetPanel.swift", ("screenshot-pet-interactions", "floating-pet", "screenshot-floating-friends")),
    ("PetCrowdViews.swift", ("screenshot-home", "screenshot-pet-interactions", "floating-pet",
                             "screenshot-floating-friends", "screenshot-stored-friends")),
    ("MenuBarContent.swift", ("menubar", "screenshot-menu-growth")),
)


def main(argv):
    if not 1 <= len(argv) <= 2:
        print(__doc__.strip(), file=sys.stderr)
        return 64
    base, head = argv[0], argv[1] if len(argv) == 2 else "HEAD"
    print(f"▶ README asset gate ({base}..{head})")
    warnings = readme_warnings() + stale_screens(base, head)
    for line in warnings:
        print(f"  ⚠ {line}")
    missing = missing_new_image(base, head)
    for line in missing:
        print(f"  ✗ {line}")
    print_checklist()
    if missing:
        return 2
    return 1 if warnings else 0


def readme_warnings():
    found = []
    for readme in READMES:
        text = Path(readme).read_text() if Path(readme).exists() else ""
        if re.search(r"img\.shields\.io/badge/release-v[0-9]", text):
            found.append(f"{readme} has a static release badge; use the dynamic github/v/release badge.")
        for tool in REMOVED_TOOLS:
            if tool in text.lower():
                found.append(f"{readme} still mentions '{tool}', which was removed.")
    return found


def stale_screens(base, head):
    """Changed UI files whose screen has no fully redrawn image family in range."""
    changed_ui = git_lines("diff", "--name-only", f"{base}..{head}", "--", UI_ROOT)
    changed_images = {p for p in git_lines("diff", "--name-only", f"{base}..{head}", "--", "assets/")
                      if README_IMAGE_RE.match(p)}
    images_at_head = [p for p in git_lines("ls-tree", "-r", "--name-only", head, "--", "assets/")
                      if README_IMAGE_RE.match(p)]
    fresh = FreshRender(head, images_at_head)
    found = []
    for path in changed_ui:
        families = families_for(path[len(UI_ROOT):])
        if families is None:
            if not changed_images:
                found.append(f"{path} changed and no README image changed since {base}.")
            continue
        redrawn = [f for f in families if family_redrawn(f, images_at_head, changed_images)]
        if redrawn:
            print(f"  ✓ {path}: assets/{redrawn[0]} redrawn (every variant changed)")
            continue
        current = [f for f in families if fresh.matches(f)]
        if current:
            print(f"  ✓ {path}: assets/{current[0]} matches a fresh render of {head}")
            continue
        names = ", ".join(f"assets/{f}{{,-ko,-ja}}" for f in families)
        found.append(f"{path} changed since {base}; redraw {names} (every language variant). {fresh.reason(families)}")
    return found


class FreshRender:
    """Committed variants of a family compared with PTB_README_FRESH_DIR through png-diff."""

    def __init__(self, head, images_at_head):
        self.head, self.images = head, images_at_head
        self.dir = os.environ.get("PTB_README_FRESH_DIR")
        self.noise = os.environ.get("PTB_README_NOISE_DIR")
        self.failures = {}

    def matches(self, family):
        if not self.dir:
            return False
        variants = [p for p in self.images if family_of(p) == family and p.endswith(".png")]
        if not variants:
            self.failures[family] = "no PNG variant"
            return False
        diff = png_diff()
        for path in variants:
            name = Path(path).name
            rendered = Path(self.dir) / name
            if not rendered.is_file():
                self.failures[family] = f"{name} missing from the fresh render"
                return False
            with tempfile.TemporaryDirectory() as scratch:
                committed = Path(scratch) / name
                committed.write_bytes(subprocess.run(["git", "show", f"{self.head}:{path}"], capture_output=True,
                                                     check=True).stdout)
                second = Path(self.noise) / name if self.noise else None
                noise = diff.noise_mask(rendered, second, 0) if second and second.is_file() else None
                changed, _, box, _ = diff.compare(committed, rendered, 0, noise)
            if changed != 0:
                self.failures[family] = f"{name} differs from the fresh render ({'size' if changed < 0 else box})"
                return False
        return True

    def reason(self, families):
        if not self.dir:
            return "No fresh render (PTB_README_FRESH_DIR) to compare with."
        return "Fresh render: " + "; ".join(self.failures.get(f, "not checked") for f in families) + "."


def png_diff():
    spec = importlib.util.spec_from_file_location("png_diff", Path(__file__).with_name("png-diff.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def families_for(ui_relative_path):
    for pattern, families in SCREENS:
        if fnmatch.fnmatchcase(ui_relative_path, pattern):
            return families
    return None


def family_redrawn(family, images_at_head, changed_images):
    """True when every language variant of one format (the PNGs, or the GIFs) changed."""
    variants = [p for p in images_at_head if family_of(p) == family]
    formats = {Path(p).suffix for p in variants}
    return any(all(p in changed_images for p in variants if Path(p).suffix == f) for f in formats)


def family_of(image_path):
    return LANGUAGE_SUFFIX_RE.sub("", Path(image_path).stem)


def missing_new_image(base, head):
    """A UI feat needs a README image that did not exist at base and that every README shows."""
    feats = [s for s in git_lines("log", "--format=%s", f"{base}..{head}", "--", UI_ROOT) if FEAT_RE.match(s)]
    if not feats:
        return []
    added = [p for p in git_lines("diff", "--name-only", "--diff-filter=A", f"{base}..{head}", "--", "assets/")
             if README_IMAGE_RE.match(p)]
    readmes = [git_show(head, readme) for readme in READMES]
    if any(all(shows_family(text, family_of(p)) for text in readmes) for p in added):
        return []
    return ([f"UI feats since {base} and no new README image (assets/screenshot-*) shown in all three READMEs:"]
            + [f"    {s}" for s in feats]
            + ["    Draw the new screen, add it to README.md, README.ko.md and README.ja.md, and commit it."])


def shows_family(readme_text, family):
    return re.search(rf"assets/{re.escape(family)}(-ko|-ja)?\.(png|gif)", readme_text) is not None


def git_lines(*args):
    out = subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout
    return [line for line in out.splitlines() if line]


def git_show(ref, path):
    out = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else ""


def print_checklist():
    print("""  ─ Manual checklist ─────────────────────────────────────────────
   [ ] README.md / .ko / .ja: feature list, requirements, data sources, screenshots
   [ ] Landing (gh-pages/index.html): feature cards, en/ko/ja i18n keys, image copies
   [ ] homebrew-tap cask caveats
  ────────────────────────────────────────────────────────────────""")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
