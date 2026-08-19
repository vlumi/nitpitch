#!/usr/bin/env bash
# Guided App Store screenshot capture. Walks the shot list, launching the app
# with EACH SHOT'S own staged readings (-demo-pose: the demo is the real
# pipeline hearing a synthesized signal, so a pose is simply what plays),
# tells you what to stage on screen, and CAPTURES for you — no ⌘S, no
# renaming, no file shuffling. Output lands canonically named at
#   <OUT>/<platform>/en/<shot>-<platform>.png
# ready for the ASC upload (Scripts/asc/screenshots.py).
#   PLATFORM=iphone|ipad|mac   (default iphone)
#   OUT=shots                  (default ./shots)
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

capture() {  # $1 = output file
    mkdir -p "$(dirname "$1")"
    if [ "$PLATFORM" = mac ]; then
        screencapture -o -x -l"$WINDOW_ID" "$1"
    else
        # By UDID — `booted` grabs an arbitrary device with several sims open.
        xcrun simctl io "$SIM_UDID" screenshot --display=internal "$1" >/dev/null
    fi
}

# Find the app's window by PID — names are localized, PIDs aren't.
mac_window_id() {
    for _ in $(seq 1 15); do
        local pid
        pid=$(pgrep -x "$APP_NAME" | head -1)
        if [ -n "$pid" ]; then
            if id=$(swift Scripts/asc/window-id.swift "$pid" 2>/dev/null); then
                echo "$id"; return 0
            fi
        fi
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
        WINDOW_ID=$(mac_window_id) || { echo "App window never appeared." >&2; exit 1; }
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
