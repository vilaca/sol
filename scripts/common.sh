#!/usr/bin/env bash
# Shared helpers for the scripts in this folder. Source it, don't run it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/.build/DerivedData"
SCHEME="Sol"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }

require_xcode() {
    xcodebuild -version >/dev/null 2>&1 || die "Xcode is required. Install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
}

# Regenerates Sol.xcodeproj when project.yml is newer (or the project is missing).
ensure_project() {
    require_xcode
    command -v xcodegen >/dev/null || die "xcodegen missing, run: make bootstrap"
    if [ ! -d Sol.xcodeproj ] || [ project.yml -nt Sol.xcodeproj ]; then
        xcodegen generate --quiet
    fi
}

# Reads a resolved build setting, e.g. build_setting Debug PRODUCT_BUNDLE_IDENTIFIER
build_setting() {
    xcodebuild -project Sol.xcodeproj -scheme "$SCHEME" -configuration "$1" -showBuildSettings 2>/dev/null \
        | awk -v key="$2" '$1 == key { print $3; exit }'
}

xcbeautify_or_cat() {
    if command -v xcbeautify >/dev/null; then xcbeautify; else cat; fi
}
