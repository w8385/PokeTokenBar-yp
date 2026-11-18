#!/bin/bash
# Publishes a fork release with the asset and checksum the in-app updater expects.
# Usage: scripts/fork-release.sh v3.1.0 notes.md   (PTB_DRY_RUN=1 builds and checks, then stops before publishing)
#        scripts/fork-release.sh --check-only v3.0.0   (only the README asset gate against that base)
# A failed asset gate stops the release. PTB_ASSET_GATE_SKIP="<reviewed reason>" lets it through and
# prints the reason in the published notes.
set -euo pipefail
cd "$(dirname "$0")/.."

asset_gate() {
    local rc=0
    python3 scripts/release-asset-gate.py "$1" || rc=$?
    (( rc == 0 )) && return 0
    if [[ -n "${PTB_ASSET_GATE_SKIP:-}" ]]; then
        echo "asset gate failed (exit $rc) and is skipped: $PTB_ASSET_GATE_SKIP" >&2
        return 0
    fi
    echo "asset gate failed (exit $rc): redraw the screens above and commit them, point PTB_README_FRESH_DIR (and PTB_README_NOISE_DIR) at two ReadmeScreenshotTests renders of HEAD, or set PTB_ASSET_GATE_SKIP=\"<reviewed reason>\"" >&2
    return 1
}

if [[ "${1:-}" == "--check-only" ]]; then
    asset_gate "${2:?base tag, e.g. v3.0.0}"
    exit
fi

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
git rev-parse -q --verify "$LATEST^{commit}" >/dev/null || { echo "tag $LATEST is not local; git fetch --tags first" >&2; exit 1; }
asset_gate "$LATEST" || exit 1
PUBLISHED_NOTES="build/release-notes-$TAG.md"
mkdir -p build
cp "$NOTES" "$PUBLISHED_NOTES"
if [[ -n "${PTB_ASSET_GATE_SKIP:-}" ]]; then
    printf '\n> README asset gate skipped: %s\n' "$PTB_ASSET_GATE_SKIP" >> "$PUBLISHED_NOTES"
    echo "notes end with: README asset gate skipped: $PTB_ASSET_GATE_SKIP"
fi

./scripts/sign-with-key.sh available || {
    echo "no fork signing key: an ad-hoc release resets every user's Keychain 'always allow'." >&2
    echo "Run ./scripts/create-fork-signing-key.sh once (see RELEASE.md \"포크 릴리스\")." >&2
    exit 1
}

./scripts/xcode-pin.sh check >/dev/null
PTB_SIGN_WITH_KEY=1 PTB_REQUIRE_STABLE_SIGN=1 PTB_ALLOW_NATIVE_ARCH_RELEASE=1 PTB_VERSION="$VERSION" PTB_NATIVE_ARCH_ONLY=1 PTB_SKIP_INSTALL=1 ./scripts/build-app.sh
REQUIREMENT=$(codesign -dr - build/PokeTokenBar.app 2>&1)
[[ "$REQUIREMENT" == *"certificate"* && "$REQUIREMENT" != *cdhash* ]] || {
    echo "designated requirement is not certificate-based; not releasing: $REQUIREMENT" >&2
    exit 1
}
codesign --verify --deep --strict build/PokeTokenBar.app || { echo "built app fails codesign --verify; not releasing" >&2; exit 1; }
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
    --title "PokeTokenBar-yp $TAG" --notes-file "$PUBLISHED_NOTES"
