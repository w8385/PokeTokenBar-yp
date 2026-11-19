---
summary: "The UI design tokens (palette, type scale, radii, spacing, shadows) and shared components under UI/Design, and the scanner that keeps raw literals out of the views."
read_when:
  - Changing how a screen looks or building a new screen
  - A view needs a color, font size, corner radius or shadow
  - DesignTokenScanTests fails
  - Proving a styling refactor changed no pixels (scripts/ui-shots.sh, scripts/png-diff.py)
---

# Design system

Every look that more than one view shares lives in `Sources/PokeTokenBar/UI/Design/`. A view picks a token
by meaning. It does not write a number.

## Tokens

| Group | API | Values |
|---|---|---|
| Type scale | `.font(.ptb(.body, weight:, design:))`, `FontSize` | micro 7, tiny 8, caption 9, small 10, body 11, label 12, control 13, lead 15, headline 17, title 22, display 24, hero 28 |
| Radius | `Radius.x` | hairline 1, bar 2, chip 6, card 8, panel 10, sheet 12 |
| Spacing | `Spacing.x` | xxs 2, xs 4, sm 6, md 8, lg 12, xl 16 |
| Shadow | `.ptbShadow(.lift)`, `ShadowStyle` | lift (0.25, 4, y 2), bubble (0.15, 4, y 2, scaled), glyph (0.35, 0.5, y 0.5), none |
| Color | `Palette.x`, `Palette.Recap.x` | provider series, sun, moon, heart, the recap handheld |

Text that follows Dynamic Type keeps the system styles (`.caption`, `.callout`). `.ptb` is for fixed-size
glyphs, badges, chips and the recap LCD, where the size is part of the layout. Scale a size with the view it
sits in through `.ptb(.body, scale: k)`. Semantic colors (`.primary`, `.secondary`, `Color.accentColor`,
`NSColor.controlBackgroundColor`) stay as they are: they follow light, dark and the user's accent.

## Components

| Modifier or type | Look | Used for |
|---|---|---|
| `.ptbCard()` | control background, separator hairline, `Radius.card` | grouped settings rows, coworker list, growth-mode and battle sections |
| `.ptbPanel(radius:)` | `secondary` at 7%, `Radius.card` | species flavor, evolution card, friend rows, unowned detail |
| `.ptbChip(active:)` | control background, hairline, `Radius.chip`; `ChipTint.accent` / `.shiny` while on | filter toggles, sort, search box |
| `.speechBubbleSurface(_:)` | window background, tail, `ShadowStyle.bubble` | every pet bubble (see `Design/Bubble.swift`) |
| `PressButtonStyle` | scales to 0.9 while pressed | clickable sprites |

Add a component when a third view needs the same recipe. Two copies can stay inline.

## The guard

`DesignTokenScanTests` (listed in `scripts/invariant-tests.sh`) fails on a raw `Color(red:`, a numeric
`.font(.system(size:` or a numeric `cornerRadius:` anywhere under `Sources/PokeTokenBar` except the token
files. Computed values pass (`size * 0.8`, `Radius.card * scale`). The allowlist is one entry: `Palette.swift`
may hold `Color(red:`. Sprite crop and fit math, chart geometry and layout constants need no entry because the
rules look at colors, font sizes and corner radii only.

Padding and frame literals are not scanned. New code should reach for `Spacing` where a value is a gap
between siblings.

## Proving a styling change moved nothing

```bash
./scripts/ui-shots.sh /tmp/ui-before       # on the base commit
./scripts/ui-shots.sh /tmp/ui-noise        # same commit again
./scripts/ui-shots.sh /tmp/ui-after        # on the branch
python3 scripts/png-diff.py /tmp/ui-before /tmp/ui-after --noise /tmp/ui-before /tmp/ui-noise
```

`ui-shots.sh` renders the offscreen screenshot suites into one folder. A suite that hosts its view in a
window (`OffscreenRender.windowHosting`) is left out. Run the baseline twice: clocks and animation phase
change a few pixels between identical renders, and `--noise` ignores those pixels. Expect only the values you
merged on purpose to differ.
