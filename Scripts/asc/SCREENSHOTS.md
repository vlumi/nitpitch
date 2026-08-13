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
a VIOLIN, bowed pairs only — never framed as a fretted feature (ROADMAP
§ Toward 1.0). And nothing in a shot may imply audio goes anywhere: there is
no such screen, which makes this easy.

## Workflow — one command

```sh
make shots PLATFORM=iphone     # or ipad / mac; OUT=shots by default
```

It builds, then walks the shot list — relaunching the app with each shot's
own pose (`-demo -uitest-clean` plus the args printed per shot), telling you
what to stage on screen, and **capturing each shot itself** (window grab on
Mac, `simctl` on the simulators), straight to
`shots/<platform>/en/<shot>-<platform>.png`. Retake with `r`, skip with `s`.
Consecutive shots with the same args share one app session, which is what
keeps in-app staging (favorites, pins, Dark) alive across them. No ⌘S, no
renaming: `shots/` is the handoff for the ASC upload.

Before a Mac run, once: the first window grab asks for Screen Recording
permission for your terminal, and the automatic 1440×900 window resize asks
for Accessibility; grant both and re-run.

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
comma-separated for a double stop — `62,69@-1.8` is D4 true and A4 1.8¢ low,
which beats at ~2/s because that's what those frequencies do. Cents are
against A=440 equal temperament, deliberately independent of what the staged
screen sets the reference to. Without a pose, a built-in score loops through
a flat-ish open G, its octave, and the D+A pair — that's `make demo-*` for
layout judging, and what the UI tests stage against.

## Sizes

iPhone 6.9" (1320×2868, a Pro Max simulator) · iPad 13" (2064×2752) ·
Mac 1440×900 logical (2880×1800 captured on Retina; the script pins the
window). The upload (`screenshots.py`) refuses any other size before it
touches ASC.

## The shots

Capture order (what `make shots` walks — grouped by launch args so sessions
are shared; the STORE order differs, see below). Same set on every platform.
`organize-shots.py <platform> --list` prints this with each shot's exact args.

1. **grid** — `-demo-open violin -demo-pose 62,69@-1.8`: the violin grid,
   D and A genuinely sounding together — D's dial true, A's a hair low, the
   interval lane beating steadily at ~2/s. The thesis shot: choosing an
   instrument means something, and double stops are read as the beats a
   violinist already listens for.
2. **grid-dark** — same session: flip the in-app Appearance to Dark, capture,
   flip back. The one dark-mode taster.
3. **reference** — same session: open the tuning menu, step the reference to
   A=442, temperament on Pure. The orchestra story: your section's A, and
   fifths tuned the way string players tune them.
4. **string-view** — `-demo-open violin -demo-pose 69@2`: tap the A string's
   dial — the single-string view holding 2¢ sharp, the strobe band visibly
   crawling. The precision shot: sub-cent error as motion.
5. **launch** — `-demo-pose 69@-3`: the chromatic tuner over the instrument
   rack, A4 reading 3¢ flat. Stage first: star the violin and a guitar in
   the chooser, pin Drop D on the guitar so a preset chip shows under the
   row. Home, with the app's breadth visible.
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
