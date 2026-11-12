#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
. "$HOME/ypoke/.env"
set +a
export YPOKE_DB="${YPOKE_DB:-$HOME/ypoke/data/ypoke.sqlite3}"
exec .venv/bin/python -m ypoke
