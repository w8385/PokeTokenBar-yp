# YPoke party upload API

The app posts the Pokémon the user is raising to the YPoke bot. The bot keeps only
the latest upload per user and uses it for `/대결` battles, which are 1v1. Battles
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
      "ivs": {"hp": 31, "attack": 20, "defense": 15,
              "special_attack": 31, "special_defense": 10, "speed": 28}
    }
  ]
}
```

| Field | Type | Rules |
|---|---|---|
| `app_version` | string | optional, max 32 chars |
| `party` | array | 1 entry: the Pokémon being raised. Up to 6 are accepted for older clients; battles use only the first |
| `pokemon_id` | int | PokéAPI `/pokemon/{id}` id: `1..1025`, or `10001..10999` for alternate forms |
| `level` | int | `1..100` |
| `name` | string | optional display name, max 40 chars. Default: Korean species name from PokéAPI |
| `shiny` | bool | optional, default `false`. Shown as ✨ in the battle log |
| `ivs` | object | optional. Each key optional, `0..31`, default `15` |

Unknown keys are ignored, so the app can send more fields later.

The app sends nothing while the user has an egg (no Pokémon being raised).

Responses:

| Status | Body |
|---|---|
| `200` | `{"ok": true, "party_size": 1}` |
| `400` | `{"ok": false, "error": "<reason>"}` — bad JSON or a rule above broken |
| `401` | `{"ok": false, "error": "unauthorized"}` — missing or unknown token |
| `413` | `{"ok": false, "error": "too_large"}` |

## `GET /v1/party`

Returns the stored party with the same shape, plus `"uploaded_at"` (ISO 8601 UTC).
`404 {"ok": false, "error": "no_party"}` if nothing was uploaded yet. Auth as above.

## `GET /v1/health`

No auth. `200 {"ok": true}`.

## Client notes

- Post every few minutes and when the raised Pokémon changes. Failures (timeout, no route when
  working from home, 5xx) should be silent; the bot keeps the last party.
- Plain HTTP on a local network. Treat the token as a password: store it in the
  Keychain, never log it.
