#!/usr/bin/env bash
# App Store screenshot capture. Walks the shot list, launching the app with
# EACH SHOT'S own staged readings (-demo-pose: the demo is the real pipeline
# hearing a synthesized signal, so a pose is simply what plays) and its own
# staged STATE (-demo-stage: stars, a pin, the reference, Dark, which sheet
# is open), then CAPTURES — no ⌘S, no renaming, no file shuffling. Output
# lands canonically named at
#   <OUT>/<platform>/en/<shot>-<platform>.png
# ready for the ASC upload (Scripts/asc/screenshots.py).
#   PLATFORM=iphone|ipad|mac   (default iphone)
#   OUT=shots                  (default ./shots)
#   AUTO=1                     unattended: no prompts, settle-wait per shot
#
# AUTO is the normal way to run this (`make shots AUTO=1`, or all three
# platforms with `make shots-all`). Every ASC shot is fully expressed in
# launch arguments, so there is nothing left to stage by hand; the
# interactive mode remains for judging a NEW shot before it joins the list,
# and for the guide set, where a couple of shots still want a human eye.
# Consecutive shots with the same launch args share one app session — that's
# what keeps in-app staging (favorites, pins, Dark) alive across those shots.
# One language today (en); when the deferred localization lands, grow the loop
# donpa's shoot.sh already has.
#
# Sizes ASC accepts (checked again at upload): iPhone 6.9" 1320×2868 (a Pro
# Max simulator), iPad 13" 2064×2752, Mac 1440×900 logical — 2880×1800 as
# captured on a Retina display.
#
# Mac notes, first run only: the window grab needs Screen Recording permission
# for your terminal, and the window resize needs Accessibility (System
# Settings ▸ Privacy & Security) — macOS prompts for each.
set -euo pipefail
cd "$(dirname "$0")/.."

AUTO="${AUTO:-}"
PLATFORM="${PLATFORM:-iphone}"
OUT="${OUT:-shots}"
# Which shot list to walk: asc (the store set) or guide (nitpitch.app/guide).
SET="${SET:-asc}"
LANG_DIR="en"
BUNDLE="fi.misaki.nitpitch"
APP_NAME="Nitpitch"
MAC_APP=".build-xcode/Build/Products/Debug/Nitpitch.app"
# Every shot runs the demo (synthesized instrument, real pipeline) on clean
# seeded state (factory presets, no personal data touched); each shot's own
# -demo-open/-demo-pose args ride on top.
COMMON_ARGS="-demo -uitest-clean"

# Wait until the screen stops MOVING, then leave that frame in $1.
#
# A tuner's dial is a live reading converging on its target and the strobe
# band is an animation, so a fixed sleep captures whatever moment it lands
# on — and byte-equality never arrives, because a needle a pixel wide keeps
# twitching and the signal bar breathes. So compare consecutive grabs by
# how MUCH of the frame changed: under `tolerance` percent means the layout
# has arrived and only the live parts are alive. Gives up after `max` tries
# and captures anyway — a shot that never settles belongs in the image as
# evidence, not in a hang.
settle_capture() {  # $1 = output file
    local previous="" tries=0 max=15 tolerance=2
    local scratch; scratch="$(mktemp -d)"
    while [ "$tries" -lt "$max" ]; do
        capture "$scratch/now.png"
        if [ -n "$previous" ] && frame_delta "$previous" "$scratch/now.png" "$tolerance"; then
            mkdir -p "$(dirname "$1")"
            mv "$scratch/now.png" "$1"
            rm -rf "$scratch"
            return 0
        fi
        previous="$scratch/previous.png"
        mv "$scratch/now.png" "$previous"
        tries=$((tries + 1))
        sleep 0.4
    done
    echo "  (never settled after $max tries — capturing as-is)" >&2
    capture "$1"
    rm -rf "$scratch"
}

# True when under $3 percent of the pixels differ between $1 and $2.
frame_delta() {
    python3 - "$1" "$2" "$3" <<'PY'
import struct, sys, zlib

def rows(path):
    data = open(path, "rb").read()
    pos, width, height, raw = 8, 0, 0, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
        elif kind == b"IDAT":
            raw += body
        elif kind == b"IEND":
            break
        pos += length + 12
    return width, height, zlib.decompress(raw)

aw, ah, a = rows(sys.argv[1])
bw, bh, b = rows(sys.argv[2])
if (aw, ah) != (bw, bh):
    sys.exit(1)
# Sample every 97th byte: enough to see a layout change, cheap enough to
# run twice a second (97 is prime, so the stride never aligns with the
# row stride and sees the same column every time).
step = 97
differing = sum(1 for i in range(0, min(len(a), len(b)), step) if a[i] != b[i])
total = max(1, len(range(0, min(len(a), len(b)), step)))
sys.exit(0 if differing * 100 / total < float(sys.argv[3]) else 1)
PY
}

capture() {  # $1 = output file
    mkdir -p "$(dirname "$1")"
    if [ "$PLATFORM" = mac ]; then
        # "could not create image from window/display" means this terminal
        # has no Screen Recording permission — the one thing here nobody
        # can grant from a script. Say which permission, rather than
        # leaving a bare CoreGraphics sentence.
        if ! screencapture -o -x -l"$WINDOW_ID" "$1" 2>/dev/null; then
            echo "" >&2
            echo "Screen capture was refused. Grant your terminal Screen Recording:" >&2
            echo "  System Settings ▸ Privacy & Security ▸ Screen Recording" >&2
            echo "then quit and reopen the terminal (the permission is read at launch)." >&2
            exit 1
        fi
    else
        # By UDID — `booted` grabs an arbitrary device with several sims open.
        xcrun simctl io "$SIM_UDID" screenshot --display=internal "$1" >/dev/null
    fi
}

# Find the app's window by PID — names are localized, PIDs aren't.
# The window id of the running app — every candidate pid, not just the
# first. A previous run that hasn't finished quitting still answers
# `pgrep`, and asking only the first pid polled a dying process for fifteen
# seconds and then declared the window missing ("App window never
# appeared") while the real one sat there.
mac_window_id() {
    for _ in $(seq 1 15); do
        local pid
        for pid in $(pgrep -x "$APP_NAME"); do
            if id=$(swift Scripts/asc/window-id.swift "$pid" 2>/dev/null); then
                echo "$id"; return 0
            fi
        done
        sleep 1
    done
    return 1
}

# ASC accepts Mac shots at exactly 1440×900 (2880×1800 on Retina) — pin the
# window there rather than hoping. System Events needs Accessibility.
mac_pin_window() {
    osascript >/dev/null 2>&1 <<'EOF' || echo "  (couldn't resize — grant Accessibility and size the window to 1440×900 by hand)"
tell application "System Events" to tell (first process whose bundle identifier is "fi.misaki.nitpitch")
    set position of front window to {0, 40}
    set size of front window to {1440, 900}
end tell
EOF
}

mac_quit() {
    pgrep -xq "$APP_NAME" || return 0
    osascript -e "tell application id \"$BUNDLE\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 8); do
        pgrep -xq "$APP_NAME" || return 0
        sleep 1
    done
    killall "$APP_NAME" >/dev/null 2>&1 || true
    sleep 1
}

# (Re)launch with this shot's args. The first call builds via the run
# scripts; later calls relaunch the built product directly.
LAUNCHED=""
launch_with() {  # $1 = shot's launch args (word-split on purpose)
    local args="$COMMON_ARGS $1"
    echo "  ↻ launching: $args"
    if [ "$PLATFORM" = mac ]; then
        if [ -z "$LAUNCHED" ]; then
            # shellcheck disable=SC2086
            LAUNCH_ARGS="$args" Scripts/run.sh >/dev/null
        else
            mac_quit
            # shellcheck disable=SC2086
            open "$MAC_APP" --args $args
        fi
        WINDOW_ID=$(mac_window_id) || {
            echo "App window never appeared — is another Nitpitch still quitting?" >&2
            exit 1
        }
        mac_pin_window
    else
        if [ -z "$LAUNCHED" ]; then
            local device log
            case "$PLATFORM" in
                iphone) device="${DEVICE:-Pro Max}" ;;  # the 6.9" tier
                ipad) device="${DEVICE:-13-inch}" ;;
                *) echo "PLATFORM must be iphone | ipad | mac" >&2; exit 2 ;;
            esac
            log=$(mktemp)
            LAUNCH_ARGS="$args" Scripts/run-ios.sh "$PLATFORM" "$device" | tee "$log"
            SIM_UDID=$(awk '/^Simulator:/ {print $2}' "$log")
            rm -f "$log"
            [ -n "$SIM_UDID" ] || { echo "Couldn't find the simulator UDID." >&2; exit 1; }
        else
            xcrun simctl terminate "$SIM_UDID" "$BUNDLE" >/dev/null 2>&1 || true
            # shellcheck disable=SC2086
            xcrun simctl launch "$SIM_UDID" "$BUNDLE" $args >/dev/null
        fi
        sleep 3  # let the launch settle before the stage prompt
    fi
    LAUNCHED="$args"
}

total=$(python3 Scripts/asc/organize-shots.py "$PLATFORM" --plain --set="$SET" | wc -l | tr -d ' ')
i=0
while IFS=$'\t' read -r name shot_args desc; do
    i=$((i + 1))
    file="$OUT/$PLATFORM/$LANG_DIR/${name}-${PLATFORM}.png"
    echo ""
    echo "[$i/$total] $name"
    # Same args as the running session = same session, staging preserved.
    [ "$LAUNCHED" = "$COMMON_ARGS $shot_args" ] || launch_with "$shot_args"
    echo "  $desc"
    if [ -n "$AUTO" ]; then
        settle_capture "$file"
        echo "  saved $file"
        continue
    fi
    printf "  ⏎ capture · s skip · q quit: "
    read -r reply </dev/tty
    [ "$reply" = q ] && exit 0
    [ "$reply" = s ] && continue
    while :; do
        capture "$file"
        printf "  saved %s — ⏎ next · r retake: " "$file"
        read -r again </dev/tty
        [ "$again" = r ] || break
    done
done < <(python3 Scripts/asc/organize-shots.py "$PLATFORM" --plain --set="$SET")

echo ""
echo "Done. Set under $OUT/$PLATFORM/$LANG_DIR/ — upload with make asc-screenshots(-apply)."
