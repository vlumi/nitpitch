# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**How this file is maintained:** a user-facing PR writes its own bullet under
`### Unreleased (next build)` as part of that PR. The release lane
(`make release`) only *stamps* that heading with the build number it cuts and
opens a fresh empty `Unreleased` above it — it never writes entries itself. The
`### Unreleased (next build)` heading is therefore load-bearing: the stamping
script (`Scripts/release-lib.sh`) matches it exactly, and expects its list items
to follow immediately with nothing in between.

Apple builds are identified as `version (build)`; the build number is shared
across iOS and macOS and bumped on every release so the two never diverge.

## [0.1.0] — unreleased

The first version. Not yet released: build 0 means nothing has been cut, and the
first `make release` will produce build 1.

### Unreleased (next build)

- Adding an instrument now asks how many strings — a 6-string bass or a
  9-string guitar is a choice in the + menu, not a missing feature. Uncommon
  counts follow the instrument's own tuning pattern, adding low strings
  first and switching to the high side where low would fall below what the
  app can hear (which is exactly how real 6-string basses are strung).
- 7- and 8-string guitars and the 5-string bass join the instrument list —
  common variants offered directly rather than hidden behind configuration.
  The 8-string's F#1 and the 5-string's B0 are exactly the notes the
  detector's floor was lowered for.
- Instruments can be managed anywhere: the + in the instrument list adds one
  (pick the type, name it), swipe a row on iPhone for rename / duplicate /
  delete, and on the Mac every row has a … menu with the same actions.
  Duplicate clones the whole setup — rack of guitars, one setup, cloned per
  instrument.
- Editing a setup that came from a preset now reads "T-bird (edited)" in the
  header instead of pretending you picked whatever tuning the edit happens
  to match. Picking a tuning or preset from the menu starts a fresh claim.
- The − and + around a string's target no longer shift with the note name's
  width.
- The tuning pill in the header now names the preset you're on — save or
  load "T-bird" and the pill says T-bird, not the tuning it happens to
  match. Change anything by hand and it falls back to the tuning's own name.
- The tuning menu's checkmark now means "the one you picked": load a preset
  and the check is on the preset, not also on the tuning that happens to
  hold the same notes. Rows that merely match the current setup — loading
  them would change nothing — show an equals sign instead.
- Save the current setup as a preset, under your own name for it — "Gig",
  "Bach No. 1" — from the tuning menu. A preset carries only what you chose
  at save time: the tuning alone, or the tuning with the reference pitch, so
  loading one never moves settings it doesn't hold. Saving over an existing
  name asks first; Edit presets… deletes stale ones.
- The padlock is a fixed toolbar toggle on the instrument's screens (the
  grid and the single string), orange and closed when locked. Locked
  controls simply dim; nothing pops up to explain, and tapping the lock is
  the one way back.
- Bass drop D is reachable again: the target stepper stopped one semitone
  short of D1, even though the tuning menu offered it. Targets now step down
  to B0 (a 5-string bass's low string), and the chromatic tuner hears that
  far down too.
- A string's target can be nudged right where you tune it: the − and +
  flanking the note on the single-string screen move that string's target by
  semitones. Edit a named tuning and it relabels itself Custom — the name
  follows the pitches. Locked instruments keep their targets locked too.
- Instruments are now *yours*: each remembers its own tuning and reference
  exactly as you left it, can be renamed (long-press in the list — "Guitar 2"
  becomes "Strat"), and you can add another of the same kind. The strings
  screen's header shows the tuning — Standard, Drop D, DADGAD, Open G,
  Half-step down — and switching retunes every dial.
- Each instrument also has a padlock (in the layout menu): locked, its tuning
  and reference can't be nudged — a touch on a locked control offers the
  unlock instead of silently changing anything. For the music stand, and for
  keeping an instrument pinned at A=442.
- Tap a string in the grid to get it full screen: the big dial aimed at that
  one string, hearing the instrument's whole range — a badly slipped peg
  reads "−300¢, keep going" instead of nothing. Arrows or a swipe move
  between strings; the view never follows the sound on its own.
- Pin instruments with the star in the instrument list, and they appear as
  one-tap chips on the launch screen — the violin starts pinned. Straight to
  its strings, no list in between.
- The instrument list is part of the navigation now: going back from an
  instrument's strings returns to the list, then to the tuner, instead of the
  list vanishing behind you.
- Two strings bowed at once now read on both dials, each with its own
  deviation — tuning by fifths the way violinists actually do. A string that's
  far out of tune is still found from semitones away, as before.
- The strings screen shows the overall input level at the top, like the
  chromatic tuner does — so "the app hears nothing" and "sound is coming in
  but isn't near any string" stopped looking identical.
- Each string's cell shows a signal bar above the dial: how much sound stands
  behind the reading, so a confident bow and something scraped off the room
  noise no longer look alike.
- Playing one string no longer lights other strings' dials. Each detector
  genuinely finds the played note's subharmonic — half the frequency is half
  the frequency — so the dials are now judged together and a reading that is
  an exact octave-fraction of another string's goes dark instead of showing.
- An instrument now shows a dial per string rather than a single dial: playing
  the G string moves the G dial. Each dial watches only the pitches nearest its
  own string, so it reads how far *that string* is from where it should be —
  a whole tone flat reads −200¢ instead of resolving to some other note. How
  many fit across is yours to set, from the menu on the instrument's screen.
- The app now opens on a chromatic tuner, whatever was last tuned, so checking
  a single note takes no setup. Choosing an instrument is a step into it rather
  than a setting on the tuning screen — the button below the dial opens the
  list, and the instrument's own screen follows.
- The microphone permission text and the About screen say "analyzed" rather
  than "analysed"; the app's English is US throughout.

### build 1 — 2026-08-02

- Initial project scaffold: XcodeGen spec for iOS 16+ / macOS 14+ app targets,
  the `NitpitchCore` / `NitpitchKit` package split, CI (lint, coverage-gated tests,
  both platform builds), and the four-step release lane.
- Pitch detection by the McLeod Pitch Method over vDSP — sub-cent accuracy
  across the supported range, with octave-error and clarity guards.
- Violin tuning as the primary case, with viola, cello, double bass, guitar, and
  bass guitar sharing the same detector, plus a chromatic mode.
- Adjustable reference pitch, A=390…466 in whole hertz, defaulting to A=440.
  Stepped from the header readout and applied to the reading live.
- Tuning dial: the error shows as a filled arc between a fixed needle at centre
  and one at the reading, over a logarithmic scale. Below it, eleven lights at
  ±2, 4, 8, 16, 32¢ with the centre lit when in tune. Colours shift brightness
  along with hue, so the display still reads in greyscale.
- Note names in English, German (H for B♮, B for B♭), Italian solfège, or the
  Japanese iroha names, selectable and persisted.
- Named the app **Nitpitch**, and renamed the sources, schemes, and bundle id
  (`fi.misaki.nitpitch`) from the `Tuner` placeholder to match.
