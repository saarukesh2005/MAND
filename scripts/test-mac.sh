#!/bin/bash
# Runs the Mac tests. With Command Line Tools only (no Xcode), the Swift Testing macro plugin
# can't find its helper libraries, so we point the loader at them. /usr/bin/swift is a
# SIP-protected shim that strips DYLD_* variables, so the toolchain binary is called directly.
set -euo pipefail
cd "$(dirname "$0")/../mac"
CLT=/Library/Developer/CommandLineTools
if [ -x "$CLT/usr/bin/swift" ] && [ ! -d /Applications/Xcode.app ]; then
  DYLD_LIBRARY_PATH="$CLT/usr/lib/swift/host" exec "$CLT/usr/bin/swift" test "$@"
fi
exec swift test "$@"
