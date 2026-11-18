# PokeTokenBar product facts

<!-- impeccable:product-schema 1 -->

## Platform

web

This repository branch is the public website for the native macOS app, not the app itself.

## Product Purpose

PokeTokenBar displays AI coding token usage in the macOS menu bar and uses accumulated tokens to hatch, evolve and collect Pokémon companions. A floating desktop pet is optional.

## Users

People using supported AI coding tools on a Mac. The installation and feature descriptions in the source README establish this audience. No user-count or conversion claims are established.

## Capabilities and Constraints

- This site is for the w8385/PokeTokenBar-yp fork of chattymin/PokeTokenBar. Fork release builds require macOS 14 or later on Apple Silicon.
- Free, open-source, unofficial and non-commercial fan project. MIT covers the project's own source code.
- Install with the Terminal command from the fork README, or download the `PokeTokenBar-yp-arm64.zip` release asset. The fork has no Homebrew cask; `chattymin/tap/poke-token-bar` installs the upstream app. Direct installation requires handling macOS Gatekeeper because the app is ad-hoc/self-signed; the Terminal command removes the quarantine attribute.
- Supported providers (16): Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent, omp, Aside, Kimi Code, omo (senpi), Devin CLI.
- Official usage limits are available for Claude, Codex and Antigravity. Do not imply official limits for every provider.
- Growth numbers come from `PokemonBalance` and `ClickGrowth` in `Sources/PokeTokenBar/Core/CompanionModel.swift` on main. `BALANCE` in app.js mirrors them, and `npm test` fails when they drift.
- Two growth sources: token mode (default; AI-coding tokens, cache reads included) and time mode (40M growth tokens and 10M wallet tokens per active hour). Clicking the partner adds growth in both modes.
- The Pokédex covers Gen 1–9 (#1025). The "Only in PokeTokenBar-yp" section lists features the upstream app does not have; keep it in step with `git log upstream/main..origin/main`.
- The battle bot is described only as the README describes it ("the YPoke Slack battle bot"). Never name an internal workspace or channel.
- Usage logs are not uploaded. The app makes network requests for provider usage/limits, Pokémon data and sprites, service status and updates. Do not claim it is completely offline.
- Companions hatch, evolve and graduate into a collection. Growth difficulty is adjustable. Rare Candy and the token shop affect progress; a fixed completion time is not a promise.
- The website supports English, Korean and Japanese. The app supports eight UI languages, including Russian; website language support is separate.
- Supported Gen 1–5 forms are retained per individual through evolution, saving and export. Form-specific types, stats, abilities and moves are not modeled: metadata uses the default form.
- Rare Candy supports quantity selection and an evolution/graduation preview with carryover; the Shop shows quantity and total price.
- Monthly daily bars use a fixed full-month axis, stacking by provider with a legend when at least two providers have usage in the month. Hover shows total/per-provider usage, with cost when enabled; idle days retain weekly/monthly history.
- Recaps cover past weeks/months/years with exact-count hovers and a shortcut to the current period.
- Automatic backup history starts collapsed; manual backup creation remains visible.

## Stack

Existing static HTML/CSS/JavaScript on the orphan `gh-pages` branch, served by GitHub Pages at https://w8385.dev/PokeTokenBar-yp/ (the owner's user-site custom domain). No website build step.

Six routes: home (`/`) plus five feature pages served as folder indexes (`/usage/`, `/growth/`, `/collection/`, `/battle/`, `/items/`), a `404.html` and a `sitemap.xml`. Home keeps the hero, install, the growth story, short links to the feature pages, the desktop companion and the guide; the detailed feature copy lives on the feature pages. `scripts/site.cjs` lists the pages for the stamp script and the tests.

## Evidence on Hand

- Main branch README files, native source and release documentation are the product authorities.
- Nineteen 2.5.6 Home/gallery PNGs are byte-identical native production-view renders with isolated sample data. They are not live user usage. Capture source/tree, exact view scope and fallbacks are in `assets/README-release-2.5.6.md`.
- Shop, difficulty, daily trend, recap, Box, held-item, gym and battle samples have EN/KO/JA images selected with the page language. The common Home image stays English and says so in all three languages.
- The retained quota, pace, collection and desktop-pet demonstrations are English examples; their captions remain separate from native sample labels.
- Download counts are requests, including upgrades and repeats. They are not unique users and are omitted from public social proof.
- No testimonials, customer logos, performance benchmarks or conversion figures have been supplied.

## Brand Commitments

Retain the PokeTokenBar name, app icon, Pokémon companion mechanism and fan-project attribution. Never imply Nintendo affiliation.
