#!/bin/bash
# One-time setup: creates a free, self-signed "M’AND Local Dev" code-signing certificate in your
# login keychain. Signing every build with the same identity stops macOS from re-asking for
# Keychain and Local Network permission after each rebuild. Nothing is uploaded anywhere.
# The temporary key files are deleted afterwards; the key lives only in your login keychain.
set -euo pipefail

NAME="M’AND Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ \"$NAME\" already exists — nothing to do."
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
