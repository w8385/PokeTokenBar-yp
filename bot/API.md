# YPoke party upload API

The app posts the user's battle Pokémon to the YPoke bot. The bot keeps only the latest
upload per user and sends out its first Pokémon in `/대결` battles, or its first N (1–6), in order,
in `/대결 @상대 N` battles; a shorter upload sends what it has. When one faints the next comes in; the only other switch is a pivot move's (U-turn, Volt Switch, Flip Turn). Explosion and Self-Destruct faint their user whether they hit or not; when that takes out both sides' last members, the user's side loses. Battles never change the party.

- Base URL: the bot's `YPOKE_PUBLIC_URL`, for example `http://<bot-host>:8790`
- Auth: `Authorization: Bearer <token>`. Users get the token from `/포켓몬연결`:
  the bot DMs a button that opens `poketokenbar://ypoke-register?token=<token>&server=<base URL>`,
  and the app saves both. The DM also shows the token for pasting by hand. The channel only sees a one-line
  notice that the user got a link; the token and link stay in the DM.
  Running `/포켓몬연결` again issues a new token and revokes the old one.
- Body: JSON, UTF-8, at most 5 MiB (room for a 2,000-entry `trade_pool`).

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
      "ability": "static",
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
| `party` | array | The battle Pokémon in battle order: up to 6 chosen in the app's battle tab (older apps send 3), or the Pokémon being raised. A `/대결 … N` battle uses the first N. An upload of one is a one-member side |
| `pokemon_id` | int | PokéAPI `/pokemon/{id}` id: `1..1025`, or `10001..10999` for alternate forms |
| `level` | int | `1..100`. Battles use `min(level, 50)`; moves stay what the Pokémon knows at its real level |
| `name` | string | optional display name, max 40 chars. Default: Korean species name from PokéAPI |
| `shiny` | bool | optional, default `false`. Shown as ✨ in the battle log |
| `rental` | bool | optional, default `false`. A loaner: it fights at the opponent's level, capped at 50 (both keep their own when both are rentals) and is announced as "대여 포켓몬 …" |
| `nature` | string | optional, lowercase English nature name from the app (`"adamant"`). Raises one non-HP stat 10% and lowers another 10%, main-series table. Missing, empty or unknown names are neutral and never rejected |
| `ability` | string | optional, the individual's PokéAPI ability name, lowercase with dashes (`"huge-power"`, max 40 chars). Missing or malformed names are dropped, never rejected. Battles know 28 abilities (Blaze, Torrent, Overgrow, Swarm, Intimidate, Levitate, Huge Power, Pure Power, Thick Fat, Technician, Sturdy, Adaptability, Guts, Swift Swim, Chlorophyll, Sand Rush, Drizzle, Drought, Sand Stream, Snow Warning, Static, Flame Body, Poison Point, Immunity, Limber, Insomnia, Water Veil, Supreme Overlord); any other name does nothing. A physical move counts as contact for Static, Flame Body and Poison Point (30%) |
| `held_item` | string | optional, lowercase PokéAPI item slug. Known: `leftovers` (heals 1/16 each turn), `choice-scarf` (Speed ×1.5), `choice-band` (Attack ×1.5), `choice-specs` (Sp. Atk ×1.5), the three Choice items lock into the first move, `focus-sash` (survives one KO hit from full HP), `focus-band` (10% to survive a KO hit), `life-orb` (damage ×1.3, 10% max HP recoil), `expert-belt` (super-effective ×1.2), `assault-vest` (Sp. Def ×1.5, no weather moves), `eviolite` (Def and Sp. Def ×1.5 while the species can still evolve), `rocky-helmet` (1/6 max HP to a physical attacker per hit), `sitrus-berry` (heals 1/4 once at 50% HP or less), `lum-berry` (cures a status once), `white-herb` (resets lowered stats once), `black-sludge` (Poison types heal 1/16, others lose 1/8 each turn), `shell-bell` (heals 1/8 of damage dealt), `big-root` (drain heals ×1.3), `muscle-band` / `wise-glasses` (physical / special moves ×1.1), `scope-lens` and `razor-claw` (critical stage +1), `quick-claw` (20% to move first), `bright-powder` (attackers' accuracy ×0.9), `wide-lens` (own accuracy ×1.1), `weakness-policy` (+2 Attack and Sp. Atk after a surviving super-effective hit), `flame-orb` / `toxic-orb` (burn / badly poison the holder at end of turn), `heat-rock` / `damp-rock` / `smooth-rock` / `icy-rock` (own weather lasts 8 turns), and one type-boost item per type (damage ×1.2): `charcoal` (Fire), `mystic-water`, `miracle-seed`, `magnet`, `never-melt-ice`, `black-belt`, `poison-barb`, `soft-sand`, `sharp-beak`, `twisted-spoon`, `silver-powder`, `hard-stone`, `spell-tag`, `dragon-fang`, `black-glasses`, `metal-coat`, `silk-scarf`, `fairy-feather`. `everstone` is app-only (it stops evolution) and does nothing in battle. A Mega Stone slug (`venusaurite`, `charizardite-x`, …) on a member whose `pokemon_id` is that stone's Pokémon makes it Mega Evolve before turn 1 with the Mega form's base stats, types and ability name from PokéAPI; on any other member it does nothing. The Ogerpon masks (`teal-mask`, `wellspring-mask`, `hearthflame-mask`, `cornerstone-mask`) work only on Ogerpon (`pokemon_id` 1017): it takes the mask's type (Grass plus Water, Fire or Rock; teal stays Grass), its moves do ×1.2 damage, and each time it enters it gets +1 Speed, Sp. Def, Attack or Defense (teal, wellspring, hearthflame, cornerstone). Terapagos (1024) always enters in its Terastal form; `stellar-crystal` (app-only, Terapagos only) makes it enter in the Stellar form instead and shares the once-per-battle slot with Mega Evolution (the first holder on a side in line takes it). Masks and the crystal on any other Pokémon do nothing. With a mask, Ivy Cudgel takes the mask's type. `punching-glove` makes punching moves ×1.1. The 17 plates (`flame-plate` … `pixie-plate`, no Legend Plate) make moves of their type ×1.2 on any holder; on Arceus (493) the plate also sets its type and Judgment's. The resist berries (`occa-berry` … `roseli-berry`, 18) halve the first super-effective hit of their type and are used up; `chilan-berry` halves the first Normal hit. `adamant-crystal`, `lustrous-globe` and `griseous-core` work only on Dialga (483), Palkia (484) and Giratina (487): it enters as its Origin Forme (its stats and types; Giratina gets Levitate) and its Dragon and second-type moves do ×1.2. `rusted-sword` and `rusted-shield` work only on Zacian (888) and Zamazenta (889): it enters in its Crowned form (its stats and types). `ultranecrozium-z` works only on Necrozma (800): it Ultra Bursts before turn 1 like a Mega Evolution and takes the Mega slot. A Rayquaza (384) that knows Dragon Ascent and holds no Mega Stone Mega Evolves with no stone, using the Mega slot; its Delta Stream replaces any weather with strong winds, which stop weather moves and abilities, take away Flying's weaknesses and end when it faints or leaves. Missing, empty or unknown slugs do nothing and are never rejected |
| `ivs` | object | optional. Each key optional, `0..31`, default `15` |
| `moves` | array | optional, up to 4 distinct PokéAPI move ids, each a move from `GET /v1/moves` at that level, level-up or machine (TM), an attacking egg move when `mirror_herb` is `true` (as `egg=1` lists it), or one of its `status=1` status moves (learnable as described there, egg moves included). Any other move is rejected with `400`. Missing or empty: the 4 most recently learned level-up moves |
| `mirror_herb` | bool | optional, default `false`. The individual has had a Mirror Herb used on it in the app, so its attacking egg moves count as learnable for `moves` and in its battles. The bot trusts it the way it trusts TM ownership. Anything but a boolean is rejected with `400` |
| `trade_pool` | array | optional, a top-level key beside `party`. The Pokémon the player may trade, see [Trades](#trades). Left out by older apps; a pool that fails validation is ignored and never fails the upload |

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
| `200` | `{"ok": true, "party_size": 1, "recent_battles": [...], "coworkers": [...]}`, see below; with trading on, also `"trades": {"deliveries": [...]}` (same list as `GET /v1/trades`). Older apps ignore the extra keys |
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

## `GET /v1/moves?pokemon_id=25&level=42&machine=1`

The moves a Pokémon can bring by that level: its level-up moves learned at or below `level`, oldest first, then (only
with `machine=1`, which apps that know TMs send) every move it learns by machine (TM) at any level, by move id.
Without `machine=1` the list is level-up moves only. Both come from the newest main game that has level-up moves
for it. Attacking moves only, plus the weather moves (Sunny Day, Rain Dance, Sandstorm,
Hail, Snowscape), which come with `"power": 0` and `"damage_class": "status"`. With `status=1` (apps that show
status moves send it) the battle's status moves follow, by id: every status move whose `effect` in
`data/battle/moves.json` is one of `STATUS_EFFECTS` in `ypoke/move_effects.py`. Status moves marked `inert` there
(doubles-only moves, forced switching and trapping, Z and G-Max moves) and the weather moves above are never in this
part. They also come with `"power": 0` and `"damage_class": "status"`, and
`"accuracy"` is `null` for the ones that never miss. A status move is listed when the Pokémon learns it by level-up at
or below `level`, by machine (only with `machine=1`), or as an egg move of the Pokémon or any species it evolved from
(`"source": "egg"`, `"level": 0`). A move learnable several ways is listed once, as the first of level-up, egg,
machine. Attacking moves count egg moves only with `egg=1`, which apps send for an individual that has had a Mirror
Herb used on it: its attacking egg moves, and those of every species it evolved from, then come after the level-up
moves and before the machine moves, by id, with `"source": "egg"` and `"level": 0` (a move learnable several ways is
the first of level-up, egg, machine). Egg moves and status moves are never in `default`. No other status move is offered.
Without `status=1` (or with any other value) the reply is exactly what it was before status moves; without `egg=1`, exactly
what it was before egg moves. Auth as above.

```json
{
  "ok": true,
  "moves": [
    {"id": 84, "name": "전기쇼크", "type": "electric", "power": 40,
     "damage_class": "special", "accuracy": 100, "pp": 30, "crit_rate": 0,
     "ailment": "paralysis", "ailment_chance": 10, "priority": 0,
     "drain": 0, "min_hits": 1, "max_hits": 1,
     "stat_changes": [], "stat_target": "target", "stat_chance": 0,
     "weather": null, "always_hits_in": [], "level": 1, "source": "level"}
  ],
  "default": [84]
}
```

`source` is `"level"` for a level-up move (`level` is when it is learned), `"machine"` for a TM move (`level` is `0`, usable at any level; the app offers it once the player owns the TM) or `"egg"` for an egg move (`level` is `0`; a status move with `status=1`, an attacking move with `egg=1`). Apps that predate `source` ignore it. `default` is what the bot uses when the upload sends no `moves`: the latest level-up attacking moves, never a weather, egg or machine move. `accuracy` is `null` for moves that
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

### Variable power

`power` is the listed (PokéAPI) power. These moves change it in battle by the Gen 9 rules; abilities such as
Technician then apply to the changed power. Every other move hits at its listed power.

| Move | Power in battle |
|---|---|
| Last Respects (854) | 50 + 50 per fainted teammate of the user in this battle |
| Eruption (284), Water Spout (323), Dragon Energy (820) | 150 × the user's HP share, at least 1 |
| Hex (506) | ×2 if the target has a status |
| Facade (263) | ×2 if the user is burned, poisoned or paralyzed; a burn does not halve its damage |
| Brine (362) | ×2 if the target is at half HP or less |
| Venoshock (474), Barb Barrage (839) | ×2 if the target is poisoned |
| Acrobatics (512) | ×2 if the user holds no item (used up or knocked off) |
| Weather Ball (311) | 100 and the weather's type in sun (Fire), rain (Water), sandstorm (Rock), hail or snow (Ice); 50 Normal otherwise |
| Stored Power (500), Power Trip (681) | 20 + 20 per raised stat stage of the user |
| Rage Fist (889) | 50 + 50 per hit the user took this battle (switching out keeps the count), up to 350 |
| Avalanche (419), Revenge (279) | ×2 if the target's move hurt the user earlier this turn |
| Payback (371) | ×2 if the target already moved this turn |
| Bolt Beak (754), Fishious Rend (755) | ×2 if the target has not moved yet this turn |
| Retaliate (514) | ×2 if a teammate fainted during the last turn |
| Stomping Tantrum (707), Temper Flare (915) | ×2 if the user's move last turn missed, failed or hit an immune target |
| Lash Out (808) | ×2 if one of the user's stats was lowered this turn |
| Knock Off (282) | ×1.5 if the target holds an item it can lose, and the hit takes the item for the rest of the battle (not a Mega Stone on its Pokémon, a plate on Arceus, a mask, an origin or rusted item, or the Stellar Crystal) |
| Collision Course (878), Electro Drift (879) | ×5461/4096 on a super-effective hit |
| Triple Kick (167), Triple Axel (813) | 10/20/30 and 20/40/60 on the first, second and third hit |
| Hydro Steam (876) | ×1.5 in sun instead of the Water ×0.5 |
| Solar Beam (76), Solar Blade (669) | ×0.5 in rain, sandstorm, hail or snow |

The ability Supreme Overlord multiplies its holder's moves by 1 + 0.1 per fainted teammate (at most ×1.5).

### Status moves in battle

Both sides pick moves by one rule: a player's Pokémon uses its status moves exactly as a trainer's does. Each turn the
Pokémon first uses a damaging move that surely knocks the foe out. Otherwise it tries its status moves in the order of
`STATUS_EFFECTS` and uses the first whose moment has come. Each move's handler under `ypoke/effects/` states its
moment in `wanted`. The rules every moment follows:

| Kind | Used when |
|---|---|
| Terrains, screens, side states, rooms | The state is not up, and it swings the exchange or covers the class of the foe's best move; side states once per team |
| Hazards | Once per team, below the most layers, while the foe has members left to come in |
| Stat raises | Once per time in, while the user is above the move's HP cost (half HP without one) and the raised stat helps |
| Stat drops | While the foe's stage is above −2 and the stat matters to it |
| Healing | At a third of max HP or below, when the heal outweighs the foe's best hit |
| Status conditions | Only when it would land and the condition hurts this foe |
| Guards (Protect and kin) | The user did not guard last turn, and a guarded turn gains something: the user's Wish lands, or the foe takes damage at the end of it |
| Type, ability and item changers | The change makes the foe weaker or the user stronger against this foe |
| Self-switching (Teleport, Parting Shot, Chilly Reception, Baton Pass) | The user has a teammate to switch to and is threatened; Baton Pass only with at least +2 stages in total or a Substitute, and no Curse, Leech Seed or Perish Song on it |
| Callers and copiers | The move they would use scores higher than the user's best damaging move; Metronome and Assist only when no damaging move hurts the foe; Me First only when the user moves first; Sleep Talk while asleep; Transform once, into a foe with higher total stats |

The battle never picks a move that would fail: a state already up, a target already hit, a copy of a move the user
knows. A move that changes nothing in singles is marked `inert` in `data/battle/moves.json` with the reason and is
not offered.

A Pokémon holding a Choice item or an Assault Vest, or locked into a move, never uses a status move. With none of these
moments, it attacks as before. A status move uses PP like any other move.

## Trades

Two linked coworkers swap one graduated Pokémon each. The app offers, the bot DMs the other player,
both accept in Slack, and each app picks its side up on its next sync. Nothing changes in the app until
then. Offers expire after 24 hours.

`trade_pool` (in `POST /v1/party`) lists what the player can offer: up to 2,000 entries, newest first.
The app sends every tradable Pokémon up to that cap and leaves out the Pokémon being raised, the battle
lineup, and eggs; it hides the trade and miracle buttons for anything past the cap. The bot only trades what is
in the latest pool, so an app that sends no pool can neither offer nor receive.

```json
{"id": "<individual id, max 64 chars, no |>", "pokemon_id": 93, "level": 100, "shiny": false,
 "name": "고우스트", "entry": {"...": "the app's record of the individual, at most 4 KB (the app sends at most 2,000 bytes per entry)"}}
```

The bot hands the other side's copy of `entry` back unchanged, so the receiver gets species, form, shiny, nature,
IVs and level as sent. The app leaves out of `entry` what the receiver replaces on arrival: `caughtAt`,
`originalTrainer` (the receiver sets the sender), and `profile.instanceID` (sent as `""`). It reads only
`entry.tradeHeldItem` (see deliveries), and `entry.nature` and `entry.profile.gender` to label picker options.
Entries that fail the rules above are dropped.

| Endpoint | Purpose |
|---|---|
| `GET /v1/coworkers` | `{"ok": true, "coworkers": [{"id", "name"}]}`: linked players with a pool, not the caller. `id` is an opaque handle for `POST /v1/trades`, never a Slack id |
| `POST /v1/trades` | `{"to": "<coworker id>", "give": "<individual id>"}` → `{"ok": true, "trade_id"}`. `400 {"ok": false, "error", "message"}` for `self`, `unknown_user`, `unknown_individual`, `locked` (already in an open trade), `too_many` (3 open offers). `message` is a short Korean reason to show as is |
| `GET /v1/trades` | `{"ok": true, "trades": {"deliveries": [...], "history": [...], "locked_ids": ["..."]}}`. `locked_ids` are the caller's individuals in open trades (offered, picked back, or up for a miracle trade); the app keeps their held item in place until the trade ends. The same `deliveries` and `locked_ids` ride in the `POST /v1/party` reply |
| `POST /v1/trades/ack` | `{"trade_ids": ["..."]}` → `{"ok": true}` |

A delivery is `{"trade_id", "give_id", "from_name", "receive": <pool entry>, "give_held_item"}`: remove `give_id` from your
Pokémon, add `receive`. `give_held_item` is the trade item that left with `give_id` (null for none): the app
takes exactly that one out of the game, so the item exists once. At completion the bot rewrites the item inside
both offered entries to the one in each owner's latest pool. The bot repeats a delivery on every sync until the app acknowledges it, so the app
applies each `trade_id` once and acknowledges ids it has already applied. Apply first, acknowledge after the
save; a lost acknowledgement only means the delivery comes again.

Flow: the proposer's offer reaches the target as a DM with a picker of their pool and Accept/Decline.
After the target picks and accepts, the proposer gets a confirm DM; their accept completes the trade.
Completion is refused if either Pokémon has left its owner's latest pool. Either side can decline.
A picker option reads name, sex, level, ✨ and nature; options still equal get ` #2`, ` #3`.
A picker of more than 100 Pokémon (Slack's cap) is an `external_select`: it lists 100 at a time and filters as the
player types any part of the label. Its block id is the trade or offer id.

### Miracle trades

A player puts one Pokémon from the pool up on a card in the battle channel (`YPOKE_HOME_CHANNEL`). Anyone else with
a pool presses 교환하기, picks one of theirs in a private select, and the trade completes at once: the poster agreed by
posting. The first completed pick wins; later pressers are told privately that it is gone. The finished swap is an
ordinary completed trade, so both apps receive it through `deliveries` as above.

| Endpoint | Purpose |
|---|---|
| `GET /v1/miracle` | `{"ok": true, "offer": null \| {"offer_id", "give_id", "name", "expires_at"}}`: the caller's open offer |
| `POST /v1/miracle` | `{"give": "<individual id>"}` → `{"ok": true, "offer": {...}}`. `400 {"ok": false, "error", "message"}` for `unknown_individual`, `locked`, `already_open` (one open offer per player), `post_failed` (the card could not be posted) |
| `POST /v1/miracle/cancel` | `{}` → `{"ok": true}`; `400` `none_open` |

All three answer `404 {"ok": false, "error": "unavailable"}` when the bot has no battle channel; the app hides the
feature on any 404, which also covers older bots. The offered Pokémon is in `locked_ids` while the offer is open.
An offer ends when the poster takes it down (app or the card's poster-only 내리기), when the offered Pokémon leaves
the poster's pool (raised, sent to battle), after 24 hours, or when it is traded; the card is edited to say which and
loses its buttons. A pick that is no longer in the acceptor's pool is refused privately and the offer stays open.

The app polls about every minute and re-sends the pool when it changes or every 5 minutes, so a finished
trade shows up in the app within about a minute. One app per token: a second Mac may pick up the delivery
first, and the first to acknowledge wins.

## Gyms (PvE)

Nine regions (the app's Pokédex regions, in dex order). Each has eight gyms with a gym leader, the Elite Four and
a champion, a villain organization's hideout and a hidden boss. Gym leaders field three to six Pokémon, the others
six (the champion and the hidden boss one or more besides, kept hidden), all at Lv50. A player's team
fights one trainer in one automatic battle. It is not a Slack battle: nothing is posted, no record is stored, the
stored party is never touched, and it counts toward no ranking. Badges and rewards live in the app. All the
trainers are original characters.

The Elite Four and the champion are one run of five battles in a row, the hideout one run of four (two grunts,
the admin, the boss). A loss starts the run again. The app heals the team fully between battles by sending no
`carried`; the bot still takes `carried` from older apps, which carry HP and status over. The bot keeps no run:
see [`carried` and `carry`](#a-run-carried-and-carry). The hidden boss is one battle at full HP, outside any run.
The app opens it after the champion is beaten; the bot does not check.

### `GET /v1/gyms`

Auth as above. The whole catalog; it is the same on every call and changes only when the bot is redeployed.

```json
{
  "ok": true,
  "regions": [
    {
      "id": "kanto", "name": "관동", "first": 1, "last": 151,
      "gyms": [
        {"id": "kanto-1", "kind": "gym", "index": 1, "types": ["water"], "level": 50,
         "trainer": {"name": {"ko": "…", "en": "…", "ja": "…"}, "line": {"ko": "…", "en": "…", "ja": "…"}},
         "team": [8, 117, 119], "finale": 0, "run": null}
      ],
      "elite": {
        "run": "kanto-elite", "badges_needed": 8,
        "battles": [
          {"id": "kanto-elite-1", "kind": "elite", "index": 1, "types": ["bug"], "level": 50, "trainer": {"...": "..."},
           "team": [], "finale": 0, "run": {"id": "kanto-elite", "step": 1, "steps": 5}},
          {"id": "kanto-champion", "kind": "champion", "index": 5, "types": [], "level": 50, "trainer": {"...": "..."},
           "team": [65, 130, 59, 143, 149, 145], "finale": 1, "run": {"id": "kanto-elite", "step": 5, "steps": 5}}
        ]
      },
      "hideout": {
        "run": "kanto-hideout", "org": {"name": {"ko": "…", "en": "…", "ja": "…"}, "types": ["electric", "ghost"]},
        "battles": [
          {"id": "kanto-hideout-1", "kind": "grunt", "index": 1, "types": ["electric", "ghost"], "level": 50,
           "trainer": {"...": "..."}, "team": [], "finale": 0, "run": {"id": "kanto-hideout", "step": 1, "steps": 4}}
        ]
      },
      "hidden": {"id": "kanto-hidden", "kind": "hidden", "index": 1, "types": [], "level": 50,
                 "trainer": {"...": "..."}, "team": [6, 3, 149, 145, 144, 146], "finale": 1, "run": null}
    }
  ]
}
```

| Field | Rules |
|---|---|
| `regions[].id`, `name` | Same ids as `dex.regions` above (`kanto johto hoenn sinnoh unova kalos alola galar paldea`); `name` is Korean. `first`..`last` is the National Dex range the region's species come from |
| `gyms` | Eight gyms, ids `<region>-1` … `<region>-8`. They stand alone and can be entered in any order. Send an `id` as `gym_id` |
| `elite.battles` | `<region>-elite-1` … `<region>-elite-4` (`kind` `"elite"`), then `<region>-champion` (`"champion"`): five battles, `run.step` 1..5. `badges_needed` is how many gym badges the app asks for before the run opens; the bot does not check |
| `hideout.battles` | `<region>-hideout-1` and `-2` (`"grunt"`), `-3` (`"admin"`), `-4` (`"boss"`): `run.step` 1..4. `org` is the organization's name and the types its teams lean to |
| `hidden` | One opponent, `<region>-hidden` (`kind` `"hidden"`, `run` `null`): a single battle sent with no `carried`. Older bots leave it out |
| `kind`, `index` | `gym`, `elite`, `champion`, `grunt`, `admin`, `boss` or `hidden`; `index` counts within its group |
| `types` | The trainer's type (PokéAPI type names). A gym leader has one and fields only that type, from the region's own species (`first`..`last`), with no legendary, mythical or baby Pokémon. An Elite Four member has one and fields at least three of it among six. The hideout has the organization's two; the champion none. Where a region has too few of a type, gyms swap type slots, so the same `index` can carry a different type than in older bots |
| `level` | Always 50 |
| `trainer` | An original character: `name` and `line` (one short sentence) in `ko`, `en` and `ja`. Both grunts share the organization's name and line |
| `team` | Species ids in battle order. Gyms 1–8 field 3, 3, 4, 4, 5, 5, 6 and 6; everyone else six. Species are picked around a base-stat total that rises with the gym number (gym 1 about 420, gym 8 about 520, gym 7 eased back to gym 6's 495 as the first gym of six; early gyms may field a form that could still evolve); the Elite Four sit above gym 8, grunts low, the boss high. The champion fields a fixed table: one or two of the region's legendaries, its pseudo-legendary, regional partners, exactly one Mega in the six and a legendary finale. The hidden boss fields a stronger fixed table with more legendaries and a finale of one to three; a species can come twice only as two different forms. The battle uses exactly this team, then the hidden `finale` members |
| `finale` | How many members come out after `team` has fainted, with no healing in between; their species stay hidden. `0` for everyone but the champion and the hidden boss. Older bots leave it out |
| `run` | `null` for a gym; otherwise `id` (`<region>-elite` or `<region>-hideout`), `step` and `steps` |

Trainer art is the app's own resource named by the battle `id`.

### `POST /v1/gym/battle`

Auth as above, body at most 5 MiB.

```json
{"gym_id": "kanto-3", "team": [{"pokemon_id": 25, "level": 42, "moves": [85, 87]}, {"pokemon_id": 7, "level": 30}]}
```

`gym_id` is any battle `id` from the catalog: a gym, an Elite Four member, the champion, a grunt, an admin, a boss or the hidden boss.
`team` is 1 to 6 members, in battle order, with the schema and rules of `party` in [`POST /v1/party`](#post-v1party),
moves included (the same attacking-move check, `503 pokeapi_unavailable` when PokéAPI cannot be reached to check
them). Errors name the field as `team[i]…`. The fight is the same simulation as `/대결`: Lv50 cap, one at a time in
order, the next comes in when one faints or a pivot move sends it out. A `rental` member fights at the trainer's level (50).
Each foe knows four moves picked from everything its species learns (level-up at any level and machines): the
best same-type hits first, then coverage. Field and item-stealing moves (Cut, Strength, Rock Smash, Thief, Covet)
and Facade come only when nothing else is left. The champion's and the hidden boss's moves are hand-picked, and may
include Trick Room, Stealth Rock, Yawn, Thunder Wave and Swords Dance (+2 Attack, used once each time it comes in,
above half HP). Each foe holds an item that works for it (no two alike on a team), and a
type-boost item only for its own type or its strongest move; none holds a Focus Band. A Mega Stone Mega Evolves its
holder; a Red or Blue Orb makes Groudon or Kyogre Primal Revert the same way, `ultranecrozium-z` makes Necrozma (800)
Ultra Burst the same way, and a Rayquaza that knows Dragon Ascent Mega Evolves with no stone. The Mega budget is per
team: the player gets one per battle, the champion one in its six and one in its finale, and the hidden boss has no
limit (every holder transforms as it comes in). Champion members have a nature; hidden boss members may also have an
ability and a form (Landorus' Therian Forme, the Kyurem fusions and Calyrex's riders fight as their form ids). Other
foes have no nature or ability. Their IVs rise with the trainer: 12 at gym 1 up to 21 at gym 8 (gym 7 has 18, one
below gym 6), 28 for the Elite Four, 31 for the champion and the hidden boss, 12 / 20 / 26 for grunts, the admin and
the boss.

```json
{
  "ok": true, "gym_id": "kanto-elite-2", "kind": "elite", "won": true, "turns": 2, "seed": 1894512067,
  "trainer": {"name": {"ko": "…", "en": "…", "ja": "…"}, "line": {"ko": "…", "en": "…", "ja": "…"}},
  "player_team": [
    {"pokemon_id": 25, "name": "피카츄", "level": 50, "types": ["electric"], "shiny": false, "hp": 62},
    {"pokemon_id": 7, "name": "꼬부기", "level": 50, "types": ["water"], "shiny": false, "hp": null}
  ],
  "foe_team": [
    {"pokemon_id": 27, "name": "모래두지", "level": 50, "types": ["ground"], "shiny": false, "hp": 0}
  ],
  "log": [
    {"turn": 1, "lines": [
      {"side": 0, "text": "피카츄 › 10만볼트 → 모래두지 무효"},
      {"side": 1, "text": "모래두지 › 할퀴기 → 피카츄 62%"}
    ]},
    {"turn": 2, "lines": [
      {"side": 0, "text": "피카츄 › 아이언테일 → 모래두지 💥"},
      {"side": null, "text": "💥 모래두지 쓰러짐"}
    ]}
  ],
  "events": [
    {"turn": 0, "type": "switch", "side": 0, "member": 0, "hp": 100, "status": null},
    {"turn": 0, "type": "switch", "side": 1, "member": 0, "hp": 100, "status": null},
    {"turn": 1, "type": "move", "side": 0, "member": 0, "move": "10만볼트", "move_id": 85},
    {"turn": 1, "type": "move", "side": 1, "member": 0, "move": "할퀴기", "move_id": 10},
    {"turn": 1, "type": "damage", "side": 0, "member": 0, "hp": 62},
    {"turn": 2, "type": "move", "side": 0, "member": 0, "move": "아이언테일", "move_id": 231},
    {"turn": 2, "type": "damage", "side": 1, "member": 0, "hp": 0},
    {"turn": 2, "type": "faint", "side": 1, "member": 0}
  ],
  "run": {"id": "kanto-elite", "step": 2, "steps": 5, "first": "kanto-elite-1", "next": "kanto-elite-3"},
  "carry": [{"hp": 62, "status": null}, {"hp": 100, "status": null}]
}
```

| Field | Rules |
|---|---|
| `kind`, `trainer` | The opponent's `kind` and `trainer`, as in the catalog |
| `won` | `true` when the player's team won. A turn limit counts like in Slack battles: more Pokémon left, then more HP |
| `turns`, `seed` | Turn count; the seed the battle ran with (a new one every time, so a rematch can end differently) |
| `player_team`, `foe_team` | Every member in lineup order: `pokemon_id`, `name` (the sent `name`, else the Korean species name), battle `level`, `types`, `shiny`. `hp` is the share of max HP left at the end, `0..100`: `0` fainted (a member that came in down stays `0`), `null` never sent out |
| `log` | One entry per turn, every turn, none left out. Entries before turn 1 (entry abilities, Mega Evolution) join turn 1 |
| `log[].lines[]` | The same lines the Slack battle log shows, Korean only. `side` is `0` for the player, `1` for the trainer, `null` for a line that names no side (a faint line, a weather end). A send-out line starts with `↪ `. `text` carries the rest of the Slack line without the 🔵/🔴 side marker |
| `events` | The battle in order, for the app to replay. Every event has `turn` (`0` before turn 1), `type`, `side` (`0` the player, `1` the trainer) and `member` (the index in `player_team` / `foe_team`). The `type`s: `switch` (the member comes out with `hp` and `status`; both sides' first members come out at turn `0`; a member a pivot move sent back can come out again, with the `hp` and `status` it left with), `move` (the member uses `move`, its Korean name as in `log`, and `move_id`, that move's PokéAPI id (`165` for Struggle), so an app can show the name in its own language; bots before `move_id` send `move` only; a turn it cannot act has no `move` event), `damage` (the member's HP share is now `hp`, up or down: hits, recoil, drain, burn and poison, weather, items, Stealth Rock as it comes out), `faint` (right after a `damage` to `0`), `status` (`status` is now one of `burn`, `poison`, `toxic`, `paralysis`, `sleep`, `freeze`, or `null` when it ends), `form` (the member now fights as the PokéAPI `/pokemon` id `pokemon_id`; `kind` is `mega`, `primal`, `ultra`, `terastal`, `stellar`, `origin`, `crowned-sword`, `crowned-shield` or `mask`; it comes after that member's first `switch` and before its first `move`, at turn `1` for the first members, and holds for that member for the rest of the battle, also when a pivot brings it back; a form with no id of its own, like Ogerpon's Teal Mask, sends none; bots before forms send none) and `finale` (right before the `switch` of the champion's or hidden boss's first hidden member; `side` `1`, `member` that member, `text` the announcement in `ko`, `en` and `ja`; `log` has the Korean line). Replaying every `switch` and `damage` ends at each member's `hp` in the rosters. Stat changes and weather are only in `log`. New `type`s may be added: skip one you do not know |
| `run` | `null` for a gym. Otherwise `id`, `step`, `steps`, `first` (the run's first battle id) and `next` (the battle to send after a win, `null` after a loss or on the last step) |
| `carry` | See below. `null` unless the battle was in a run, was won and has a `next` |

#### A run: `carried` and `carry`

The Elite Four run is `<region>-elite-1` … `-4`, then `<region>-champion`; a hideout run is
`<region>-hideout-1` … `-4`. The bot stores nothing between the battles. The app keeps the run and, after a win,
sends the next battle with `carried`: one entry per `team` member, in the same order.

```json
{"gym_id": "kanto-elite-3", "team": [{"pokemon_id": 25, "level": 42}, {"pokemon_id": 7, "level": 30}],
 "carried": [{"hp": 62, "status": "burn"}, null]}
```

| Field | Rules |
|---|---|
| `carried` | Optional. A list with exactly one entry per `team` member. An entry is `null` (full HP, no status) or `{"hp": 0..100, "status": null | "burn" | "poison" | "toxic" | "paralysis" | "sleep" | "freeze"}`. `hp` is the share of max HP; `0` keeps the member down for this battle. At least one member must have `hp > 0`. Only battles with a non-null `run` take it |
| `carry` | In a response: the same list shape, ready to send back as the next `carried`. A member that never got sent out keeps the state it came in with |

PP, stat stages, confusion and the progress of a toxic or sleep status (a carried toxic starts at its first tick, a carried sleep lasts one more turn) do not carry. A loss ends the run: the app starts again at `run.first` with nothing
carried. The app decides what is locked (a gym stands alone; the Elite Four run needs the gym badges
`badges_needed` asks for) and the bot does not check, nor does it check that `carried` came from the last
battle, so the app owns the run's integrity.

The wire format has room to grow: a later opponent `kind` (a coworker's ghost party) and another request field
are added next to the current ones, so a client that ignores unknown fields and unknown `kind`s keeps working.

| Status | Body |
|---|---|
| `200` | the body above |
| `400` | `{"ok": false, "error": "<reason>"}`: a missing `gym_id`, a `team` rule broken, or `carried` not a list of `team`'s length (`carried must be a list with one entry per team member (N)`), an `hp` outside 0..100, an unknown `status`, no member able to fight, or `carried` sent for a gym (`carried is only for Elite Four and hideout battles`) |
| `401` | unauthorized |
| `404` | `{"ok": false, "error": "unknown_gym"}`. Also `not_found` from a bot that predates gyms |
| `429` | `{"ok": false, "error": "rate_limited", "retry_after": 2.1}` and a `Retry-After` header: one battle per user every 3 seconds |
| `503` | `{"ok": false, "error": "pokeapi_unavailable"}` |

The first battle against a trainer fetches its foes' learnsets from PokéAPI, so allow the request a longer timeout
(10 seconds) than the others; later ones are cached.

## `GET /v1/health`

No auth. `200 {"ok": true}`.

## Client notes

- Post every few minutes and when the raised Pokémon or the entry changes. Failures (timeout, no route when
  working from home, 5xx) should be silent; the bot keeps the last party.
- Plain HTTP on a local network. Treat the token as a password: store it in the
  Keychain, never log it.
