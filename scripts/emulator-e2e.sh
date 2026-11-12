#!/bin/bash
# End-to-end test on a real Android system (the emulator) against the real Swift BridgeServer:
# installs the phone app, pairs through the mand://pair link, then checks phone details, links and
# built-in screen mirroring arrive at the Mac. Uses a throwaway Mac identity; nothing touches your
# real M’AND pairing. Needs: emulator + system image (see docs/DEVELOPMENT.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"
AVD="${MAND_AVD:-mand-e2e}"
IMAGE="system-images;android-37.0;google_apis;arm64-v8a"
PORT=47900
WORK="$(mktemp -d)"
SERVER_PID=""
EMU_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  [ -n "$EMU_PID" ] && "$ADB" -s emulator-5554 emu kill >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

if [ -z "${JAVA_HOME:-}" ]; then
  for candidate in "$HOME"/.mand-tools/jdk-*/Contents/Home; do [ -x "$candidate/bin/java" ] && export JAVA_HOME="$candidate" && break; done
fi

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; echo "--- server log"; cat "$WORK/server.log"; exit 1; }
wait_for() { # pattern, seconds
  for _ in $(seq 1 $(( $2 * 2 ))); do grep -q "$1" "$WORK/server.log" 2>/dev/null && return 0; sleep 0.5; done
  return 1
}
# Taps the first on-screen element whose text matches (case-insensitive), using the UI hierarchy.
tap_text() {
  for _ in $(seq 1 20); do
    "$ADB" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
    local xml; xml="$("$ADB" shell cat /sdcard/ui.xml 2>/dev/null || true)"
    local bounds
    bounds="$(echo "$xml" | tr '>' '\n' | grep -i "text=\"$1\"" | head -1 | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')"
    if [ -n "$bounds" ]; then
      read -r x1 y1 x2 y2 <<<"$bounds"
      "$ADB" shell input tap $(( (x1 + x2) / 2 )) $(( (y1 + y2) / 2 ))
      return 0
    fi
    sleep 1
  done
  return 1
}

echo "→ Building the phone app and the test Mac server…"
(cd "$ROOT/android" && ./gradlew :app:assembleDebug --console=plain -q)
APK="$(ls -t "$HOME"/.mand-build/_app/outputs/apk/debug/app-debug.apk "$ROOT"/android/app/build/outputs/apk/debug/app-debug.apk 2>/dev/null | head -1)"
(cd "$ROOT/mac" && swift build --product MandInteropServer >/dev/null)

echo "→ Starting the emulator…"
if ! "$SDK/cmdline-tools/latest/bin/avdmanager" list avd -c | grep -qx "$AVD"; then
  echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd -n "$AVD" -k "$IMAGE" -d pixel_7 >/dev/null
fi
"$EMULATOR" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect >"$WORK/emulator.log" 2>&1 &
EMU_PID=$!
"$ADB" wait-for-device
for _ in $(seq 1 180); do [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break; sleep 2; done
"$ADB" shell input keyevent KEYCODE_WAKEUP; "$ADB" shell wm dismiss-keyguard || true
pass "Emulator booted: Android $("$ADB" shell getprop ro.build.version.release | tr -d '\r')"

echo "→ Installing M’AND…"
"$ADB" install -r -g "$APK" >/dev/null
"$ADB" shell pm grant dev.mand.android android.permission.ACCESS_LOCAL_NETWORK 2>/dev/null || true
"$ADB" shell pm grant dev.mand.android android.permission.POST_NOTIFICATIONS 2>/dev/null || true
pass "Installed $("$ADB" shell dumpsys package dev.mand.android | grep -m1 versionName | tr -d ' \r')"

echo "→ Starting the test Mac (10.0.2.2 is this Mac, seen from the emulator)…"
MAND_HOSTS=10.0.2.2 MAND_PORT=$PORT MAND_TEST_SCREEN=1 "$ROOT/mac/.build/debug/MandInteropServer" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
wait_for "^INVITE " 20 || fail "test Mac didn't start"
INVITE="$(grep -m1 '^INVITE ' "$WORK/server.log" | cut -d' ' -f2-)"

echo "→ Pairing through the mand://pair link (as the phone's camera would open it)…"
"$ADB" shell am start -W -a android.intent.action.VIEW -d "\"$INVITE\"" dev.mand.android >/dev/null
tap_text "Pair" || fail "pair confirmation dialog didn't appear"
wait_for "^APPROVE " 30 && pass "Mac asked to approve the phone" || fail "phone never reached the Mac"
wait_for "^CONNECTED " 30 && pass "Connected: $(grep -m1 '^CONNECTED' "$WORK/server.log" | cut -d' ' -f2-)" || fail "no session"
wait_for "^INFO " 15 && pass "Phone details: $(grep -m1 '^INFO' "$WORK/server.log" | cut -d' ' -f2-)" || fail "no device.info"

echo "→ Sharing a web link from the phone…"
"$ADB" shell am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "\"Look https://example.com/mand\"" \
  -n dev.mand.android/.system.ShareActivity >/dev/null
wait_for "^LINK https://example.com/mand" 15 && pass "Link arrived on the Mac" || fail "link didn't arrive"

echo "→ Built-in screen mirroring (the Mac asked when the phone connected)…"
"$ADB" root >/dev/null 2>&1 || true; sleep 2
"$ADB" shell am start -n dev.mand.android/.screen.ScreenShareActivity >/dev/null 2>&1 || true
tap_text "Entire screen" >/dev/null 2>&1 || true   # Android 15+: choose what to share
tap_text "Start now" || tap_text "Share screen" || tap_text "Start" || fail "Android's consent prompt didn't appear"
wait_for "^SCREEN START" 20 && pass "$(grep -m1 '^SCREEN START' "$WORK/server.log")" || fail "screen.start missing"
wait_for "SCREEN FRAMES 30 " 30 && pass "$(grep 'SCREEN FRAMES' "$WORK/server.log" | tail -1)" || fail "frames didn't arrive"
grep 'SCREEN FRAMES' "$WORK/server.log" | tail -1 | grep -q "decodable=0" && fail "frames arrived but couldn't be decoded"

echo "--- server log"
cat "$WORK/server.log"
echo "✓ End-to-end test passed"
