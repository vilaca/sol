#!/usr/bin/env bash
# Builds the Dev app ("Sol Dev"), installs it on a connected iPhone and launches it.
#
#   scripts/device.sh            # the only connected iPhone, or pick from a list
#   DEVICE_ID=<udid> scripts/device.sh
#   scripts/device.sh --test     # run the unit and UI tests on the iPhone instead
#
# First time on a new iPhone:
#   1. Put your team in Config/Signing.local.xcconfig (see the .example next to it).
#   2. Connect the iPhone by cable, unlock it and tap "Trust".
#   3. iOS 16+: Settings > Privacy & Security > Developer Mode > On (the phone restarts).
#   4. After the first install with a free Apple ID: Settings > General > VPN & Device Management > trust your profile.
# iOS 17+ devices install with `devicectl`; older ones (iOS 16) need `ios-deploy` (brew install ios-deploy).
source "$(dirname "$0")/common.sh"

pick_device() {
    if [ -n "${DEVICE_ID:-}" ]; then echo "$DEVICE_ID"; return; fi
    # Physical devices are listed before "== Simulators ==", as "Name (iOS version) (UDID)".
    local devices
    devices="$(xcrun xctrace list devices 2>/dev/null \
        | awk '/^== Devices ==/{on=1; next} /^== /{on=0} on && /\([0-9.]+\) \(/' || true)"
    [ -n "$devices" ] || die "no iPhone found. Connect it, unlock it and trust this Mac."
    if [ "$(echo "$devices" | wc -l | tr -d ' ')" = "1" ]; then
        echo "$devices" | sed -E 's/.*\(([^)]+)\)$/\1/'
        return
    fi
    echo "Connected devices:" >&2
    echo "$devices" | nl >&2
    read -r -p "Pick a number: " n
    echo "$devices" | sed -n "${n}p" | sed -E 's/.*\(([^)]+)\)$/\1/'
}

ensure_project
UDID="$(pick_device)"
[ -n "$UDID" ] || die "no device selected"
echo "Using device $UDID"

if [ "${1:-}" = "--test" ]; then
    shift
    xcodebuild test -project Sol.xcodeproj -scheme "$SCHEME" -configuration Debug \
        -destination "id=$UDID" -derivedDataPath "$DERIVED" -allowProvisioningUpdates "$@" | xcbeautify_or_cat
    exit 0
fi

xcodebuild build -project Sol.xcodeproj -scheme "$SCHEME" -configuration Debug \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" -allowProvisioningUpdates | xcbeautify_or_cat \
    || die "build failed (signing? set DEVELOPMENT_TEAM in Config/Signing.local.xcconfig)"

APP="$DERIVED/Build/Products/Debug-iphoneos/Sol.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"

if xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null 2>&1; then
    if xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1; then
        echo "Running $BUNDLE_ID on $UDID"
    else
        echo "Installed $BUNDLE_ID, but iOS refused to launch it. On the iPhone: Settings > General >"
        echo "VPN & Device Management > your Apple ID > Trust. Then open \"Sol Dev\" from the home screen."
    fi
elif command -v ios-deploy >/dev/null; then
    ios-deploy --id "$UDID" --bundle "$APP" --justlaunch
    echo "Running $BUNDLE_ID on $UDID"
else
    die "devicectl could not install (device older than iOS 17?). Run: brew install ios-deploy"
fi
