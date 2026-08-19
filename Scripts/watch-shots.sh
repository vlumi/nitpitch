#!/usr/bin/env bash
# Capture the site guide's WATCH shots into guide-shots/watch/, one canonical
# PNG per staged state — the wrist's version of Scripts/shoot.sh, fully
# automatic because the watch needs no in-app staging: every state below is
# reachable with launch args alone (-demo-open routes, -demo-pose readings).
#
# Builds + boots via Scripts/run-watch.sh once, then relaunches the app per
# shot with that shot's args and screenshots via simctl. Sizes are whatever
# the newest watch simulator renders (45 mm today); the guide scales images
# anyway.
#   OUT=guide-shots   (default; shots land in $OUT/watch/<name>-watch.png)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${OUT:-guide-shots}/watch"
BUNDLE="fi.misaki.nitpitch.watchkitapp"
COMMON="-demo -uitest-clean"

# name | extra launch args | seconds to settle before the shot
# The pair pose stages D on target with A 8¢ sharp — beats visible at ~4/s;
# the reading pose holds A4 2¢ sharp (settled green after ~1.5 s).
SHOTS=$(cat <<'LIST'
root|	|3
all-instruments|-demo-open all|3
reading|-demo-open violin -demo-pose 69@2|6
listening|-demo-open violin -demo-pose rest|3
pair|-demo-open violin -demo-pose 62@-2,69@8|6
settings|-demo-open settings|3
LIST
)

# First launch builds, installs and boots the simulator.
say() { printf '\033[36m▶︎ %s\033[0m\n' "$*"; }
say "Building and booting the watch simulator…"
LAUNCH_ARGS="$COMMON" Scripts/run-watch.sh > /dev/null

UDID="$(xcrun simctl list devices booted --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
print([d["udid"] for runtime, devs in devices.items()
       if "watchOS" in runtime for d in devs][0])')"

mkdir -p "$OUT"
while IFS='|' read -r name args settle; do
    [ -n "$name" ] || continue
    say "shot: ${name} (${args:-no extra args})"
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    # shellcheck disable=SC2086  # args are a flag list, meant to split
    xcrun simctl launch "$UDID" "$BUNDLE" $COMMON $args > /dev/null
    sleep "$settle"
    xcrun simctl io "$UDID" screenshot "$OUT/${name}-watch.png" > /dev/null
    echo "  → $OUT/${name}-watch.png"
done <<< "$SHOTS"

say "done — $(ls "$OUT" | wc -l | tr -d ' ') shots in $OUT/"
