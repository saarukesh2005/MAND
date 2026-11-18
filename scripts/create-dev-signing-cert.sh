#!/bin/bash
# One-time setup: creates a free, self-signed "M’AND Local Dev" code-signing certificate in your
# login keychain. Signing every build with the same identity stops macOS from re-asking for
# Keychain and Local Network permission after each rebuild. Nothing is uploaded anywhere.
# The temporary key files are deleted afterwards; the key lives only in your login keychain.
set -euo pipefail

NAME="M’AND Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# codesign needs a *valid* identity. A certificate that is imported but not trusted for code
# signing shows up as CSSMERR_TP_NOT_TRUSTED and makes codesign say "no identity found", so the
# check below is about the identity, not the certificate.
trust_it() {
    local pem="$1"
    echo "→ Trusting it for code signing. macOS will ask for your login password — that prompt is"
    echo "  this step, and nothing is uploaded anywhere."
    # User-level trust in the login keychain; no sudo and no admin certificate store.
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$pem"
}

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$NAME"; then
    echo "✓ \"$NAME\" already exists and is trusted — nothing to do."
    exit 0
fi

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "→ \"$NAME\" is already in your keychain but is not trusted for code signing."
    EXISTING="$(mktemp -d)"
    trap 'rm -rf "$EXISTING"' EXIT
    security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$EXISTING/cert.pem"
    trust_it "$EXISTING/cert.pem"
    if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$NAME"; then
        echo "✓ \"$NAME\" is now a valid signing identity."
    else
        echo "✗ Still not trusted. Builds will fall back to ad-hoc signing, which works fine —"
        echo "  macOS will just re-ask for Keychain and Local Network access after each rebuild."
        exit 1
    fi
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS="$(openssl rand -hex 16)"

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = M’AND
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -utf8 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout "pass:$PASS" 2>/dev/null

# -T lets codesign use the key without a password prompt each build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -f pkcs12
echo "✓ Created \"$NAME\" in your login keychain."
trust_it "$WORK/cert.pem"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$NAME"; then
    echo "✓ \"$NAME\" is a valid signing identity. scripts/build-mac-app.sh will use it."
else
    echo "✗ Created but not trusted. Builds will fall back to ad-hoc signing, which works fine —"
    echo "  macOS will just re-ask for Keychain and Local Network access after each rebuild."
    exit 1
fi
