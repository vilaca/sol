#!/usr/bin/env bash
# Runs the app's unit and UI tests on a simulator (default: iPhone 13, newest runtime).
#
#   scripts/test-app.sh
#   SIM_RUNTIME=16 scripts/test-app.sh                                   # the oldest iOS we support
#   SIM_DEVICE="iPhone 8" SIM_RUNTIME=16 scripts/test-app.sh -only-testing:SolUITests
#
# Results bundle: .build/TestResults.xcresult (open it in Xcode for screenshots and coverage).
source "$(dirname "$0")/common.sh"

ensure_project
DESTINATION="$("$ROOT/scripts/simulator.sh" --destination)"
rm -rf "$ROOT/.build/TestResults.xcresult"

xcodebuild test -project Sol.xcodeproj -scheme "$SCHEME" -configuration Debug \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
    -resultBundlePath "$ROOT/.build/TestResults.xcresult" \
    CODE_SIGNING_ALLOWED=NO "$@" | xcbeautify_or_cat
