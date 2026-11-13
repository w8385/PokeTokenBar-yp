#!/bin/bash
# Publishes a fork release with the asset and checksum the in-app updater expects.
# Usage: scripts/fork-release.sh v2.5.7-yp7 notes.md
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?tag, e.g. v2.5.7-yp7}"
NOTES="${2:?release notes file}"
REPO="w8385/PokeTokenBar-yp"
ASSET="PokeTokenBar-yp-arm64.zip"

PTB_NATIVE_ARCH_ONLY=1 PTB_SKIP_INSTALL=1 ./scripts/build-app.sh
BUILT=$(/usr/libexec/PlistBuddy -c "Print :PTBForkVersion" build/PokeTokenBar.app/Contents/Info.plist)
[[ "v$BUILT" == "$TAG" ]] || { echo "PTBForkVersion $BUILT does not match $TAG; bump FORK_VERSION in build-app.sh" >&2; exit 1; }

VERSIONED="PokeTokenBar-yp-$TAG-arm64.zip"
rm -f "build/$ASSET" "build/$ASSET.sha256" "build/$VERSIONED"
ditto -c -k --keepParent build/PokeTokenBar.app "build/$ASSET"
cp "build/$ASSET" "build/$VERSIONED"
(cd build && shasum -a 256 "$ASSET" > "$ASSET.sha256")
gh release create "$TAG" "build/$ASSET" "build/$ASSET.sha256" "build/$VERSIONED" --repo "$REPO" \
    --title "PokeTokenBar-yp $TAG" --notes-file "$NOTES"
