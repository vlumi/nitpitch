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

# The newest iOS runtime's iPhone 17 Pro, else the newest runtime's first
# iPhone — addressed by UDID, not name. Once several iOS runtimes are
# installed the same device name exists under each of them, and a
# `name=` destination is then AMBIGUOUS: xcodebuild reports it as "unable
# to find a device matching the provided destination specifier", which
# reads like the simulator is missing when it is merely plural.
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (-1, -1)
ios = sorted((r for r in devices if "iOS" in r), key=version, reverse=True)
for want in ("iPhone 17 Pro", "iPhone"):
    for runtime in ios:
        for d in devices[runtime]:
            if d["name"].startswith(want) and d.get("isAvailable", True):
                print(d["udid"]); sys.exit(0)
sys.exit("no available iPhone simulator")
')
destination="platform=iOS Simulator,id=${udid}"

echo "Running UI tests on: ${destination}"
if command -v xcbeautify >/dev/null; then
    set -o pipefail
    xcodebuild -project Nitpitch.xcodeproj -scheme Nitpitch-iOS \
        -destination "$destination" test | xcbeautify
else
    xcodebuild -project Nitpitch.xcodeproj -scheme Nitpitch-iOS \
        -destination "$destination" test
fi
