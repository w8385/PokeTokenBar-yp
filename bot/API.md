# YPoke party upload API

The app posts the user's battle Pokémon to the YPoke bot. The bot keeps only the latest
upload per user and sends out its first Pokémon in one-on-one `/대결` battles. Battles
never change the party.

- Base URL: the bot's `YPOKE_PUBLIC_URL`, for example `http://<bot-host>:8790`
- Auth: `Authorization: Bearer <token>`. Users get the token from `/포켓몬연결`:
  the bot DMs a button that opens `poketokenbar://ypoke-register?token=<token>&server=<base URL>`,
  and the app saves both. The DM also shows the token for pasting by hand.
  Running `/포켓몬연결` again issues a new token and revokes the old one.
- Body: JSON, UTF-8, at most 64 KB.

## `POST /v1/party`

Replaces the caller's stored party.

```json
{
  "app_version": "2.5.7",
  "party": [
    {
      "pokemon_id": 25,
      "level": 42,
      "name": "피카츄",
      "shiny": false,
      "nature": "adamant",
      "ivs": {"hp": 31, "attack": 20, "defense": 15,
              "special_attack": 31, "special_defense": 10, "speed": 28},
      "moves": [85, 87, 209, 98]
    },
    {"pokemon_id": 7, "level": 30}
  ]
}
```

| Field | Type | Rules |
|---|---|---|
| `app_version` | string | optional, max 32 chars |
| `party` | array | The battle Pokémon: the one chosen in the app's battle tab, or the Pokémon being raised. Up to 6 are accepted for older clients; battles use the first |
| `pokemon_id` | int | PokéAPI `/pokemon/{id}` id: `1..1025`, or `10001..10999` for alternate forms |
| `level` | int | `1..100`. Battles use `min(level, 50)`; moves stay what the Pokémon knows at its real level |
| `name` | string | optional display name, max 40 chars. Default: Korean species name from PokéAPI |
| `shiny` | bool | optional, default `false`. Shown as ✨ in the battle log |
| `rental` | bool | optional, default `false`. A loaner: it fights at the opponent's level, capped at 50 (both keep their own when both are rentals) and is announced as "대여 포켓몬 …" |
| `nature` | string | optional, lowercase English nature name from the app (`"adamant"`). Raises one non-HP stat 10% and lowers another 10%, main-series table. Missing, empty or unknown names are neutral and never rejected |
| `ivs` | object | optional. Each key optional, `0..31`, default `15` |
| `moves` | array | optional, up to 4 distinct PokéAPI move ids, each an attacking move from `GET /v1/moves` at that level. Missing or empty: the 4 most recently learned |

### `dex` (optional)

A summary of the user's Pokédex for `/도감`. The bot keeps the latest one beside the party. An upload without
`dex` (an older app) keeps the stored one. A malformed `dex` is ignored, never a `400`.

```json
"dex": {
  "owned": 120,
  "shiny": 3,
  "regions": {"kanto": 151, "johto": 40},
  "representative": {"pokemon_id": 25, "shiny": true}
}
```

| Field | Type | Rules |
|---|---|---|
| `owned` | int | Species owned, `0..1025` |
| `shiny` | int | Species owned as shiny, `0..1025` |
| `regions` | object | Species owned per region. Keys `kanto johto hoenn sinnoh unova kalos alola galar paldea`; a value above the region's size, or an unknown key, is dropped |
| `representative` | object | optional, the Pokémon the app shows (`pokemon_id` as in `party`, `shiny` bool). Missing while the user has only an egg |

Unknown keys are ignored, so the app can send more fields later.
At battle time, chosen moves the Pokémon can no longer use (it evolved, say) are dropped; if none
are left it uses the defaults.

While the user has only an egg and no kept catch, the app sends a rental Gen-1 starter
(`{"pokemon_id": 1|4|7, "level": 5, "rental": true}`, no `moves`).

The first upload that makes both sides of a waiting challenge ready plays it (see README).

Responses:

| Status | Body |
|---|---|
| `200` | `{"ok": true, "party_size": 1, "recent_battles": [...], "coworkers": [...]}`, see below |
| `400` | `{"ok": false, "error": "<reason>"}` — bad JSON or a rule above broken |
| `401` | `{"ok": false, "error": "unauthorized"}` — missing or unknown token |
| `413` | `{"ok": false, "error": "too_large"}` |
| `503` | `{"ok": false, "error": "pokeapi_unavailable"}` — `moves` sent and PokéAPI could not be reached to check them |

### Battle info in the `200` body

Both lists are fresh on every upload. Names only: the body never carries Slack ids or tokens. Apps
that do not know these fields ignore them, and an old bot omits them.

```json
{
  "recent_battles": [
    {"opponent_name": "민수", "my_pokemon_id": 25, "opponent_pokemon_id": 7,
     "result": "win", "turns": 6, "at": "2026-11-13T05:20:11+00:00"}
  ],
  "coworkers": [
    {"name": "은정", "pokemon_id": 6, "level": 55, "shiny": true}
  ]
}
```

| Field | Rules |
|---|---|
| `recent_battles` | The uploader's last 5 stored battles (practice battles against the bot are not stored), newest first |
| `opponent_name` | Slack display name; `null` when Slack cannot be asked |
| `my_pokemon_id`, `opponent_pokemon_id`, `turns` | Lead species ids (same ids as `pokemon_id` above) and the turn count; `null` for battles stored before the bot kept them |
| `result` | `"win"` or `"loss"` for the uploader |
| `at` | ISO 8601 UTC |
| `coworkers` | The first Pokémon of every other user's latest upload from the last 30 days, newest upload first, at most 30 |
| `name`, `pokemon_id`, `level`, `shiny` | `name` is the Slack display name or `null`; `level` is the real level, not the battle level |

## `GET /v1/party`

Returns the stored party with the same shape, plus `"uploaded_at"` (ISO 8601 UTC).
`404 {"ok": false, "error": "no_party"}` if nothing was uploaded yet. Auth as above.

## `GET /v1/moves?pokemon_id=25&level=42`

The moves a Pokémon can bring by that level, oldest first: level-up moves from the newest
main game it is in. Attacking moves only, plus the weather moves (Sunny Day, Rain Dance, Sandstorm,
Hail, Snowscape), which come with `"power": 0` and `"damage_class": "status"`. Auth as above.

```json
{
  "ok": true,
  "moves": [
    {"id": 84, "name": "전기쇼크", "type": "electric", "power": 40,
     "damage_class": "special", "accuracy": 100, "pp": 30, "crit_rate": 0,
     "ailment": "paralysis", "ailment_chance": 10, "priority": 0,
     "drain": 0, "min_hits": 1, "max_hits": 1,
     "stat_changes": [], "stat_target": "target", "stat_chance": 0,
     "weather": null, "always_hits_in": [], "level": 1}
  ],
  "default": [84]
}
```

`default` is what the bot uses when the upload sends no `moves`: the latest attacking moves, never a weather move. `accuracy` is `null` for moves that
never miss.

| Field | Meaning in the battle |
|---|---|
| `pp` | Uses before the move runs out. With every move out of PP the Pokémon uses 발버둥 (typeless, 50 power, loses 1/4 of its max HP) |
| `crit_rate` | Critical-hit stage: 0 → 1/24, 1 → 1/8, 2 → 1/2, 3+ → always |
| `ailment`, `ailment_chance` | `"burn"`, `"paralysis"`, `"poison"`, `"toxic"`, `"sleep"`, `"freeze"`, `"confusion"` (or `null`) and its percent chance. Burn: 1/16 max HP each turn and half physical damage; fire types are immune. Paralysis: half speed and a 1 in 4 chance to lose the turn; electric types are immune. Poison: 1/8 max HP each turn; toxic: 1/16 more each turn; poison and steel types are immune. Sleep: 1–3 turns lost. Freeze: 20% thaw each turn, a fire move thaws it; ice types are immune. Confusion: 2–5 turns, a 1 in 3 chance each turn to hurt itself (40 power); no type is immune. A target takes one of the first six at a time, confusion on top |
| `drain` | Percent of the damage dealt: positive heals the user (Giga Drain `50`), negative is recoil (Take Down `-25`) |
| `min_hits`, `max_hits` | Multi-hit range; 2–5 hits use the main series odds (35%, 35%, 15%, 15%) |
| `priority` | Higher priority acts first (Quick Attack is `1`); equal priority falls back to speed, and a full tie is a coin flip |
| `stat_changes`, `stat_target`, `stat_chance` | Stage changes (`attack`, `defense`, `special_attack`, `special_defense`, `speed`, −6..+6) on the `"target"` or the `"user"`, with a percent chance |

| `weather` | `"sun"`, `"rain"`, `"sandstorm"`, `"hail"` or `"snow"` for a move that sets weather for 5 turns, else `null`. The Pokémon uses it only when it swings the exchange in its favor and that weather is not already up. Sun/rain: Fire and Water damage ×1.5 / ×0.5 (rain the other way round). Sandstorm: 1/16 max HP each turn to everything but Rock, Ground and Steel, and Rock Special Defense ×1.5. Hail: the same chip, Ice is immune. Snow: Ice Defense ×1.5 |
| `always_hits_in` | Weathers in which the move never misses (Thunder and Hurricane in `"rain"`, Blizzard in `"hail"`, `"snow"`) |

Other secondary effects (flinch, trapping) are not simulated. `400` for a missing or out-of-range query, `503 pokeapi_unavailable` when PokéAPI is down.

## `GET /v1/health`

No auth. `200 {"ok": true}`.

## Client notes

- Post every few minutes and when the raised Pokémon or the entry changes. Failures (timeout, no route when
  working from home, 5xx) should be silent; the bot keeps the last party.
- Plain HTTP on a local network. Treat the token as a password: store it in the
  Keychain, never log it.
