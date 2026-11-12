#!/bin/bash
# Run on the bot host after copying bot/ to ~/ypoke/bot. Installs or restarts the launchd agent.
set -euo pipefail
LABEL=local.ypoke-bot
ROOT="$HOME/ypoke"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UV="$(command -v uv || echo /opt/homebrew/bin/uv)"

test -f "$ROOT/.env" || { echo "missing $ROOT/.env (copy bot/.env.example)" >&2; exit 1; }
chmod 600 "$ROOT/.env"
mkdir -p "$ROOT/logs" "$ROOT/data" "$HOME/Library/LaunchAgents"
(cd "$ROOT/bot" && "$UV" sync -q --locked)
sed -e "s|__LABEL__|$LABEL|g" -e "s|__ROOT__|$ROOT|g" "$ROOT/bot/deploy/ypoke-bot.plist.template" > "$PLIST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
while launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; do sleep 1; done
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "started $LABEL"
