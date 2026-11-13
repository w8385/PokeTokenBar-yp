# YPoke bot

Slack bot for one-on-one office battles between PokeTokenBar users' Pokémon.
Slack Socket Mode, plus a small LAN HTTP server the app uploads its battle Pokémon to ([API.md](API.md)).

- `/대결 @상대` runs one automatic one-on-one battle (PokéAPI base stats, level, IVs, type chart,
  level-up moves with PP, critical-hit stages, burn, paralysis and stat stages) and posts a turn-by-turn
  log, written like the in-game battle text, in the channel it was called from. Each Pokémon uses its
  move with the highest expected damage every turn. Only win/loss is recorded. With no mention it shows
  help.
- If a side has no Pokémon uploaded yet, the challenge waits (SQLite `pending_challenges`, one per pair,
  24 hours). That side gets the "PokeTokenBar 연결" button by DM, at most once a day; the new token works
  beside any older one. The channel hears about it only when the opponent is the one missing; a challenger
  who is not ready is told privately. The first upload that makes both sides ready plays the battle once and
  posts it where it was asked for (the slash command's response URL for 30 minutes, then the channel or
  thread, then a DM to the challenger).
- A `rental` Pokémon (the app's starter before the first hatch) fights at the opponent's level and is
  announced as "대여 포켓몬 …". It counts in records like any other.
- `/대결 @YPoke` or a channel message `@YPoke 대결` is a practice battle against a random species
  (#1–1025, picked from the battle seed) at your Pokémon's level. Nothing is recorded.
- `/포켓몬연결` DMs the caller a "PokeTokenBar 연결" button. It opens
  `poketokenbar://ypoke-register?token=…&server=…`, which saves the upload token and server in the app.
  The token is also in the DM for pasting by hand. Running it again rotates the token.
- `/전적 [@누구]` shows win/loss.
- `/랭킹` posts this week's top 10 (since Monday 00:00 KST) by wins, then win rate, then fewer battles.
- `/ypoke` shows help.
- Slack runs no slash commands in threads, so mentions cover them all and answer in the thread:
  `@YPoke 대결 @상대`, `@YPoke 대결` (practice), `@YPoke 전적 [@누구]`, `@YPoke 랭킹`,
  `@YPoke 연결` (link by DM). `@YPoke` alone shows help. A top-level mention starts a thread.

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
| Secrets | `~/ypoke/.env` (mode 600), from [.env.example](.env.example) |
| Data | `~/ypoke/data/ypoke.sqlite3` |
| Logs | `~/ypoke/logs/bot.log` |
| launchd | `~/Library/LaunchAgents/local.ypoke-bot.plist`, made from [deploy/ypoke-bot.plist.template](deploy/ypoke-bot.plist.template) |

Install or update:

```bash
rsync -a --delete --exclude .venv --exclude __pycache__ --exclude '*.sqlite3*' --exclude .env \
  bot/ <user>@<bot-host>:ypoke/bot/
ssh <user>@<bot-host> 'bash ~/ypoke/bot/deploy/install.sh'
```

Remove everything the bot added:

```bash
ssh <user>@<bot-host> \
  'launchctl bootout gui/$(id -u)/local.ypoke-bot; rm ~/Library/LaunchAgents/local.ypoke-bot.plist; rm -rf ~/ypoke'
```

Then delete the Slack app at api.slack.com/apps if it is no longer wanted.
