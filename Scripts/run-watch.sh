#!/usr/bin/env bash
# Build, install, and launch the watch app in a watch simulator, in demo mode
# (the watch simulator's microphone is as silent as the iPhone's, so the
# synthesized instrument is the only way to see a reading there).
#   Usage: run-watch.sh            — demo drift score
#   LAUNCH_ARGS="-demo -demo-pose 69@2" run-watch.sh   — a pinned pose
set -euo pipefail
cd "$(dirname "$0")/.."

bundle_id="fi.misaki.nitpitch.watchkitapp"
derived=".build-xcode"

# The newest available Apple Watch simulator.
udid="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
best = None  # (runtime-sortable, udid)
for runtime, devs in d.items():
    if "watchOS" not in runtime:
        continue
    for dev in devs:
        if dev.get("isAvailable") and "Watch" in dev["name"]:
            best = max(best or ("", ""), (runtime, dev["udid"]))
print(best[1] if best else "")
')"
[ -n "$udid" ] || { echo "error: no watchOS simulator available" >&2; exit 1; }

echo "Simulator: $udid"
open -a Simulator
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

echo "Building Nitpitch-watchOS..."
xcodebuild -project Nitpitch.xcodeproj -scheme Nitpitch-watchOS \
    -destination "generic/platform=watchOS Simulator" \
    -derivedDataPath "$derived" -configuration Debug CODE_SIGNING_ALLOWED=NO build \
    >/dev/null 2>&1 || {
    echo "build failed; re-running with full output:" >&2
    xcodebuild -project Nitpitch.xcodeproj -scheme Nitpitch-watchOS \
        -destination "generic/platform=watchOS Simulator" \
        -derivedDataPath "$derived" -configuration Debug CODE_SIGNING_ALLOWED=NO build
    exit 1
}

app="$derived/Build/Products/Debug-watchsimulator/Nitpitch.app"
[ -d "$app" ] || { echo "error: built app not found at $app" >&2; exit 1; }

echo "Installing and launching $bundle_id"
xcrun simctl install "$udid" "$app"
# shellcheck disable=SC2086
xcrun simctl launch "$udid" "$bundle_id" ${LAUNCH_ARGS:--demo}
