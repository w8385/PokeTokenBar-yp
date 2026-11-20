# YPoke bot

Slack bot for office battles between PokeTokenBar users' Pokémon, up to six each.
Slack Socket Mode, plus a small LAN HTTP server the app uploads its battle Pokémon to ([API.md](API.md)).

- `/대결 @상대` runs one automatic 1:1 battle with each side's first uploaded Pokémon; `/대결 @상대 N` (N 1–6,
  also `N:N`; `풀` is 6) sends out up to N in the order the app uploaded instead; a side with fewer sends what it has. When one faints the next comes in, and a
  side that runs out loses (PokéAPI base stats, level (a flat Lv50 cap), IVs, natures, type chart,
  level-up moves with PP, move priority, critical-hit stages, multi-hit, drain and recoil moves, burn, paralysis, poison, toxic, sleep, freeze, confusion, stat stages, five-turn weather, and every ability and held item in `data/battle/` that has a battle effect).
  The channel gets a result card: a context line ("who ran which command", since Slack shows nobody a typed slash
  command), the winner with the format (`1:1`, `3:3`, `6:6`, …) and turn count, both lineups side by side with each
  Pokémon's fate, up to three highlight lines and a "다시 붙기" button. The compact log, one line per turn, is the
  first reply in that message's thread. The bot posts it with `chat.postMessage`, so it must be a member of
  the channel; where it cannot (a DM, a private channel it is not in) the card and then the log go as two
  messages through the response URL instead. Each Pokémon uses its
  move with the highest expected damage every turn. Only win/loss is recorded. With no mention it shows
  help.
- Every slash command's result is public where it ran, headed by that context line: battles, `/전적`, `/랭킹`,
  `/도감`, and a one-line notice for `/포켓몬연결` and `/ypoke` help. Only the caller sees mistakes (bad
  arguments, no mention), a target that is not linked or has no dex yet, the help text itself, and anything with
  a token or link; those replies are ephemeral and carry no context line. A mention reply stays in the mention's
  thread (card, then the log) with the same public/private split and needs no echo line.
- "다시 붙기" reruns the same matchup and format (the same size) with the current uploads and posts in the same thread. Only the two who
  fought can press it, and in a recorded battle only the loser (others get a private notice); a practice battle
  reruns as practice, and a side with no upload goes through the pending flow below. Each card's button works once:
  the press removes it from the card, and a press that races it gets a private "이미 다시 붙었어요". The new card
  has its own button.
- When the challenger has no upload, the thread/channel also sees one line saying so; the how-to stays in the DM
  and the private reply.
- The bot logs one INFO line per slash command, mention and button (`user`, `command`, `args`), never the
  request body.
- If a side has no Pokémon uploaded yet, the challenge waits (SQLite `pending_challenges`, one per pair,
  24 hours). That side gets the "PokeTokenBar 연결" button by DM, at most once a day; the new token works
  beside any older one. The channel hears about it only when the opponent is the one missing; a challenger
  who is not ready is told privately. The first upload that makes both sides ready plays the battle once and
  posts it where it was asked for (the slash command's response URL for 30 minutes, then the channel or
  thread, then a DM to the challenger).
- Every battle takes one Pokémon per species from an uploaded party, then lets only the first holder of each item keep it
  ([API.md](API.md#lineup-rules)). When that changes who fights or what they hold, the result card says so.
- A `rental` Pokémon (the app's starter before the first hatch) fights at the opponent's level (capped at 50) and is
  announced as "대여 포켓몬 …". It counts in records like any other.
- `/대결 @YPoke [N]` or a channel message `@YPoke 대결 [N]` is a practice battle against a random team: as many
  distinct species (#1–1025, picked from the battle seed) as you send out (one, or up to N with `N`), each at the
  level of your Pokémon in the same slot. Nothing is recorded.
- `/포켓몬연결` DMs the caller a "PokeTokenBar 연결" button. It opens
  `poketokenbar://ypoke-register?token=…&server=…`, which saves the upload token and server in the app.
  The token is also in the DM for pasting by hand. Running it again rotates the token. The channel only sees
  "<user>님이 YPoke 연결 링크를 받았어요."; the link and token never leave the DM.
- Trades: the app's Friends (친구) tab or a Box detail page offers one graduated Pokémon to a linked coworker. The bot DMs them a picker of
  their own Pokémon with Accept/Decline; after they accept, the offerer confirms in a DM. Each app picks its side
  up on its next sync, once. Offers expire after 24 hours. Wire format: [API.md](API.md#trades).
- Gyms (PvE, [API.md](API.md#gyms-pve)): the app's 체육관 screen calls `GET /v1/gyms` (9 regions, each with 8 gyms,
  the Elite Four and champion, and a villain hideout; six Lv50 Pokémon per trainer, drawn from the region's own
  species by a seed made of region and trainer) and `POST /v1/gym/battle` (a team of up to 6 against one trainer, one
  automatic battle; the Elite Four and hideout runs carry HP and status in a `carried`/`carry` pair the app keeps).
  Nothing is stored or posted. The species table behind the teams is `ypoke/species.json`, made by
  `tools/generate_species.py`; the trainers' text is in `ypoke/gym_data.py`.
- `/전적 [@누구]` posts win/loss in the channel.
- `/랭킹` posts this week's top 10 (since Monday 00:00 KST) by wins, then win rate, then fewer battles.
- `/도감 [@누구]` posts the target's (default: your own) dex summary the app uploaded in the channel: owned species,
  shiny count, progress per region and the representative Pokémon with its sprite. An unlinked target, or one
  whose app has not sent a dex yet, gets one short private line.
- `/ypoke` (or `/ypoke help`, `/ypoke 도움말`) shows the help privately and posts one public line pointing at
  `/ypoke`. `/ypoke 도감 @누구` (or any command word after `/ypoke`) runs that command; an unknown word gets the
  help privately with nothing public.
- `/파티`, `/박스 [이름] [쪽]` and `/가방` show the caller, privately, their battle party, Box (25 per page, filtered
  by name) and bag with the token balance and the Slack ops still waiting for the app ([API.md](API.md#remote-ops)).
  Each reply is the app's last upload with those ops replayed and says when the app last synced at the office. A bag
  needs an app that sends `remote_ops`; an older one gets a line asking to update. `/상점`, `/트레이닝`, `/교환` and
  `/미라클` answer "곧 열려요" for now.
- The upload response carries the app's "최근 대결" and "동료" lists ([API.md](API.md)). Display names come from Slack
  `users.info` (scope `users:read`, cached an hour); without the scope the names are `null` and the app shows a generic label.
- Slack runs no slash commands in threads, so mentions cover them all and answer in the thread:
  `@YPoke 대결 @상대`, `@YPoke 대결` (practice), `@YPoke 전적 [@누구]`, `@YPoke 랭킹`,
  `@YPoke 도감 [@누구]`, `@YPoke 연결` (link by DM), `@YPoke 파티`. `@YPoke` alone shows help. A top-level mention starts a thread.

## Run locally

```bash
cd bot
uv sync
uv run pytest
cp .env.example .env   # fill in the Slack tokens
set -a; . ./.env; set +a; uv run python -m ypoke
```

Env ([.env.example](.env.example)): `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` (required),
`YPOKE_PUBLIC_URL` (how apps reach the upload server, sent in the `/포켓몬연결` link),
`YPOKE_DB` (SQLite path), `YPOKE_HTTP_HOST` (default `0.0.0.0`), `YPOKE_HTTP_PORT` (default `8790`),
`YPOKE_HOME_CHANNEL` (optional channel id: the bot joins it at startup and help links to it).

## Slack app

Created from [deploy/slack-manifest.json](deploy/slack-manifest.json); icon is
[deploy/icon.png](deploy/icon.png). Socket Mode needs an app-level token with
`connections:write`.

## Deploy to a Mac

| What | Where |
|---|---|
| Code | `~/ypoke/bot` (copy of this folder) with `.venv` from `uv sync` |
| Battle rules | `~/ypoke/data/battle` (copy of [../data/battle](../data/battle)) |
| Secrets | `~/ypoke/.env` (mode 600), from [.env.example](.env.example) |
| Data | `~/ypoke/data/ypoke.sqlite3` |
| Logs | `~/ypoke/logs/bot.log` |
| launchd | `~/Library/LaunchAgents/local.ypoke-bot.plist`, made from [deploy/ypoke-bot.plist.template](deploy/ypoke-bot.plist.template) |

Install or update:

```bash
rsync -a --delete --exclude .venv --exclude __pycache__ --exclude '*.sqlite3*' --exclude .env \
  bot/ <user>@<bot-host>:ypoke/bot/
ssh <user>@<bot-host> 'mkdir -p ~/ypoke/data/battle'
rsync -a --delete data/battle/ <user>@<bot-host>:ypoke/data/battle/
ssh <user>@<bot-host> 'bash ~/ypoke/bot/deploy/install.sh'
```

Remove everything the bot added:

```bash
ssh <user>@<bot-host> \
  'launchctl bootout gui/$(id -u)/local.ypoke-bot; rm ~/Library/LaunchAgents/local.ypoke-bot.plist; rm -rf ~/ypoke'
```

Then delete the Slack app at api.slack.com/apps if it is no longer wanted.
