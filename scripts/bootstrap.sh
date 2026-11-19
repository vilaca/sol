#!/usr/bin/env bash
# One-time setup: checks Xcode, installs the command-line tools the scripts use, generates Sol.xcodeproj.
source "$(dirname "$0")/common.sh"

require_xcode
command -v brew >/dev/null || die "Homebrew is required: https://brew.sh"

for tool in xcodegen xcbeautify ios-deploy; do
    command -v "$tool" >/dev/null || brew install "$tool"
done

if command -v bundle >/dev/null; then
    bundle config set --local path vendor/bundle
    bundle install
else
    echo "Ruby bundler not found; fastlane lanes (dev IPA, TestFlight, App Store) won't work until you: gem install bundler" >&2
fi

[ -f Config/Signing.local.xcconfig ] || {
    cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
    echo "Created Config/Signing.local.xcconfig: set DEVELOPMENT_TEAM and APP_BUNDLE_ID before building for a device."
}

xcodegen generate --quiet
echo "Ready. Try: make sim"
