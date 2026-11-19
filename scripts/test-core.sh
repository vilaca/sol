#!/usr/bin/env bash
# Runs the SolitaireCore unit tests on the Mac (no simulator needed).
# Uses `swift test`; if SwiftPM itself is broken (seen with some Command Line Tools installs),
# falls back to building the module and the Swift Testing runner with swiftc directly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/SolitaireCore"

if swift package --package-path "$PKG" describe >/dev/null 2>&1; then
    exec swift test --package-path "$PKG" "$@"
fi

echo "swift test unavailable, falling back to swiftc" >&2
DEV_DIR="$(xcode-select -p)"
FRAMEWORKS="$DEV_DIR/Library/Developer/Frameworks"
[ -d "$FRAMEWORKS" ] || FRAMEWORKS="$DEV_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks"
PLUGINS="$DEV_DIR/usr/lib/swift/host/plugins/testing"
[ -d "$PLUGINS" ] || PLUGINS="$DEV_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing"
OUT="$ROOT/.build/core-tests"
mkdir -p "$OUT"

swiftc -emit-library -emit-module -module-name SolitaireCore -enable-testing -swift-version 6 \
    "$PKG"/Sources/SolitaireCore/*.swift \
    -o "$OUT/libSolitaireCore.dylib" -emit-module-path "$OUT/SolitaireCore.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libSolitaireCore.dylib

cat >"$OUT/main.swift" <<'EOF'
import Testing
@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }
EOF

swiftc -parse-as-library -swift-version 6 -I "$OUT" -L "$OUT" -lSolitaireCore \
    -F "$FRAMEWORKS" -framework Testing -plugin-path "$PLUGINS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS/../usr/lib" \
    -Xlinker -rpath -Xlinker "$OUT" \
    "$PKG"/Tests/SolitaireCoreTests/*.swift "$OUT/main.swift" -o "$OUT/run-tests"

exec "$OUT/run-tests" "$@"
