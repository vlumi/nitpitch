#!/usr/bin/env bash
# Guided App Store screenshot capture. Launches the demo, tells you what to
# stage, and CAPTURES for you — no ⌘S, no renaming, no file shuffling. Output
# lands canonically named at
#   <OUT>/<platform>/en/<shot>-<platform>.png
# ready for the ASC upload (Scripts/asc/screenshots.py).
#   PLATFORM=iphone|ipad|mac   (default iphone)
#   OUT=shots                  (default ./shots)
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
LANG_DIR="en"
BUNDLE="fi.misaki.nitpitch"
APP_NAME="Nitpitch"
# Clean seeded state (factory presets, no personal data touched), synthetic
# readings, and straight onto the violin grid — the first shot's screen.
DEMO_ARGS="-demo -uitest-clean -demo-open violin"

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

echo "━━━ $PLATFORM — launching demo ━━━"
case "$PLATFORM" in
    mac)
        LAUNCH_ARGS="$DEMO_ARGS" Scripts/run.sh >/dev/null
        WINDOW_ID=$(mac_window_id) || { echo "App window never appeared." >&2; exit 1; }
        mac_pin_window
        ;;
    iphone | ipad)
        # The 6.9" iPhone tier needs a Pro Max; the 13" iPad tier the big Pro.
        case "$PLATFORM" in
            iphone) device="${DEVICE:-Pro Max}" ;;
            ipad) device="${DEVICE:-13-inch}" ;;
        esac
        log=$(mktemp)
        LAUNCH_ARGS="$DEMO_ARGS" Scripts/run-ios.sh "$PLATFORM" "$device" | tee "$log"
        SIM_UDID=$(awk '/^Simulator:/ {print $2}' "$log")
        rm -f "$log"
        [ -n "$SIM_UDID" ] || { echo "Couldn't determine the simulator UDID." >&2; exit 1; }
        sleep 3  # let the launch settle before the first stage prompt
        ;;
    *) echo "PLATFORM must be iphone | ipad | mac" >&2; exit 2 ;;
esac

total=$(python3 Scripts/asc/organize-shots.py "$PLATFORM" --plain | wc -l | tr -d ' ')
i=0
while IFS=$'\t' read -r name desc; do
    i=$((i + 1))
    file="$OUT/$PLATFORM/$LANG_DIR/${name}-${PLATFORM}.png"
    echo ""
    echo "[$i/$total] $name"
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
done < <(python3 Scripts/asc/organize-shots.py "$PLATFORM" --plain)

echo ""
echo "Done. Set under $OUT/$PLATFORM/$LANG_DIR/ — upload with make asc-screenshots(-apply)."
