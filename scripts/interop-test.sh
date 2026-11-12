#!/bin/bash
# Real interoperability test: the Swift BridgeServer (Network.framework TLS) against a Kotlin client
# using Java's TLS stack (as Android does) and the shared protocol core. Uses throwaway keys only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
SERVER_PID=""
cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

if [ -z "${JAVA_HOME:-}" ]; then
  for candidate in "$HOME"/.mand-tools/jdk-*/Contents/Home "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    [ -x "$candidate/bin/java" ] && export JAVA_HOME="$candidate" && break
  done
fi
KEYTOOL="$JAVA_HOME/bin/keytool"
for name in phone other; do
  "$KEYTOOL" -genkeypair -alias "$name" -keyalg EC -groupname secp256r1 -sigalg SHA256withECDSA \
    -dname "CN=Interop $name" -validity 2 -storetype PKCS12 -keystore "$WORK/$name.p12" \
    -storepass interop -keypass interop >/dev/null 2>&1
done

echo "→ Building and starting the Swift test server…"
(cd "$ROOT/mac" && swift build --product MandInteropServer >/dev/null 2>&1)
"$ROOT/mac/.build/debug/MandInteropServer" > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do grep -q "^INVITE " "$WORK/server.log" 2>/dev/null && break; sleep 0.2; done
INVITE="$(grep -m1 '^INVITE ' "$WORK/server.log" | cut -d' ' -f2- || true)"
[ -n "$INVITE" ] || { echo "Server didn't start:"; cat "$WORK/server.log"; exit 1; }

echo "→ Running the Kotlin/JSSE client…"
cd "$ROOT/android"
MAND_INVITE="$INVITE" MAND_PHONE_P12="$WORK/phone.p12" MAND_OTHER_P12="$WORK/other.p12" \
  ./gradlew :interop:test --console=plain -q
echo "--- server log"
cat "$WORK/server.log"
echo "✓ Interop test passed"
