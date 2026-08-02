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
