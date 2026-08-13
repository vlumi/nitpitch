# App Store screenshots — capture guide

The carousel's job: make a string player scrolling past their 50th tuner stop
at the per-string grid and think *"this one was built for me."* Lead with what
no generic tuner has — a dial per string and bowed double stops read as beats —
then show precision, then breadth. Manual capture, demo mode (synthetic
readings, seeded presets, no microphone needed).

**The copy rules apply to images too:** the interval/beat display is staged on
a VIOLIN, bowed pairs only — never framed as a fretted feature (ROADMAP
§ Toward 1.0). And nothing in a shot may imply audio goes anywhere: there is
no such screen, which makes this easy.

## Workflow — one command

```sh
make shots PLATFORM=iphone     # or ipad / mac; OUT=shots by default
```

It builds, launches the demo (`-demo -uitest-clean -demo-open violin` — clean
seeded state, synthetic readings, straight onto the violin grid), walks the
shot list — *"stage this, press ⏎"* — and **captures each shot itself** (window
grab on Mac, `simctl` on the simulators), straight to
`shots/<platform>/en/<shot>-<platform>.png`. Retake with `r`, skip with `s`.
No ⌘S, no renaming: `shots/` is the handoff for the ASC upload.

Before a Mac run, once: the first window grab asks for Screen Recording
permission for your terminal, and the automatic 1440×900 window resize asks
for Accessibility; grant both and re-run.

Manual fallback (freehand capture, then rename by capture order):
`make demo-iphone` / `make demo-mac` to just launch, shoot freely, then
`make shots-organize PLATFORM=iphone DIR=<folder>`.

## Demo isolation & staging

`-uitest-clean` routes every store to wiped ephemeral storage with no iCloud —
demo runs can't touch real data, and every launch starts identical: the
factory presets seeded (Drop D, DADGAD, Open G, Half-step down on guitar;
Drop D, Half-step down on bass), no favorites, no pins. The `launch` and
`presets` shots stage their own favorites/pins in-app during the run — the
shot descriptions say what to set up.

`-demo` feeds synthetic readings: on an instrument grid it bows the two middle
strings together (violin: D+A), drifting the beat rate, so the interval chip
is live; in the single-string view the reading drifts through the cent range,
so the strobe band wakes as it passes through ±10¢. Capture timing is part of
the stage direction on those shots.

## Sizes

iPhone 6.9" (1320×2868, a Pro Max simulator) · iPad 13" (2064×2752) ·
Mac 1440×900 logical (2880×1800 captured on Retina; the script pins the
window). The upload (`screenshots.py`) refuses any other size before it
touches ASC.

## The shots

Capture order (what `make shots` walks — dark right after `grid` because it's
the same staged screen). Same set on every platform.

1. **grid** — the violin's per-string grid, arriving staged by `-demo-open`:
   four dials, the demo bowing D+A together, the beat chip live in the
   interval lane. Capture with the pair sounding. The thesis shot: choosing
   an instrument means something, and double stops are read as the beats a
   violinist already listens for.
2. **grid-dark** — the same screen with the in-app Appearance flipped to Dark:
   the one dark-mode taster. Flip back to Light before moving on.
3. **string-view** — tap the A string's dial: the big dial with the
   fine-tuning strobe band beneath it. Wait for the demo to drift inside
   ±10¢ so the strobe is visibly awake. The precision shot — sub-cent error
   as motion.
4. **reference** — the grid's tuning menu open, reference stepped to A=442,
   temperament on Pure. The orchestra story: your section's A, and fifths
   tuned the way string players tune them.
5. **launch** — back at the root: the chromatic tuner over the instrument
   rack. Stage first: star the violin and a guitar in the chooser, pin
   Drop D on the guitar (its manage sheet) so a preset chip shows under the
   row. Home, with the app's breadth visible.
6. **presets** — "All presets…" from the launch screen: the browser with the
   seeded tunings across instruments, the instrument filter visible. The
   collection is real and yours — deletable, renameable, shareable.
7. **share** — Share Drop D from the browser: the QR + link sheet. Hand a
   tuning to a bandmate; nothing but the setup travels.

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
