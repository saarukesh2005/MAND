#!/bin/bash
# Builds dist/M’AND.app from the Swift package (Command Line Tools are enough; Xcode is optional).
# Signs with the stable "M’AND Local Dev" certificate if present (see create-dev-signing-cert.sh),
# otherwise ad-hoc. Usage: scripts/build-mac-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/M’AND.app"
SIGNING_IDENTITY="M’AND Local Dev"
VERSION="0.7.0"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

echo "→ Building MandMac ($CONFIG)…"
(cd "$ROOT/mac" && swift build -c "$CONFIG" --product MandMac)
BINARY="$ROOT/mac/.build/$CONFIG/MandMac"

echo "→ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/MandMac"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.mand.mac</string>
    <key>CFBundleName</key><string>M’AND</string>
    <key>CFBundleDisplayName</key><string>M’AND</string>
    <key>CFBundleExecutable</key><string>MandMac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>M’AND uses your local network to find and securely connect to your paired Android phone. Nothing is sent to the internet.</string>
    <key>NSBonjourServices</key>
    <array><string>_mand._tcp</string></array>
    <key>NSHumanReadableCopyright</key><string>M’AND</string>
</dict>
</plist>
PLIST

echo "→ Making icon…"
ICON_WORK="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK"' EXIT
swift "$ROOT/scripts/make-icon.swift" "$ICON_WORK/icon_1024.png"
ICONSET="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$ICON_WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signing…"
# A certificate is not enough: codesign needs a *valid* identity, which means the self-signed
# certificate must also be trusted for code signing. An untrusted one is reported by
# `find-identity -p codesigning` as CSSMERR_TP_NOT_TRUSTED and makes codesign say
# "no identity found", so test for the valid identity and fall back instead of failing the build.
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGNING_IDENTITY"; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"
else
    echo "  ! No valid \"$SIGNING_IDENTITY\" signing identity — using ad-hoc signing."
    echo "    The app works, but macOS may ask for Keychain/Local Network access again after"
    echo "    each rebuild. Run scripts/create-dev-signing-cert.sh once to fix that; it needs"
    echo "    your login password, because trusting a certificate is a security setting."
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "✓ Built $APP"
