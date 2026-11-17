#!/bin/bash
# One-time setup of the fork release signing key. No Keychain and no GUI: the key lives in ~/.config/ptb-signing
# (mode 600) and is read by scripts/sign-with-key.sh. Never commit it. Losing it means every user is prompted once more.
# Also installs the pinned rcodesign binary (sha256-checked) next to it.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_DIR="${PTB_SIGN_DIR:-$HOME/.config/ptb-signing}"
RCODESIGN_VERSION="0.29.0"
TARBALL="apple-codesign-$RCODESIGN_VERSION-aarch64-apple-darwin.tar.gz"
TARBALL_SHA256="d1a532150adaf90048260d76359261aa716abafc45c53c5dc18845029184334a"
URL="https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign/$RCODESIGN_VERSION/$TARBALL"

[[ "$(uname -m)" == "arm64" ]] || { echo "the pinned rcodesign build is arm64 only" >&2; exit 1; }
mkdir -p "$SIGN_DIR/bin"
chmod 700 "$SIGN_DIR"

if [[ -e "$SIGN_DIR/key.pem" || -e "$SIGN_DIR/cert.pem" ]]; then
    echo "key or cert already exists in $SIGN_DIR; not regenerating (a new cert changes the designated requirement for every user)"
else
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    cat > "$TMP/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = PokeTokenBar Fork Release
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
    (umask 077 && /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$SIGN_DIR/key.pem" \
        -out "$SIGN_DIR/cert.pem" -days 7300 -config "$TMP/openssl.cnf" 2>/dev/null)
    chmod 600 "$SIGN_DIR/key.pem" "$SIGN_DIR/cert.pem"
    echo "created key and cert in $SIGN_DIR"
fi

if [[ ! -x "$SIGN_DIR/bin/rcodesign" ]]; then
    DL=$(mktemp -d)
    trap 'rm -rf "$DL"' EXIT
    curl -fsSL -o "$DL/$TARBALL" "$URL"
    [[ "$(shasum -a 256 "$DL/$TARBALL" | cut -d' ' -f1)" == "$TARBALL_SHA256" ]] || { echo "rcodesign download sha256 mismatch" >&2; exit 1; }
    tar -xzf "$DL/$TARBALL" -C "$DL"
    install -m 755 "$DL/${TARBALL%.tar.gz}/rcodesign" "$SIGN_DIR/bin/rcodesign"
fi

echo "certificate sha1: $(/usr/bin/openssl x509 -in "$SIGN_DIR/cert.pem" -outform der | shasum -a 1 | cut -d' ' -f1)"
./scripts/sign-with-key.sh available && echo "ready"
