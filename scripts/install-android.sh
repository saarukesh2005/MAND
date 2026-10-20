#!/bin/bash
# Builds the M’AND Android app and installs it on the phone connected by USB.
# Needs: USB debugging on, the phone plugged in, and "Allow USB debugging" accepted on the phone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$SDK/platform-tools/adb"

if [ -z "${JAVA_HOME:-}" ]; then
  for candidate in "$HOME"/.mand-tools/jdk-*/Contents/Home "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    [ -x "$candidate/bin/java" ] && export JAVA_HOME="$candidate" && break
  done
fi
[ -x "$ADB" ] || { echo "adb not found at $ADB. See docs/DEVELOPMENT.md."; exit 1; }

echo "→ Building the Android app…"
(cd "$ROOT/android" && ./gradlew :app:assembleDebug --console=plain -q)
APK="$(ls -t "$HOME"/.mand-build/_app/outputs/apk/debug/app-debug.apk "$ROOT"/android/app/build/outputs/apk/debug/app-debug.apk 2>/dev/null | head -1)"
[ -n "$APK" ] || { echo "Build finished but the APK wasn't found."; exit 1; }

echo "→ Looking for your phone…"
DEVICES="$("$ADB" devices | sed 1d | grep -v '^$' || true)"
if [ -z "$DEVICES" ]; then
  echo "No phone found. Plug it in with a USB cable and turn on USB debugging (docs/DEVELOPMENT.md)."; exit 1
fi
if echo "$DEVICES" | grep -q unauthorized; then
  echo "Unlock the phone and tap “Allow USB debugging”, then run this again."; exit 1
fi
"$ADB" shell getprop ro.product.model | sed 's/^/  Phone: /'
"$ADB" shell getprop ro.build.version.release | sed 's/^/  Android: /'

echo "→ Installing…"
"$ADB" install -r "$APK"
"$ADB" shell am start -n dev.mand.android/.ui.MainActivity >/dev/null
echo "✓ M’AND is installed and open on your phone."
