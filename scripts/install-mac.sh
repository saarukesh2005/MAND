#!/bin/bash
# Installs the M’AND Mac app from the latest GitHub release.
#
# Run it with one line, no download needed:
#   curl -fsSL https://raw.githubusercontent.com/saarukesh2005/MAND/main/scripts/install-mac.sh | bash
#
# Why this exists: a browser tags everything it downloads, and macOS then refuses
# to open the app until you approve it in Privacy & Security. curl sets no such tag,
# so an app installed this way opens straight away. Apple still hasn't checked the
# app — you are choosing to trust this project — but the download is verified
# against the SHA-256 published with the release before anything is installed.
#
# Install a specific version instead of the latest:  ... | bash -s 0.6.0
set -euo pipefail

REPO="saarukesh2005/MAND"
WANTED="${1:-}"

say()  { printf '%s\n' "$*"; }
step() { printf '→ %s\n' "$*"; }
fail() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

# ---- 1. Is this Mac supported? ------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || fail "This installer only runs on a Mac."

if [ "$(uname -m)" != "arm64" ]; then
  fail "M’AND needs an Apple Silicon Mac (M1 or later). This Mac is $(uname -m)."
fi

MACOS="$(sw_vers -productVersion)"
if [ "${MACOS%%.*}" -lt 14 ]; then
  fail "M’AND needs macOS 14 or newer. This Mac is on $MACOS."
fi

# ---- 2. Which version? --------------------------------------------------------
if [ -n "$WANTED" ]; then
  VERSION="${WANTED#v}"
  TAG="v$VERSION"
else
  step "Looking up the latest version…"
  # The /releases/latest page redirects to the real tag, so the final URL names it.
  # This avoids GitHub's API rate limit.
  FINAL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$REPO/releases/latest" 2>/dev/null || true)"
  TAG="${FINAL##*/tag/}"
  [ -n "$TAG" ] && [ "$TAG" != "$FINAL" ] || fail "Couldn't reach GitHub to find the latest version. Check your internet and try again."
  VERSION="${TAG#v}"
fi
say "  Version: $VERSION"

BASE="https://github.com/$REPO/releases/download/$TAG"
ZIP="MAND-$VERSION-mac.zip"
SUMS="SHA256SUMS-$VERSION.txt"

# ---- 3. Download into a temporary folder --------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

step "Downloading $ZIP…"
curl -fsSL --retry 3 -o "$TMP/$ZIP" "$BASE/$ZIP" 2>/dev/null \
  || fail "Couldn't download $ZIP from the $TAG release. Check https://github.com/$REPO/releases"

# ---- 4. Verify it before trusting it ------------------------------------------
step "Checking the download…"
if curl -fsSL --retry 3 -o "$TMP/$SUMS" "$BASE/$SUMS" 2>/dev/null; then
  ( cd "$TMP" && grep -F "  $ZIP" "$SUMS" | shasum -a 256 -c --status - ) \
    || fail "The download does not match the checksum published with the release. Nothing was installed. Please report this."
  say "  Checksum matches the published release."
else
  say "  No checksum file in this release — skipping that check."
fi

# ---- 5. Unpack ----------------------------------------------------------------
step "Unpacking…"
mkdir -p "$TMP/open"
ditto -x -k "$TMP/$ZIP" "$TMP/open" || fail "The zip could not be unpacked."

APP="$(find "$TMP/open" -maxdepth 2 -type d -name '*.app' -print -quit)"
[ -n "$APP" ] || fail "No app was found inside $ZIP."
APP_NAME="$(basename "$APP")"

# ---- 6. Where does it go? -----------------------------------------------------
DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  say "  /Applications isn't writable, installing to $DEST instead."
fi

# ---- 7. Quit the old copy, replace it -----------------------------------------
if pgrep -x "MandMac" >/dev/null 2>&1; then
  step "Quitting the running copy…"
  osascript -e "quit app \"${APP_NAME%.app}\"" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "MandMac" >/dev/null 2>&1 || break
    sleep 0.5
  done
  pkill -x "MandMac" >/dev/null 2>&1 || true
fi

if [ -d "$DEST/$APP_NAME" ]; then
  step "Replacing the old version…"
  rm -rf "$DEST/$APP_NAME.old"
  mv "$DEST/$APP_NAME" "$DEST/$APP_NAME.old"
fi

step "Installing to $DEST…"
if ditto "$APP" "$DEST/$APP_NAME"; then
  rm -rf "$DEST/$APP_NAME.old"
else
  # Put the old one back rather than leaving the Mac with no app at all.
  [ -d "$DEST/$APP_NAME.old" ] && mv "$DEST/$APP_NAME.old" "$DEST/$APP_NAME"
  fail "Copying the app into $DEST failed. Nothing was changed."
fi

# Belt and braces: curl sets no download tag, but strip one if anything added it.
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

# ---- 8. Done ------------------------------------------------------------------
step "Opening M’AND…"
open "$DEST/$APP_NAME" 2>/dev/null || say "  Open it yourself from $DEST."

cat <<DONE

✓ M’AND $VERSION is installed in $DEST.

  The first time it runs, macOS will ask to let M’AND use your Keychain —
  that is where its security key is kept. Enter your Mac password and
  click Always Allow.

  Next: click “Pair a Phone”, then scan the QR code with the M’AND app
  on your Android phone. Both devices must be on the same Wi-Fi.
DONE
