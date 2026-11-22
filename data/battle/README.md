# Battle data

The rule data the YPoke battle bot runs and the app's tests read. Every item, ability and move PokéAPI lists for
Gen 9 singles has one entry, and every entry says what the bot does with it.

| File | Keyed by | Read by |
|---|---|---|
| `items.json` | item slug | `bot/ypoke/items.py`, `mega_stones.py`, `tera_forms.py`; the app's item tests; `scripts/generate-item-lore.py` (names) |
| `abilities.json` | ability slug | `bot/ypoke/abilities.py` |
| `moves.json` | move id | `bot/ypoke/move_effects.py`, `move_power.py`, `pokeapi.py`, `mega_stones.py` |
| `coverage-baseline.json` | kind | `bot/tests/test_battle_data.py`, `BattleDataCoverageTests` |
| `showdown-events.json` | kind, then entry | `bot/tests/test_showdown_events.py` |

The bot reads these files through `bot/ypoke/battle_data.py`. Nothing reads PokéAPI for them at run time.

## An entry

```json
"charcoal": {"names": {"ko": "목탄", "en": "Charcoal", …}, "category": "type-enhancement",
             "summary": "Held: Fire-Type moves from holder do 20% more damage.",
             "effect": "type-boost", "args": {"type": "fire"}}
```

`effect` is one of:

- a key, `"leftovers"`: the bot runs that effect.
- a list of keys, `["sand-force", "weather-chip-immune"]`: the bot runs each one. A list may hold `"todo"` next to
  keys when part of the Gen 9 effect is still missing, `["rocky-helmet", "todo"]`.
- `"todo"`: the bot does nothing with it yet.
- `{"inert": "<reason>"}`: nothing to do in this format, and the reason says why (doubles only, no effect while held,
  not learnable).

Every key must exist in the bot (`EFFECT_KEYS` in the module that runs it), and every bot key must be named by at
least one entry. Keys shared by a group take their parameters from `args` (`"type-boost"` reads `args.type`).

Fields from PokéAPI, rewritten on regeneration: `names` (app languages PokéAPI has), `category`, `summary`, and for
moves `slug`, `type`, `class`, `power`, `accuracy`, `priority`, `pp` and `meta`.

The `"contact"` move flag comes from Pokémon Showdown's `data/moves.ts` (`flags.contact`), because PokéAPI has none:
`bot/tools/generate_battle_data.py --showdown-contact <moves.ts>` sets it from the commit in `SHOWDOWN_COMMIT`.
Showdown is MIT-licensed; its license is in `LICENSE-showdown`.

`showdown-events.json` records, from the same Showdown commit, which hit events (onAfterSubDamage, onDamagingHit, onAfterHit, onAfterMoveSecondary[Self], onAfterMove, onDamage, onTryPrimaryHit) each entry and its condition handle, and whether each move has secondaries (what Sheer Force boosts). `bot/tools/generate_battle_data.py --showdown-events <showdown>/data` rewrites it; `test_showdown_events.py` checks the bot's hooks against it.

Hand-set fields, kept on regeneration: `effect`, `args`, `flags` (`["punch"]`), `note`, `bot_name` (the bot's Korean
name when it differs from the official one), `pokeapi` (the PokéAPI slug when it differs from the key; `null` for an
item PokéAPI lacks, whose `names` are then hand-set too) and `names_extra`.

## Effect handlers

Each key has one handler in `bot/ypoke/effects/` (`abilities.py`, `items.py`, `moves.py`, and `field.py` for terrains, side states, hazards and the moves and abilities keyed to them). A handler is a class that
`@register`s under its keys and defines the hooks it needs; `battle.py` keeps the turn loop and calls the hooks. A key
that acts outside the battle loop (Mega Stones, `badly-poisons`, `judgment`) is registered with `elsewhere(...)` and a
note of where it acts. `bot/tests/test_effect_registry.py` fails when a key has no handler, a handler has no key, a
handler method is not a hook, or two keys of one entry run the same hook.

A move key is found from the move's `effect`, `weather` and `always_hits_in` fields, or by the move's id for the
`by_id` keys (the power rules, `knock-off`, `facade`, `hydro-steam`, `weather-ball`, and `move_effects.ID_KEYS`: `always-crit`, `never-miss` and the terrain-keyed moves).

### Adding an effect

1. Give the entries the key in their JSON file (`effect`, plus `args` for a shared key), and add the key to the
   module's `EFFECT_KEYS` (`items.py`, `abilities.py`, `move_effects.py`, `move_power.py` or `pokeapi.py`).
2. Write the handler in `bot/ypoke/effects/<kind>.py`: `@register("<kind>", "<key>")` on a `Handler` subclass with
   the hooks it needs. Use a hook from the list below; add one to `effects/hooks.py` `HOOKS` and its call in
   `battle.py` only when no hook fits.
3. Write a test that the effect triggers and one that it does not (the other branch of its condition).
4. Shrink the coverage baseline (below) for the entries that were todo.

The golden event logs (`bot/tests/golden/`) pin every battle the corpus plays. A new effect changes them only when
an entry in the corpus now runs it; rewrite them on purpose with
`cd bot && WRITE_GOLDEN=1 uv run pytest tests/test_battle_golden.py -k write_golden_event` and read the diff.

### Hook order

The hooks in the order a turn reaches them (`HOOKS` in `effects/hooks.py` says who runs each):

1. Entry: `hazard` (each hazard on the side, in the order it was set, unless `ignores_hazards`), `on_entry_form`
   (item forms, after the hazards and Mega Evolution), `on_entry` (abilities, the faster Pokémon first; a Surge sets
   its terrain for `state_turns`), `on_update` (one-use items).
2. Choosing: `forces_move` (Encore), `wanted` (item moves ask the items' `burdens` and `craves`),
   `bars_status_moves`. A sleeping Pokémon still acts with a move whose `acts_asleep` holds (Sleep Talk).
3. Order: `modify_type`, `modify_priority`, `moves_first`, `modify_stat` (item, then ability; paralysis halves Speed
   in between; `swaps_stat` picks the raw stat under Wonder Room), then `field_stat` (ability under a state) and
   `side_stat` (Tailwind). `suppresses_items` (Magic Room, Embargo) idles every item hook of the Pokémon it covers.
4. The move: `bans_move` (Gravity, Taunt; Heal Block bans the moves whose `heals` holds) and the foe's
   `bans_foe_move` (Imprison), after PP `calls` (Metronome: the called move runs the rest of this step in its place
   and the action names the caller in `via`), `retypes_move` (Electrify),
   `locks_move`, `backfires` (Powder), `stops_move` (Psychic Terrain, Protect, with its `punishes` on the user;
   `targets_foe` says which status moves it stops), `use` (status and weather moves, with `weather_turns` and
   `state_turns`; a status move aimed at the foe meets its `shields` (Substitute) and `reflects` (Magic Coat), one aimed
   at its user the foe's `snatches`; `never_misses` skips its accuracy draw; Teatime and Stuff Cheeks run the
   item's `eaten`), `before_hit` (Brick Break), `skips_accuracy` or the target's `sure_hit`
   (Lock-On), the accuracy and evasion stages (unless `exposes`) × `accuracy_as_user` × `accuracy_as_target` ×
   `modify_accuracy` (Gravity), `grounds`, `lifts` and `airborne` before `immune_to` and `exposes` (Foresight),
   `crit_stage` (move, item, then state: Focus Energy) unless `guards_crit` (Lucky Chant).
5. Damage, in this multiplication order (type effectiveness × the target's `weakens`, Tar Shot):
   `ignores_burn` (on the Attack stat), `base_power`, `modify_power` ×
   `field_power` (terrain), `modify_stab`, `modify_weather_boost`, `modify_damage_taken`, `modify_damage`, `screen`
   (passed by a crit or `infiltrates`).
6. Each hit: `resists` (first hit), `takes_hit` (Substitute: the target and its secondary effects are spared),
   `endures` (state, ability, then item), `on_contact_hit`, `between_hits`; `on_knocked_out` (Destiny Bond) once the
   target faints.
7. After the hits: `guards_ailment` (terrain, Safeguard) and `blocks_ailment`, `guards_stats` (Mist), `on_contact`,
   then recoil or `modify_drain`, then `after_move_as_user`, `after_move_as_target`, `after_move`; `faints_user`,
   `switches_user_out`, `remember`.
8. End of turn, `battle.END_OF_TURN`: residual status damage, weather chip (`blocks_weather_chip`), terrain
   (`end_of_turn`: Grassy Terrain's heal), items (`end_of_turn`, then `on_update`), each Pokémon's own states
   (`volatile_end`: Leech Seed, Perish Song, the countdowns), Yawn, the side states' turns, Trick Room, the rooms'
   turns, the terrain's and Gravity's turns, strong winds (`keeps_weather`), replacing fainted Pokémon (who take the
   hazards).

### Where the order differs from Gen 9

Kept as it is so the battles stay the same; a change here rewrites the golden logs.

- Burn and poison damage come first at the end of a turn. Gen 9 runs them after weather and Leftovers.
- Flame Orb and Toxic Orb act with Leftovers. Gen 9 runs them near the end, after status damage.
- A contact ability hits back once per move, after the hits. Gen 9 checks it on every contact hit.

## Coverage ratchet

`coverage-baseline.json` lists every todo entry and the counts per file. The bot test and `BattleDataCoverageTests`
fail when an entry turns todo that the baseline does not list, or when a listed entry is no longer todo. After you
give a todo entry a key or an inert reason, rewrite the baseline:

```sh
cd bot && WRITE_BASELINE=1 uv run pytest tests/test_battle_data.py::test_write_baseline
```

## Regenerating

```sh
cd bot && uv run python tools/generate_battle_data.py <scratch-cache.db>
```

The cache is a scratch SQLite file, never the bot's database; a rerun reads PokéAPI from it. New entries get a
default effect: inert by category or rule, `"damage"` for a move whose whole effect is plain damage, else `"todo"`.

## Deploying

The bot reads `data/battle/` next to `bot/`, so a deploy copies both directories.
