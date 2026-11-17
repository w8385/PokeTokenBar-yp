#!/bin/bash
# Publishes a fork release with the asset and checksum the in-app updater expects.
# Usage: scripts/fork-release.sh v3.1.0 notes.md   (PTB_DRY_RUN=1 builds and checks, then stops before publishing)
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?tag, e.g. v3.1.0}"
NOTES="${2:?release notes file}"
REPO="w8385/PokeTokenBar-yp"
ASSET="PokeTokenBar-yp-arm64.zip"

[[ "$TAG" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || { echo "tag must be vMAJOR.MINOR.PATCH: $TAG" >&2; exit 1; }
VERSION="${BASH_REMATCH[1]}"

newer() {
    local i a b
    IFS=. read -ra a <<< "$1"
    IFS=. read -ra b <<< "$2"
    for i in 0 1 2; do
        (( 10#${a[i]} != 10#${b[i]} )) && { (( 10#${a[i]} > 10#${b[i]} )); return; }
    done
    return 1
}
LATEST=$(gh release view --repo "$REPO" --json tagName -q .tagName)
LATEST_BASE="${LATEST#v}"
LATEST_BASE="${LATEST_BASE%%-*}"
[[ "$LATEST_BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "cannot read the latest release tag: $LATEST" >&2; exit 1; }
newer "$VERSION" "$LATEST_BASE" || { echo "$TAG is not newer than the latest release $LATEST" >&2; exit 1; }

./scripts/xcode-pin.sh check >/dev/null
PTB_VERSION="$VERSION" PTB_NATIVE_ARCH_ONLY=1 PTB_SKIP_INSTALL=1 ./scripts/build-app.sh
PLIST=build/PokeTokenBar.app/Contents/Info.plist
for key in CFBundleShortVersionString PTBForkVersion; do
    BUILT=$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST")
    [[ "$BUILT" == "$VERSION" ]] || { echo "$key $BUILT does not match $TAG" >&2; exit 1; }
done

VERSIONED="PokeTokenBar-yp-$TAG-arm64.zip"
rm -f "build/$ASSET" "build/$ASSET.sha256" "build/$VERSIONED"
ditto -c -k --keepParent build/PokeTokenBar.app "build/$ASSET"
cp "build/$ASSET" "build/$VERSIONED"
(cd build && shasum -a 256 "$ASSET" > "$ASSET.sha256")
if [[ "${PTB_DRY_RUN:-0}" == "1" ]]; then
    echo "dry run: $TAG > $LATEST, built $VERSION; not publishing"
    exit 0
fi
gh release create "$TAG" "build/$ASSET" "build/$ASSET.sha256" "build/$VERSIONED" --repo "$REPO" \
    --title "PokeTokenBar-yp $TAG" --notes-file "$NOTES"
