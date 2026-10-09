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
#
# Like the phone's shoot.sh, capture waits for the screen to STOP MOVING
# rather than sleeping a fixed time — a dial is a live reading converging on
# its target. There is no appearance to stage: watchOS has no light mode.
#
# The watch has no App Store screenshot slot of its own (it ships inside the
# iOS app), so these serve nitpitch.app/guide. `make shots-all` takes them
# anyway: one command for every image the project publishes.
set -euo pipefail
cd "$(dirname "$0")/.."

# SET=asc writes the store carousel into <OUT>/watch/en/ (the layout
# screenshots.py uploads from); SET=guide writes the explanatory states
# into <OUT>/watch/ for nitpitch.app/guide.
SET="${SET:-guide}"
if [ "$SET" = asc ]; then
    OUT="${OUT:-shots}/watch/en"
else
    OUT="${OUT:-guide-shots}/watch"
fi
BUNDLE="fi.misaki.nitpitch.watchkitapp"
COMMON="-demo -uitest-clean"

# name | extra launch args | FLOOR seconds before the settle check starts
# The pair pose stages D on target with A 8¢ sharp — beats visible at ~4/s;
# the reading pose holds A4 2¢ sharp (settled green after ~1.5 s).
# The STORE set — what sells a tuner on the wrist, in carousel order:
# a string being tuned, the double stop read as beats, then the rack the
# phone's instruments arrive in. Three is plenty for a watch listing.
ASC_SHOTS=$(cat <<'LIST'
reading|-demo-open violin -demo-pose 69@2|6
pair|-demo-open violin -demo-pose 62@-2,69@8|6
root|	|3
LIST
)

# The GUIDE set — the states nitpitch.app/guide explains, including the
# ones a store carousel has no use for (an idle screen, a settings pane).
GUIDE_SHOTS=$(cat <<'LIST'
root|	|3
all-instruments|-demo-open all|3
reading|-demo-open violin -demo-pose 69@2|6
listening|-demo-open violin -demo-pose rest|3
pair|-demo-open violin -demo-pose 62@-2,69@8|6
settings|-demo-open settings|3
LIST
)

if [ "$SET" = asc ]; then SHOTS="$ASC_SHOTS"; else SHOTS="$GUIDE_SHOTS"; fi

# First launch builds, installs and boots the simulator.
say() { printf '\033[36m▶︎ %s\033[0m\n' "$*"; }
say "Building and booting the watch simulator…"
# ASC's watch screenshots are per SIZE: the Ultra (49 mm) renders at
# 422×514, one of the sizes the store accepts. The guide doesn't care —
# it scales — so it takes whatever the newest simulator is.
if [ "$SET" = asc ]; then
    DEVICE="${DEVICE:-Ultra}" LAUNCH_ARGS="$COMMON" Scripts/run-watch.sh > /dev/null
else
    LAUNCH_ARGS="$COMMON" Scripts/run-watch.sh > /dev/null
fi

UDID="$(xcrun simctl list devices booted --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
print([d["udid"] for runtime, devs in devices.items()
       if "watchOS" in runtime for d in devs][0])')"

# Capture once the screen stops changing. Same reasoning as the phone's
# shoot.sh: a dial is a live reading, so a fixed sleep catches whatever
# moment it lands on, while byte-equality never arrives (the needle keeps
# twitching) — so compare consecutive grabs and shoot when under 2% of the
# frame differs. `floor` is the shot's own minimum wait, for states that
# need a moment to even begin (a settled reading takes ~1.5 s).
settle_shot() {  # $1 = output file, $2 = floor seconds
    local previous="" tries=0 max=15
    local scratch; scratch="$(mktemp -d)"
    sleep "$2"
    while [ "$tries" -lt "$max" ]; do
        xcrun simctl io "$UDID" screenshot "$scratch/now.png" > /dev/null 2>&1
        if [ -n "$previous" ] && Scripts/asc/frame-delta.py "$previous" "$scratch/now.png" 2; then
            mv "$scratch/now.png" "$1"; rm -rf "$scratch"; return 0
        fi
        previous="$scratch/previous.png"
        mv "$scratch/now.png" "$previous"
        tries=$((tries + 1))
        sleep 0.4
    done
    echo "  (never settled — capturing as-is)" >&2
    xcrun simctl io "$UDID" screenshot "$1" > /dev/null
    rm -rf "$scratch"
}

mkdir -p "$OUT"
while IFS='|' read -r name args settle; do
    [ -n "$name" ] || continue
    say "shot: ${name} (${args:-no extra args})"
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    # shellcheck disable=SC2086  # args are a flag list, meant to split
    xcrun simctl launch "$UDID" "$BUNDLE" $COMMON $args > /dev/null
    settle_shot "$OUT/${name}-watch.png" "$settle"
    echo "  → $OUT/${name}-watch.png"
done <<< "$SHOTS"

say "done — $(ls "$OUT" | wc -l | tr -d ' ') shots in $OUT/"
