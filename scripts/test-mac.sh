#!/bin/bash
# Runs the Mac tests. With only the Command Line Tools (no Xcode), Apple's Swift Testing macro plugin
# can't find the helper libraries it was linked against, so the compiler intermittently fails with
# "plugin for module 'TestingMacros' not found". We keep a private copy of the plugin with those
# libraries linked beside it (in ~/.mand-tools, outside the project) and load it explicitly.
# Nothing in the Command Line Tools is modified. With Xcode installed, plain `swift test` is used.
set -euo pipefail
cd "$(dirname "$0")/../mac"
CLT=/Library/Developer/CommandLineTools
HOST="$CLT/usr/lib/swift/host"

if [ -d /Applications/Xcode.app ] || [ ! -f "$HOST/plugins/testing/libTestingMacros.dylib" ]; then
  exec swift test "$@"
fi

PLUGINS="$HOME/.mand-tools/swift-plugins"
PLUGIN="$PLUGINS/testing/libTestingMacros.dylib"
if ! cmp -s "$HOST/plugins/testing/libTestingMacros.dylib" "$PLUGIN" 2>/dev/null; then
  rm -rf "$PLUGINS"
  mkdir -p "$PLUGINS/testing"
  cp "$HOST/plugins/testing/libTestingMacros.dylib" "$PLUGIN"
  for item in "$HOST"/libSwift*.dylib "$HOST"/XcodeDefaultTools-*; do
    [ -e "$item" ] && ln -s "$item" "$PLUGINS/"
  done
fi
exec "$CLT/usr/bin/swift" test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
