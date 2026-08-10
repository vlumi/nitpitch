#!/usr/bin/env bash
# Build and launch the macOS app. Usage: run.sh
# Builds into a local .build-xcode dir so the product path is deterministic.
set -euo pipefail
cd "$(dirname "$0")/.."

derived=".build-xcode"
echo "Building Nitpitch-macOS..."
# Unsigned: a locally-run debug build needs no signature, and since the
# iCloud entitlement landed there is no provisioning profile for a
# command-line build to sign WITH — so signing on made this fail silently and
# leave the previous build in place, which is a genuinely confusing way to
# lose an afternoon. (iCloud sync itself needs the signed Xcode build.)
xcodebuild -project Nitpitch.xcodeproj -scheme Nitpitch-macOS -destination "platform=macOS" \
    -derivedDataPath "$derived" -configuration Debug CODE_SIGNING_ALLOWED=NO build \
    >/dev/null 2>&1 || {
    echo "build failed; re-running with full output:" >&2
    xcodebuild -project Nitpitch.xcodeproj -scheme Nitpitch-macOS -destination "platform=macOS" \
        -derivedDataPath "$derived" -configuration Debug CODE_SIGNING_ALLOWED=NO build
    exit 1
}

app="$derived/Build/Products/Debug/Nitpitch.app"
[ -d "$app" ] || { echo "error: built app not found at $app" >&2; exit 1; }

# Relaunch cleanly: quit any running instance first.
osascript -e 'quit app "Nitpitch"' 2>/dev/null || true
sleep 0.3
echo "Launching $app"
# shellcheck disable=SC2086
open "$app" ${LAUNCH_ARGS:+--args $LAUNCH_ARGS}
