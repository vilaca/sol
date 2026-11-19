#!/usr/bin/env bash
# Builds the Dev app, installs it on an iOS Simulator and launches it.
#
#   scripts/simulator.sh                 # iPhone 13 on the newest installed iOS runtime
#   SIM_DEVICE="iPhone SE (2nd generation)" SIM_RUNTIME=16 scripts/simulator.sh
#   scripts/simulator.sh --destination   # only print the xcodebuild destination (used by the test scripts)
#
# A simulator named "Sol - <device> - iOS <version>" is created on first use.
# Older runtimes (e.g. iOS 16, the minimum we support) come from Xcode > Settings > Components.
source "$(dirname "$0")/common.sh"

DEVICE_NAME="${SIM_DEVICE:-iPhone 13}"
RUNTIME_PREFIX="${SIM_RUNTIME:-}"

runtime_id() {
    xcrun simctl list runtimes --json | python3 -c '
import json, sys
prefix = sys.argv[1]
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r["isAvailable"] and r["platform"] == "iOS" and r["version"].startswith(prefix)]
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(runtimes[-1]["identifier"] + " " + runtimes[-1]["version"] if runtimes else "")
' "$RUNTIME_PREFIX"
}

device_type_id() {
    xcrun simctl list devicetypes --json | python3 -c '
import json, sys
name = sys.argv[1]
print(next((t["identifier"] for t in json.load(sys.stdin)["devicetypes"] if t["name"] == name), ""))
' "$DEVICE_NAME"
}

find_or_create_simulator() {
    read -r runtime version <<<"$(runtime_id)"
    [ -n "${runtime:-}" ] || die "no iOS ${RUNTIME_PREFIX:-} simulator runtime installed (Xcode > Settings > Components)"
    local name="Sol - $DEVICE_NAME - iOS $version"
    local udid
    udid="$(xcrun simctl list devices --json | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name and d["isAvailable"]:
            print(d["udid"]); sys.exit()
' "$name")"
    if [ -z "$udid" ]; then
        local type
        type="$(device_type_id)"
        [ -n "$type" ] || die "unknown simulator device type: $DEVICE_NAME (see: xcrun simctl list devicetypes)"
        udid="$(xcrun simctl create "$name" "$type" "$runtime")"
    fi
    echo "$udid"
}

require_xcode
UDID="$(find_or_create_simulator)"

if [ "${1:-}" = "--destination" ]; then
    echo "platform=iOS Simulator,id=$UDID"
    exit 0
fi

ensure_project
xcodebuild build -project Sol.xcodeproj -scheme "$SCHEME" -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" | xcbeautify_or_cat

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Sol.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"

xcrun simctl boot "$UDID" 2>/dev/null || true
# Simulator.app up to Xcode 26; Xcode 27 shows simulators in DeviceHub.app.
for viewer in "$(xcode-select -p)/Applications/Simulator.app" "$(xcode-select -p)/../Applications/DeviceHub.app"; do
    if [ -d "$viewer" ]; then
        open "$viewer" --args -CurrentDeviceUDID "$UDID" || true
        break
    fi
done
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
echo "Running $BUNDLE_ID on $DEVICE_NAME simulator ($UDID)"
