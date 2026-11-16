#!/usr/bin/env bash
#
# ci-build-slot.sh — hold one local build slot for the whole self-hosted CI job.
#
#   ci-build-slot.sh acquire   wait for a free slot, then take it
#   ci-build-slot.sh release   give the slot back; in CI also remove .build (run with `if: always()`)
#
# Same lock as the leaf build-slot.sh: /tmp/ptb-build-slots/slot<i>, a directory holding a `pid`
# file, stale when that pid is dead, PTB_BUILD_SLOTS slots (default 1). The holder pid is the
# runner's Runner.Worker, which lives exactly as long as the job. A cancelled job runs the release
# step; a killed worker leaves a dead pid that the next waiter clears.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR=${PTB_BUILD_SLOTS_DIR:-/tmp/ptb-build-slots}
SLOTS=${PTB_BUILD_SLOTS:-1}

holder_pid() {
  local p=$PPID cmd
  while [ "$p" -gt 1 ]; do
    cmd=$(ps -o command= -p "$p" 2>/dev/null || true)
    case "$cmd" in *Runner.Worker*) echo "$p"; return ;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || break
    [ -n "$p" ] || break
  done
  echo "$PPID"
}

me=$(holder_pid)

case "${1:-}" in
  acquire)
    mkdir -p "$DIR"
    waited=0
    while :; do
      for i in $(seq 1 "$SLOTS"); do
        lock="$DIR/slot$i"
        if [ -d "$lock" ]; then
          pid=$(cat "$lock/pid" 2>/dev/null || true)
          if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$lock"; fi
        fi
        if mkdir "$lock" 2>/dev/null; then
          echo "$me" > "$lock/pid"
          echo "[ci-build-slot] took slot $i for pid $me after ${waited}s"
          exit 0
        fi
      done
      [ $(( waited % 60 )) -ne 0 ] || echo "[ci-build-slot] waiting for a build slot (${waited}s)"
      sleep 15
      waited=$(( waited + 15 ))
    done
    ;;
  release)
    for i in $(seq 1 "$SLOTS"); do
      lock="$DIR/slot$i"
      if [ "$(cat "$lock/pid" 2>/dev/null || true)" = "$me" ]; then
        rm -rf "$lock"
        echo "[ci-build-slot] released slot $i"
      fi
    done
    [ -z "${GITHUB_ACTIONS:-}" ] || rm -rf .build
    ;;
  *)
    echo "usage: ci-build-slot.sh acquire|release" >&2
    exit 2
    ;;
esac
