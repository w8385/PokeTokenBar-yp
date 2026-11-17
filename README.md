# PokeTokenBar website

Static landing page for https://w8385.github.io/PokeTokenBar-yp/ (fork of chattymin/PokeTokenBar), maintained on the `gh-pages` lineage. App source lives on `main`. This branch does not build or replace the native app.

## Local preview and verification

```sh
npm ci
npm run preview
# http://127.0.0.1:8765

npm test
npm run design:check
```

`npm test` starts its own local server on port 18765, uses installed Google Chrome on this Mac, and saves screenshots plus results under `test-results/`. Set `CHROME_PATH` for a different local Chrome executable. The suite covers three languages, responsive layouts, light/dark themes, axe accessibility scans, keyboard controls, clipboard errors, no JavaScript and unavailable local storage. There is no website production build step.

## Design tools

Impeccable and Hallmark are project-local development tools, not website runtime dependencies. Their installed payloads are ignored by Git; `.codex/hooks.json` and these setup instructions are retained.

```sh
npm run design:install
```

This runs the official Impeccable 4.1.0 installer for Codex in project scope. The installed skill reports version 4.3.1 and engine 0.1.5 at this snapshot; the installer retrieves the upstream skill payload separately. Use the installed launcher for checks, so they don't fetch a new version on every run.

Hallmark 1.1.0 is installed at `.agents/skills/hallmark/` from [Nutlope/hallmark](https://github.com/Nutlope/hallmark/tree/main/skills/hallmark). On this Mac it can be reinstalled using:

```sh
python3 /Users/patrick.park/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo Nutlope/hallmark --path skills/hallmark --dest .agents/skills
```

Newly installed skills are available on the next task turn. The Impeccable installer writes Codex PostToolUse and Stop hooks. Reload/open this project and inspect `/hooks`; Codex may require trusting the new hook definition. Installed/enabled configuration is not evidence that the already-running parent task has reloaded it. The current redesign was checked explicitly with `npm run design:check`.

The official hook intentionally becomes a no-op if its launcher is missing. Our manual `design:check` command instead reports the missing installation and exits with failure. No CI, telemetry backend, external posting or scheduled automation was added.

## Sources of truth

- `PRODUCT.md`: product facts, constraints and image provenance.
- `DESIGN.md`, `tokens.css`: implemented visual decisions and tokens.
- `.impeccable/surfaces/landing.md`: this page's goal, sequence and direction.
- `docs/design-references.md`: ten inspected references, tool selection and post-build critique.

`index.html` includes readable English fallback content. `app.js` applies the English/Korean/Japanese dictionaries using text nodes, plus separately translated image descriptions and ARIA labels. Six native sample image families switch to matching EN/KO/JA files; the shared Home sample stays English. Keep the fallback copy and dictionaries aligned when changing wording.

## Assets

The 2.5.6 Home, forms, Bag, Shop, difficulty, daily trend and recap images are native production SwiftUI/AppKit renders with isolated sample data. Six families have English/Korean/Japanese variants; Home is English in every website language. Captions distinguish these from the retained English quota, pace, collection and desktop-pet examples. See [the capture provenance](assets/README-release-2.5.6.md) for source revisions, scroll-region scope and offline fallbacks.

`floating-pet-still.png` is the first frame of the existing `floating-pet.gif`; its animation is user initiated. The growth sequence keeps its separate play/pause control and reduced-motion preference. The local Bricolage Grotesque font is distributed under `assets/fonts/OFL.txt`, from the [Google Fonts source](https://github.com/google/fonts/tree/main/ofl/bricolagegrotesque). Kimi Code’s icon is the official site’s [public app icon](https://www.kimi.com/pwa-192.png), retrieved on 2026-10-16; other provider icons are preserved from the redesign.

## Publishing

The preview is local. Publishing requires reviewing the change and explicitly authorizing the `gh-pages` update; opening a preview does not deploy it. Preserve `.nojekyll` and the existing public anchors. Do not merge this orphan website branch into the app's `main` branch.
