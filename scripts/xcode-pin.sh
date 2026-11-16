#!/usr/bin/env bash
#
# xcode-pin.sh — keep every build on the Xcode major pinned in .xcode-version.
#
#   xcode-pin.sh check    fail unless the active xcodebuild has the pinned major
#                         (release scripts and the self-hosted CI runner)
#   xcode-pin.sh select   GitHub-hosted runners: pick the newest installed Xcode with the pinned
#                         major, else the closest major, and export DEVELOPER_DIR for later steps
#
# PTB_XCODE_DIR overrides where `select` looks for Xcode_*.app (tests only).
set -euo pipefail
cd "$(dirname "$0")/.."

pin=$(cat .xcode-version 2>/dev/null || true)
if ! [[ "$pin" =~ ^[0-9]+$ ]]; then
  echo "xcode-pin.sh: .xcode-version must hold one Xcode major such as 27 (got '$pin')" >&2
  exit 1
fi

active_major() { xcodebuild -version | awk 'NR == 1 { split($2, v, "."); print v[1] }'; }

case "${1:-}" in
  check)
    got=$(active_major)
    if [ "$got" != "$pin" ]; then
      echo "xcode-pin.sh: active Xcode major is $got, .xcode-version pins $pin" >&2
      xcodebuild -version >&2
      exit 1
    fi
    xcodebuild -version
    ;;
  select)
    dir="${PTB_XCODE_DIR:-/Applications}"
    best=$(
      for app in "$dir"/Xcode_*.app; do
        v=${app##*/Xcode_}; v=${v%.app}
        [[ "$v" =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue
        d=$(( ${v%%.*} - pin )); d=${d#-}
        echo "$d $v $app"
      done | sort -k1,1n -k2,2Vr | head -1
    )
    [ -n "$best" ] || { echo "xcode-pin.sh: no Xcode_*.app under $dir" >&2; exit 1; }
    app=${best#* * }
    export DEVELOPER_DIR="$app/Contents/Developer"
    [ -z "${GITHUB_ENV:-}" ] || echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"
    xcodebuild -version
    if [ "$(active_major)" != "$pin" ]; then
      echo "::warning::no Xcode $pin on this image; using the closest ($app)"
    fi
    ;;
  *)
    echo "usage: xcode-pin.sh check|select" >&2
    exit 2
    ;;
esac
