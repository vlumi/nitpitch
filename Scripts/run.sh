#!/usr/bin/env bash
# Build and launch the macOS app. Usage: run.sh
# Builds into a local .build-xcode dir so the product path is deterministic.
set -euo pipefail
cd "$(dirname "$0")/.."

derived=".build-xcode"
echo "Building Tuner-macOS..."
xcodebuild -project Tuner.xcodeproj -scheme Tuner-macOS -destination "platform=macOS" \
    -derivedDataPath "$derived" -configuration Debug build \
    >/dev/null 2>&1 || {
    echo "build failed; re-running with full output:" >&2
    xcodebuild -project Tuner.xcodeproj -scheme Tuner-macOS -destination "platform=macOS" \
        -derivedDataPath "$derived" -configuration Debug build
    exit 1
}

app="$derived/Build/Products/Debug/Tuner.app"
[ -d "$app" ] || { echo "error: built app not found at $app" >&2; exit 1; }

# Relaunch cleanly: quit any running instance first.
osascript -e 'quit app "Tuner"' 2>/dev/null || true
sleep 0.3
echo "Launching $app"
open "$app"
