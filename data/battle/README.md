# Battle data

The rule data the YPoke battle bot runs and the app's tests read. Every item, ability and move PokéAPI lists for
Gen 9 singles has one entry, and every entry says what the bot does with it.

| File | Keyed by | Read by |
|---|---|---|
| `items.json` | item slug | `bot/ypoke/items.py`, `mega_stones.py`, `tera_forms.py`; the app's item tests; `scripts/generate-item-lore.py` (names) |
| `abilities.json` | ability slug | `bot/ypoke/abilities.py` |
| `moves.json` | move id | `bot/ypoke/move_effects.py`, `move_power.py`, `pokeapi.py`, `mega_stones.py` |
| `coverage-baseline.json` | kind | `bot/tests/test_battle_data.py`, `BattleDataCoverageTests` |

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

Hand-set fields, kept on regeneration: `effect`, `args`, `flags` (`["punch"]`), `note`, `bot_name` (the bot's Korean
name when it differs from the official one), `pokeapi` (the PokéAPI slug when it differs from the key; `null` for an
item PokéAPI lacks, whose `names` are then hand-set too) and `names_extra`.

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
