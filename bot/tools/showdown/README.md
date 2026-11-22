# Showdown scenario recorder

Records how Pokémon Showdown resolves one move for each scenario in `scenarios.mjs` and writes
`bot/tests/showdown/<name>.json`. `bot/tests/test_showdown_scenarios.py` replays each one in the bot and compares the
state the move leaves (HP only as the sign of its change). CI reads the committed fixtures and never runs node.

Re-record after changing a scenario or the Showdown pin:

```sh
cd bot/tools/showdown && npm ci && npm run build-showdown && npm run record
```

Showdown is pinned to the commit in `package.json`, the same one as `SHOWDOWN_COMMIT` in
`bot/tools/generate_battle_data.py`. Move both together.

Every random chance is forced: all land, or none when a scenario sets `chance: false`. Hit counts of 2–5 hit moves
and picks such as Tri Attack's status are not forced, so no compared fact may depend on them.
