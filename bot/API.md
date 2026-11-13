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

Unknown keys are ignored, so the app can send more fields later.
At battle time, chosen moves the Pokémon can no longer use (it evolved, say) are dropped; if none
are left it uses the defaults.

While the user has only an egg and no kept catch, the app sends a rental Gen-1 starter
(`{"pokemon_id": 1|4|7, "level": 5, "rental": true}`, no `moves`).

The first upload that makes both sides of a waiting challenge ready plays it (see README).

Responses:

| Status | Body |
|---|---|
| `200` | `{"ok": true, "party_size": 1}` |
| `400` | `{"ok": false, "error": "<reason>"}` — bad JSON or a rule above broken |
| `401` | `{"ok": false, "error": "unauthorized"}` — missing or unknown token |
| `413` | `{"ok": false, "error": "too_large"}` |
| `503` | `{"ok": false, "error": "pokeapi_unavailable"}` — `moves` sent and PokéAPI could not be reached to check them |

## `GET /v1/party`

Returns the stored party with the same shape, plus `"uploaded_at"` (ISO 8601 UTC).
`404 {"ok": false, "error": "no_party"}` if nothing was uploaded yet. Auth as above.

## `GET /v1/moves?pokemon_id=25&level=42`

The attacking moves a Pokémon knows by that level, oldest first: level-up moves from the newest
main game it is in, without status moves or moves with no fixed power. Auth as above.

```json
{
  "ok": true,
  "moves": [
    {"id": 84, "name": "전기쇼크", "type": "electric", "power": 40,
     "damage_class": "special", "accuracy": 100, "pp": 30, "crit_rate": 0,
     "ailment": "paralysis", "ailment_chance": 10, "priority": 0,
     "stat_changes": [], "stat_target": "target", "stat_chance": 0, "level": 1}
  ],
  "default": [84]
}
```

`default` is what the bot uses when the upload sends no `moves`. `accuracy` is `null` for moves that
never miss.

| Field | Meaning in the battle |
|---|---|
| `pp` | Uses before the move runs out. With every move out of PP the Pokémon uses 발버둥 (typeless, 50 power, loses 1/4 of its max HP) |
| `crit_rate` | Critical-hit stage: 0 → 1/24, 1 → 1/8, 2 → 1/2, 3+ → always |
| `ailment`, `ailment_chance` | `"burn"` or `"paralysis"` (or `null`) and its percent chance. Burn: 1/16 max HP each turn and half physical damage; fire types are immune. Paralysis: half speed and a 1 in 4 chance to lose the turn; electric types are immune |
| `priority` | Higher priority acts first (Quick Attack is `1`); equal priority falls back to speed, and a full tie is a coin flip |
| `stat_changes`, `stat_target`, `stat_chance` | Stage changes (`attack`, `defense`, `special_attack`, `special_defense`, `speed`, −6..+6) on the `"target"` or the `"user"`, with a percent chance |

Other secondary effects (poison, flinch, recoil, drain) are not simulated. `400` for a missing or out-of-range query, `503 pokeapi_unavailable` when PokéAPI is down.

## `GET /v1/health`

No auth. `200 {"ok": true}`.

## Client notes

- Post every few minutes and when the raised Pokémon or the entry changes. Failures (timeout, no route when
  working from home, 5xx) should be silent; the bot keeps the last party.
- Plain HTTP on a local network. Treat the token as a password: store it in the
  Keychain, never log it.
