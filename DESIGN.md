---
name: PokeTokenBar
description: Neutral surfaces, red accents and product illustrations.
colors:
  paper: "oklch(98% 0 0)"
  surface: "oklch(100% 0 0)"
  logo-surface: "oklch(100% 0 0)"
  soft: "oklch(95% .002 250)"
  stage: "oklch(92% .036 45)"
  ink: "oklch(25% .008 250)"
  muted: "oklch(47% .008 250)"
  rule: "oklch(85% .004 250)"
  accent: "oklch(49% .17 28)"
  accent-hover: "oklch(42% .16 28)"
  on-accent: "oklch(100% 0 0)"
  focus: "oklch(45% .17 255)"
  selection: "oklch(88% .07 45)"
  code: "oklch(24% .013 45)"
  code-ink: "oklch(95% .01 80)"
  success: "oklch(43% .1 155)"
  shadow: "oklch(20% .016 45 / .16)"
  dark-paper: "oklch(21% .004 250)"
  dark-surface: "oklch(25% .004 250)"
  dark-soft: "oklch(27% .004 250)"
  dark-stage: "oklch(32% .035 45)"
  dark-ink: "oklch(94% .004 250)"
  dark-muted: "oklch(75% .004 250)"
  dark-rule: "oklch(41% .004 250)"
  dark-accent: "oklch(75% .135 30)"
  dark-accent-hover: "oklch(83% .1 30)"
  dark-on-accent: "oklch(20% .02 30)"
  dark-focus: "oklch(80% .12 245)"
  dark-selection: "oklch(43% .08 35)"
  dark-success: "oklch(78% .12 155)"
  dark-shadow: "oklch(5% .01 45 / .35)"
typography:
  display:
    fontFamily: "\"Bricolage Grotesque\", -apple-system, BlinkMacSystemFont, \"Apple SD Gothic Neo\", sans-serif"
    fontSize: "clamp(3rem, 5.8vw, 5.25rem)"
    fontWeight: 750
    lineHeight: 1.08
    letterSpacing: "-.035em"
  headline:
    fontFamily: "\"Bricolage Grotesque\", -apple-system, BlinkMacSystemFont, \"Apple SD Gothic Neo\", sans-serif"
    fontSize: "clamp(2rem, 3.5vw, 3.25rem)"
    fontWeight: 650
    lineHeight: 1.08
    letterSpacing: "-.035em"
  title:
    fontFamily: "\"Bricolage Grotesque\", -apple-system, BlinkMacSystemFont, \"Apple SD Gothic Neo\", sans-serif"
    fontSize: "1.375rem"
    fontWeight: 700
    lineHeight: 1.08
    letterSpacing: "-.02em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"Apple SD Gothic Neo\", \"Hiragino Kaku Gothic ProN\", \"Segoe UI\", sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.65
  command:
    fontFamily: "ui-monospace, \"SFMono-Regular\", Menlo, monospace"
    fontSize: ".8125rem"
    fontWeight: 400
    lineHeight: 1.65
rounded:
  control: "8px"
  surface: "16px"
spacing:
  xs: ".5rem"
  sm: "1rem"
  md: "1.5rem"
  lg: "2rem"
  xl: "3rem"
  2xl: "4rem"
  3xl: "6rem"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.control}"
    padding: "12px 22px"
  button-primary-hover:
    backgroundColor: "{colors.accent-hover}"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "12px 22px"
---

# Design System: PokeTokenBar

## Overview

**Creative North Star: "A quiet desktop companion showcase"**

A neutral canvas gives the red identity and existing product illustrations room to carry the personality. Rounded display lettering adds playfulness; multilingual system body type keeps instructions readable. This records the implemented website, not an approved generated comp.

**Key Characteristics:**
- Neutral page with a bounded red-tinted product stage.
- Compact controls, generous section spacing and native disclosures.
- Light and dark theme tokens with visible keyboard focus.

## Colors

### Primary
Red `accent` identifies main actions, emphasized headline text and progress labels. `accent-hover` changes action state; `on-accent` supplies its foreground. Warm `stage` contains the hero illustration rather than tinting the entire page.

### Neutral
`paper` is the canvas and sticky header; `surface` supports secondary controls; `soft` groups quieter sections. `ink`, `muted` and `rule` separate reading levels and rows. `code` and `code-ink` form the installation command. Blue `focus` and green `success` communicate interaction state. The `dark-` entries replace matching base colors under the explicit dark theme; code colors remain unchanged.

**The Bounded Stage Rule.** Keep the warm hero stage bounded by the surrounding neutral canvas.

## Typography

The display, headline and title roles use the bundled Bricolage Grotesque stack. Body copy uses the system stack with Korean and Japanese fallbacks; commands use the mono stack. Paragraphs stop at 68ch, the hero explanation at 42ch. Headings balance lines and allow long content to wrap. Korean text keeps words together. Responsive hero sizes are defined in styles.css; preserve the separate Korean/Japanese phone treatment.

## Layout

The centered container caps at 1160px with 80px total outer space on wide screens, then 48px at 1000px, 40px at 760px and 32px at 380px. Two-column stories stack at 760px. Section spacing uses the recorded rem scale, reducing from 6rem to 4rem on phones. The sticky header is 80px tall, reducing to 72px; corresponding anchor offsets are 100px and 84px. Landing sequence and installation placement belong to `.impeccable/surfaces/landing.md`.

## Elevation & Depth

Tonal sections and fine rules establish most separation. The product shadow (`0 20px 44px var(--color-shadow)`) lifts the hero and collection illustrations. Controls and text sections stay flat.

**The Product Depth Rule.** Reserve the ambient product shadow for the illustrated product, as implemented.

## Shapes

Controls and images use the control radius; illustration stages and calculator containers use the surface radius. Fine one-pixel borders divide rows, disclosures and control boundaries. The command copy button has a local 6px radius, not a replacement for the shared control token.

## Components

- **Buttons:** primary red or neutral bordered secondary; minimum height 48px, weight 600, line height 1.4. Primary hover changes fill; secondary hover changes its border to ink. Press shifts one pixel, suppressed for reduced motion.
- **Navigation:** compact display wordmark, muted links with red hover, language select and SVG icon controls. Controls have 44px targets. On phones the menu reveals the link row; without JavaScript links remain available.
- **Fields:** native selects use an outlined surface, control radius and a 44px minimum height. Calculator fields use 8px 12px padding; the header language field uses its compact sizing.
- **Provider list:** all 16 linked names and official-site icons stay visible after the growth guide. Four columns reduce to three at 1000px and two at 760px. Icons sit on a fixed white logo surface in both themes to preserve the original brand marks.
- **Disclosures and tabs:** the growth guide has no disclosure; its selected topic is visible immediately. Native summary rows elsewhere reveal optional detail. Selected guide tabs invert ink and paper; wrapping keeps their 44px controls readable. Keep keyboard navigation and selected state semantics.
- **Product containers:** warm hero stage and neutral feature stages pad the example screens; captions remain outside the image. Preserve actual image proportions.
- **Command and feedback:** dark command strip, wrapping mono text, copy control and reserved status line. Success uses the success token; failure instructions remain readable.

All focusable controls use a 3px focus-color outline with 4px offset. The desktop demo begins as a still and plays only on request. Reduced motion disables smooth scrolling and pressed transforms. Unused easing/duration declarations are not an active animation system.

## Do's and Don'ts

### Do:
- Do use the semantic tokens in tokens.css for both themes.
- Do preserve readable example-screen captions and multilingual wrapping.
- Do keep keyboard focus visible and animation explicitly user-controlled.

### Don't:
- Don't introduce gradients, glow or simulated operating-system chrome.
- Don't turn every section into a raised card.
