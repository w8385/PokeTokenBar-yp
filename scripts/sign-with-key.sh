#!/bin/bash
# Signs an app bundle with a key file instead of a Keychain identity, so it works from sessions that cannot reach
# the login keychain. The designated requirement pins the bundle id and the certificate, so it is the same on every release.
# Usage: scripts/sign-with-key.sh available | sign <App.app>
# PTB_SIGN_DIR (default ~/.config/ptb-signing) holds key.pem, cert.pem and bin/rcodesign.
set -euo pipefail

SIGN_DIR="${PTB_SIGN_DIR:-$HOME/.config/ptb-signing}"
KEY="$SIGN_DIR/key.pem"
CERT="$SIGN_DIR/cert.pem"
RCODESIGN="$SIGN_DIR/bin/rcodesign"
RCODESIGN_SHA256="6c4623db45f1d89af439a2ce42fd65798ef56aaaa3e4ced48879be05f750aacb"

case "${1:-}" in
    available)
        [[ -r "$KEY" && -r "$CERT" && -x "$RCODESIGN" ]]
        ;;
    sign)
        APP="${2:?app bundle}"
        [[ -r "$KEY" && -r "$CERT" && -x "$RCODESIGN" ]] || { echo "signing key, cert or rcodesign missing in $SIGN_DIR" >&2; exit 1; }
        ACTUAL=$(shasum -a 256 "$RCODESIGN" | cut -d' ' -f1)
        [[ "$ACTUAL" == "$RCODESIGN_SHA256" ]] || { echo "rcodesign sha256 mismatch; refusing to sign" >&2; exit 1; }
        BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
        LEAF=$(/usr/bin/openssl x509 -in "$CERT" -outform der | shasum -a 1 | cut -d' ' -f1)
        TMP=$(mktemp -d)
        trap 'rm -rf "$TMP"' EXIT
        csreq -r="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$LEAF\"" -b "$TMP/requirement.bin"
        "$RCODESIGN" sign --pem-file "$KEY" --pem-file "$CERT" --code-requirements-file "$TMP/requirement.bin" \
            --timestamp-url none "$APP"
        ;;
    *)
        echo "usage: $0 available | sign <App.app>" >&2
        exit 2
        ;;
esac
