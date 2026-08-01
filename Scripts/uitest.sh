#!/usr/bin/env bash
# Run the local-only iOS UI tests (XCUITest). Not part of CI — CI runs the
# package logic suite (`swift test`) and `xcodebuild build` only. Usage: uitest.sh
# Assumes the Xcode project is already generated (the Makefile handles that).
#
# These drive the UI with no live audio (the simulator has no usable mic), so
# they cover navigation, settings, and the permission-denied path — never the
# needle responding to a real note.
set -euo pipefail
cd "$(dirname "$0")/.."

# A booted simulator if there is one, else the latest available iPhone.
destination="platform=iOS Simulator,name=iPhone 17 Pro"
if ! xcrun simctl list devices available | grep -q "iPhone 17 Pro"; then
    # Fall back to whatever iPhone the host has.
    name=$(xcrun simctl list devices available | grep -oE "iPhone [0-9][^(]*" | head -1 | xargs)
    destination="platform=iOS Simulator,name=${name}"
fi

echo "Running UI tests on: ${destination}"
if command -v xcbeautify >/dev/null; then
    set -o pipefail
    xcodebuild -project Nitpitch.xcodeproj -scheme Nitpitch-iOS \
        -destination "$destination" test | xcbeautify
else
    xcodebuild -project Nitpitch.xcodeproj -scheme Nitpitch-iOS \
        -destination "$destination" test
fi
