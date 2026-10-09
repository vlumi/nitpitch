# App Store screenshots — capture guide

The carousel's job: make a string player scrolling past their 50th tuner stop
at the per-string grid and think *"this one was built for me."* Lead with what
no generic tuner has — a dial per string and bowed double stops read as beats —
then show precision, then breadth. Manual capture, demo mode.

**Every reading in every shot is real.** Under `-demo` the microphone is
swapped for a synthesized instrument at the one seam below the audio session
controller — the whole pipeline (detection, smoothing, beats, the strobe) runs
on known frequencies. `-demo-pose` pins what "plays", so each shot's launch
args ARE its staging: a dial reading 2¢ sharp is the detector genuinely
reading a 2¢-sharp string. No waiting for a drift to pass through the right
moment, and identical pixels on every retake.

**The copy rules apply to images too:** the interval/beat display is staged on
a VIOLIN, bowed pairs only — never framed as a fretted feature (AGENTS.md,
"The App Store copy constraints"). And nothing in a shot may imply audio goes
anywhere: there is no such screen, which makes this easy.

## Workflow — one command, unattended

```sh
make shots-all                 # iPhone, iPad, Mac and watch — no prompts
make shots PLATFORM=iphone AUTO=1   # one platform
make watch-shots SET=asc            # the watch's store set alone
```

Every shot names its APPEARANCE, the Light ones included: the app defaults
to `.system`, so a Mac set captured on a machine in Dark came out entirely
dark but for the deliberate twin (found the hard way — the simulators
default to Light, so iPhone and iPad hid it). A screenshot must not depend
on whose machine took it.

**Every ASC shot is fully declared in launch arguments** — `-demo-pose`
stages what SOUNDS, `-demo-stage` stages the state around it (stars, a
pin, the reference, the temperament, Dark, which sheet is open), and
`-demo-open violin:2` lands on a string's own screen. Nothing is staged
by hand, so the set is reproducible and CI-able; `organize-shots.py
<platform> --list` prints each shot's exact arguments.

Capture waits for the screen to STOP MOVING rather than sleeping a fixed
time: a dial is a live reading converging on its target, so the script
compares consecutive grabs and shoots when under 0.2% of the frame
changes — a measured threshold, not a guessed one (settled frames differ
by ~0.01%, two different screens by ~1.7%; see `Scripts/asc/frame-delta.py`). A shot that never settles is captured anyway with a warning —
that belongs in the image as evidence, not in a hang.

Interactive mode (no `AUTO=1`) remains for judging a NEW shot before it
joins the list, and for the guide set.

It builds, then walks the shot list — relaunching the app with each shot's
own pose (`-demo -uitest-clean` plus the args printed per shot), telling you
what to stage on screen, and **capturing each shot itself** (window grab on
Mac, `simctl` on the simulators), straight to
`shots/<platform>/en/<shot>-<platform>.png`. Retake with `r`, skip with `s`.
Consecutive shots with the same args share one app session, which is what
keeps in-app staging (favorites, pins, Dark) alive across them. No ⌘S, no
renaming: `shots/` is the handoff for the ASC upload.

Before a Mac run, once: the window grab needs Screen Recording permission
for your terminal and the automatic 1440×900 resize needs Accessibility
(System Settings ▸ Privacy & Security). Grant both, then QUIT AND REOPEN
the terminal — the permission is read at process launch, so an already-
running shell keeps being refused. Without it the script stops and says
which permission is missing. iPhone and iPad need no permissions.

Manual fallback (freehand capture, then rename by capture order):
`make demo-iphone` / `make demo-mac` to just launch (append the shot's pose
via `LAUNCH_ARGS`), shoot freely, then
`make shots-organize PLATFORM=iphone DIR=<folder>`.

## Demo isolation & staging

`-uitest-clean` routes every store to wiped ephemeral storage with no iCloud —
demo runs can't touch real data, and every launch starts identical: the
factory presets seeded (Drop D, DADGAD, Open G, Half-step down on guitar;
Drop D, Half-step down on bass), no favorites, no pins. The `launch` shot
stages its own favorites/pins in-app; `presets` and `share` run in the same
session, so that staging carries.

`-demo-pose` syntax (see `DemoScore.parse`): voices as `midi[@cents]`,
comma-separated for a double stop. Cents are against A=440 equal temperament,
deliberately independent of what the staged screen sets — which cuts both
ways: the violin defaults to PURE fifths, whose D target sits 1.955¢ below
equal D, so "D dead on its target" is `62@-2`, not `62`. The baked poses
below were chosen by looking at the rendered pixels, not just the arithmetic.
Without a pose, a built-in score loops through a flat-ish open G, its octave,
and the D+A pair — that's `make demo-*` for layout judging, and what the UI
tests stage against.

## The watch set

The watch app ships inside the iOS app, and its screenshots live in the
**same iOS record** as the phone's and the iPad's — one more set
(`APP_WATCH_ULTRA`), not a platform of its own. Three shots, captured off
an **Apple Watch Ultra simulator** (49 mm, 422×514, one of the sizes ASC
accepts for that set):

1. **reading** — A4 green at +2¢, the string row across the top. Tuning on
   the wrist.
2. **pair** — a double stop read as beats (4.1/s), the arc on the
   interval's error. What no phone tuner does for you hands-free.
3. **root** — the rack your phone's instruments arrive in.

`make watch-shots` takes the guide's longer set instead (idle, settings,
all-instruments — states a store carousel has no use for).

## Sizes

iPhone 6.9" (1320×2868, a Pro Max simulator) · iPad 13" (2064×2752) ·
Apple Watch Ultra (422×514, also accepts 410×502) · Mac 1440×900 logical
(2880×1800 captured on Retina; the script pins the window). The upload
(`screenshots.py`) refuses any other size before it touches ASC.

## The shots

Capture order (what `make shots` walks — grouped by launch args so sessions
are shared; the STORE order differs, see below). Same set on every platform.
`organize-shots.py <platform> --list` prints this with each shot's exact args.

1. **grid** — `-demo-open violin -demo-pose 62@-2,69@-4`: the violin grid,
   D and A genuinely sounding together — D dead on its pure target (0¢, the
   slim centred needle), A 4¢ low (green, visibly left, one amber dot lit),
   the interval lane beating at 2.0/s. One string done, one settling. The
   thesis shot: choosing an instrument means something, and double stops are
   read as the beats a violinist already listens for.
2. **grid-dark** — the same staged screen in Dark (`appearance=dark`). The
   one dark-mode taster.
3. **reference** — the same screen at A=442 on pure fifths
   (`reference=442;temperament=pure`), both worn in the FOOTER, where a
   player looks while tuning. The orchestra story: your section's A, and
   fifths tuned the way string players tune them. (The dials read honestly
   flat against the raised A — that IS the story.) The tuning menu is
   deliberately not the subject: SwiftUI's `Menu` can't be opened
   programmatically, and a shot that needs a hand breaks the unattended
   set for a control the footer already states.
4. **string-view** — `-demo-open violin -demo-pose 69@2`: tap the A string's
   dial — the single-string view holding 2¢ sharp, the strobe band awake.
   The precision shot: sub-cent error as motion.
5. **launch** — the chromatic tuner over the instrument rack, A4 green at
   −3¢, violin and guitar starred with Drop D pinned under the guitar
   (`favorites=violin,guitar;pin=guitar:drop-d` — the pin also expands its
   row, since a chip only shows on an expanded one). Home, with the app's
   breadth visible.
6. **presets** — same session: "All presets…" from the launch screen, the
   browser with the seeded tunings across instruments, the instrument filter
   visible. The collection is real and yours — deletable, renameable,
   shareable.
7. **share** — same session: Share Drop D from the browser, the QR + link
   sheet. Hand a tuning to a bandmate; nothing but the setup travels.

**Store order ≠ capture order.** In ASC, arrange the carousel by persuasion —
the first ~3 sell the app: **grid, string-view, reference**, then launch,
presets, share, grid-dark. Don't spend slot 2 on the dark twin of slot 1.
(`screenshots.py` uploads in this order automatically.)

Optional captions (add in ASC), one concrete idea each: "A dial for every
string." · "Double stops, read as beats." · "Sub-cent, shown as motion." ·
"Your orchestra's A."

## After capturing

`make asc-screenshots` (dry run) → `make asc-screenshots-apply` — replaces
each set's contents in the editable version, in store order.
