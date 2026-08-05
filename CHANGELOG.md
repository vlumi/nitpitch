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

## [0.2.0] — unreleased

The per-string version: choosing an instrument now means something — every
string gets its own dial, the detection genuinely reads them (two at once
included), and the instruments themselves become yours: named, tuned, locked,
and remembered exactly as you left them.

### Unreleased (next build)

- Mac: ← and → walk the strings in the string view — the same move as the
  on-screen arrows, without reaching for the mouse. The keys land there
  the moment the screen opens, and fall silent past the outermost string.
- The string view checks intonation, ambiently — no mode to find. Below
  the switcher sits the octave's own tuner, lit whenever the octave
  sounds (fretted 12th, fingered octave, or the natural harmonic — they
  all count), beside both captured samples and the verdict between them:
  Δ positive = octave sharp; on a guitar the saddle wants to move back.
  Each value records once its note holds steady, and the latest hold
  wins. One detector serves both notes: an open string always sounds odd
  partials while the octave sounds only even ones, so the two are told
  apart by what's missing — which is also why a phone microphone rolling
  off a low string's fundamental can't fool it. The main dial now stands
  down honestly while the octave plays (it used to misread a fretted
  12th as the open string, roughly in tune) — the open string's answer
  stays the open string's. And any reading near +1200¢ routes to the
  octave's tuner whatever engine found it: on a bass — where a 55 Hz
  fundamental spans one FFT bin and the time-domain engine carries more
  of the frames — the 12th fret used to slam the main dial to +1200,
  and the open string flickered between in-tune and full-right.
- A Mac with no microphone at all no longer crashes at launch: the audio
  engine throws an uncatchable exception the moment it's asked about input
  hardware that doesn't exist, so the app now checks for input devices
  before asking — and says so: the tuner reads "No audio input device"
  instead of sitting silent or asking you to play a note it could never
  hear — with a Retry button for when the microphone arrives. (The device
  check also stays inside the audio stack now, keeping the camera
  subsystem's entitlement complaints out of the console.)
- …and the message actually appears: the tuner sampled the audio status
  once, in a race it usually lost against activation, so a mic-less Mac
  showed a stale "Not listening" forever. It now observes the status, so
  the display follows activation whenever it finishes — including after
  Retry.
- Unplugging the microphone mid-run no longer strands the tuner: the
  windows just stopped coming, the volume bar froze at its last reading,
  and plugging back in resumed nothing. The capture now listens for the
  hardware coming and going and rebuilds itself around whatever the input
  is — unplug drops to "No audio input device" (meter cleared), replug
  picks the tuning back up on its own. Device events arrive in storms and
  on threads of the hardware layer's choosing, so they're funneled to the
  main queue and coalesced into a single rebuild once the hardware
  settles — answering each one directly crashed the app mid-replug.

### build 3 — 2026-08-04

- Instruments are deliberate now, and the factory list is real: first
  launch seeds one ordinary, fully editable instrument per catalog kind —
  browse and tune immediately, rename the violin "Guarneri", delete the
  ones you'll never touch (all of them, if you like: the list can be
  empty, and a big Add button takes their place). Nothing joins or leaves
  anything by side effect — opening an instrument is just opening it.
  Each row carries a small kind tag (Vln, Gtr, Bass…) and its current
  tuning, so which is which reads at a glance without renaming anything.
- The star is the launch screen: starred instruments form a Favorites
  section at the top of the list — drag-ordered, and that order IS the
  home screen's — while everything unstarred sits below, family-grouped
  and stable. On the launch screen the old truncating chips grew into a
  rack of full rows (kind tag, name, current tuning, padlock) that say
  what they'll open into before the tap, with "All instruments…" one row
  below; the dial stays the headline, the rack caps at four.
- Presets and tunings can be pinned to an instrument — Standard included:
  light the 📌 beside "Gig" (or Drop D) in Manage presets…, and a chip
  appears under that instrument's launch row — tap it and the instrument
  opens with that setup loaded, an explicit pick that overwrites any
  drift, while the plain row still opens it exactly as you left it. The
  pin is the (instrument, preset) pair, so pinning Gig to one guitar
  never surfaces it on another; pinned entries also float to the top of
  the tuning menu whether or not the instrument is on the launch screen,
  and on a locked instrument the chips dim and only navigate. Presets
  gained template-wide favorites of their own (the ★ floats them into a
  Favorites block atop every preset list), and Manage presets… is always
  in the tuning menu — it's where the pins live.
- Adding an instrument is one sheet: pick the kind from the + menu (one
  entry per kind, grouped by family) and everything else — the name,
  ready to edit, and the strings — is decided together, with Create the
  moment anything comes to exist and Cancel leaving no trace. Kinds that
  come in sizes offer their common counts as one-tap chips (double bass
  4/5, guitar 6/7/8, bass 4/5/6 — violins offer nothing, being violins),
  the full string list waits behind a disclosure (always visible on the
  Mac, whose sheet fits its content exactly), and nothing is ever
  labelled "custom" — touch the list and the chips simply stop matching.
  Duplicate opens the same sheet prefilled from the source: name
  suggested, strings and reference copied, everything editable.
- The instrument's own screen manages the instrument: an … menu carries
  Rename, Duplicate, Edit strings and Delete alongside the column picker —
  the chooser's swipe and long-press have the same actions for those who
  find them, but the … is findable by everyone. The string list itself is
  editable everywhere it appears: add a string at either end (the
  proposed pitch continues the instrument's own pattern — a violin grows
  a viola's C3 below), nudge targets in place, remove down to the last;
  rows stack lowest-at-bottom, so the numbers read like a string set's.
- The strips look like strings now: each row is a compact card — name,
  dots, cents — threaded on a line that runs to both screen edges at the
  string's own gauge, the lowest fattest. The cents got bigger, lost
  their symbol, and sit on the side the pitch leans — left of the dots
  when flat, right when sharp, in reserved slots — so which way to turn
  the peg is visible before the number is read.
- The dial grid follows the strips' order: the lowest string sits at the
  bottom, rows reading left to right and climbing upward, leftover rows
  at the bottom so up-and-right always means higher. The "Low string on
  top" switch in Settings flips both views together.
- Every readout leads with your own name for the note — the chromatic
  tuner included: in German naming a guitar reads E₂ A₂ D₃ G₃ H₃ E₄
  everywhere, with the octave as a subscript (E₂ and E₄, not two Es).
  The chromatic note grew into the space its parens and the arc's hollow
  gave back; grid cells stack the name over the cents (no more sideways
  wobble) and rose into the hollow too, so an SE's six height-bound rows
  stay legible.
- On the Mac, the grid's menus no longer snap shut the moment the
  microphone hears anything — the level meter's ticking was re-rendering
  the whole screen, and macOS closes an open menu whenever its anchor
  rebuilds; the meter now ticks alone.
- Rotating an iPhone to the strips and back lands on the same grid you
  left: the collapsed title bar was quietly handing the return trip a
  taller viewport, for which the auto layout honestly picked a different
  column count. The title stays large in portrait now.

### build 2 — 2026-08-03

- An instrument now shows a dial per string rather than a single dial: playing
  the G string moves the G dial. Each dial watches only the pitches nearest its
  own string, so it reads how far *that string* is from where it should be —
  a whole tone flat reads −200¢ instead of resolving to some other note.
- Two strings bowed at once read on both dials, each with its own deviation —
  tuning by fifths the way violinists actually do. A string that's far out of
  tune is still found from semitones away.
- Playing one string never lights another string's dial: a reading that is an
  exact octave-fraction of another string's — the classic subharmonic ghost —
  goes dark instead of showing, and the dials are judged together to catch it.
- Each string's cell shows a signal bar above the dial: how much sound stands
  behind the reading, so a confident bow and something scraped off the room
  noise no longer look alike. The strings screen also shows the overall input
  level at the top, like the chromatic tuner — "the app hears nothing" and
  "sound is coming in but isn't near any string" stopped looking identical.
- The app opens on a chromatic tuner, whatever was last tuned, so checking a
  single note takes no setup. Choosing an instrument is a step into it rather
  than a setting on the tuning screen — and going back walks the same path:
  strings → instrument list → tuner.
- Pin instruments with the star in the instrument list, and they appear as
  one-tap chips on the launch screen — the violin starts pinned. Straight to
  its strings, no list in between.
- Instruments are *yours*: each remembers its own tuning and reference exactly
  as you left it, can be renamed ("Guitar 2" becomes "Strat"), and you can add
  another of the same kind. The strings screen's header shows the tuning —
  Standard, Drop D, DADGAD, Open G, Half-step down — and switching retunes
  every dial.
- Instruments can be managed anywhere: the + in the instrument list adds one
  (pick the type, name it), swipe a row on iPhone for rename / duplicate /
  delete, and on the Mac every row has a … menu with the same actions.
  Duplicate clones the whole setup — rack of guitars, one setup, cloned per
  instrument.
- Adding an instrument asks how many strings — a 6-string bass or a 9-string
  guitar is a choice in the + menu, not a missing feature. Uncommon counts
  follow the instrument's own tuning pattern, adding low strings first and
  switching to the high side where low would fall below what the app can hear
  (which is exactly how real 6-string basses are strung).
- 7- and 8-string guitars and the 5-string bass join the instrument list —
  common variants offered directly rather than hidden behind configuration.
  The 8-string's F♯1 and the 5-string's B0 are exactly the notes the
  detector's floor was lowered for.
- Save the current setup as a preset, under your own name for it — "Gig",
  "Bach No. 1" — from the tuning menu. A preset carries only what you chose
  at save time: the tuning alone, or the tuning with the reference pitch, so
  loading one never moves settings it doesn't hold. Saving over an existing
  name asks first; Edit presets… deletes stale ones.
- The tuning pill in the header names the preset you're on — save or load
  "T-bird" and the pill says T-bird, not the tuning it happens to match.
  Edit the setup by hand and it reads "T-bird (edited)" instead of pretending
  you picked whatever tuning the edit happens to match; picking a tuning or
  preset from the menu starts a fresh claim.
- The tuning menu's checkmark means "the one you picked": load a preset and
  the check is on the preset, not also on the tuning that happens to hold the
  same notes. Rows that merely match the current setup — loading them would
  change nothing — show an equals sign instead.
- A string's target can be nudged right where you tune it: the − and +
  flanking the note on the single-string screen move that string's target by
  semitones. Edit a named tuning and it relabels itself Custom — the name
  follows the pitches. The buttons don't shift with the note name's width,
  and their touch areas reach across the gaps beside it.
- Bass drop D is reachable: targets step down to B0 (a 5-string bass's low
  string), and the chromatic tuner hears that far down too.
- The padlock is a fixed toolbar toggle on the instrument's screens (the grid
  and the single string), orange and closed when locked: the whole setup —
  tuning, targets, reference — is frozen behind it. Locked controls simply
  dim; nothing pops up to explain, and tapping the lock is the one way back.
  For the music stand, and for keeping an instrument pinned at A=442.
- Tap a string in the grid to get it full screen: the big dial aimed at that
  one string, hearing the instrument's whole range — a badly slipped peg
  reads "−300¢, keep going" instead of nothing. The view never follows the
  sound to another string.
- Moving between strings has a photo gallery's physics: the dial rides your
  finger, the neighbor slides in beside it and springs into place — or snaps
  back, with a rubber-band past the outermost string. The arrows play the
  same motion, the dots beneath the dial are a scrubber (touch one to jump,
  drag across to flick through), and a swipe can begin anywhere on the
  screen, buttons included.
- With a non-English notation, the single-string screen leads with your name
  for the note — "H (B0)" rather than "B0 (H)" — matching the grid, which has
  always said H. The chromatic tuner keeps its scientific-first readout: what
  it heard, then what you call it.
- A wide screen shows the strings as strings: one horizontal strip per string
  with the tuning lights running across it, instead of dial cells stretched
  out of shape. Rotate the phone, or flip the toggle on the Mac, and the view
  follows; tall keeps the dials. The strips spread out to use the whole
  screen — four strings occupy it evenly instead of huddling at the top —
  and run low-to-high from the bottom, the way tabs are written and pitch
  reads; a Settings switch flips them for the looking-down-at-the-neck view.
- On the Mac, the strips view is a deliberate toggle in the layout menu
  rather than following the window's shape, and the window can't shrink past
  where the toolbar hides the back button.
- Every screen scales as one piece, from a tiny window to fullscreen,
  proportions kept: the chromatic tuner, the dial grid, and the single-string
  view all size against their real measured footprint, so a fullscreen Mac
  window means a big tuner rather than a small one adrift in empty space.
  Unfilled height frames the content symmetrically instead of pooling at the
  bottom, and swiping between strings feels identical at every size.
- The dial grid picks its own shape: a modest window gets one calm column,
  and extra columns have to earn their place by making the dials noticeably
  bigger — a big squarish window goes 2×2 huge, and an iPhone fits four full
  rows when they fit. The cards stay snug around their content, and a fixed
  count — or Auto again — is a menu choice away.
- The launch screen's header is a real toolbar: the level meter rides the
  title area and the settings gear is a standard toolbar button — the same
  species as the + in the instrument list, instead of a hand-drawn imitation.
- The microphone permission text and the About screen use US English
  ("analyzed", not "analysed") — the app's English is en-US throughout, and
  the documentation now follows.

## [0.1.0] — 2026-08-02

The first version: a violin-first chromatic tuner with sub-cent detection,
released as build 1 on both platforms.

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
- Tuning dial: the error shows as a filled arc between a fixed needle at center
  and one at the reading, over a logarithmic scale. Below it, eleven lights at
  ±2, 4, 8, 16, 32¢ with the center lit when in tune. Colors shift brightness
  along with hue, so the display still reads in grayscale.
- Note names in English, German (H for B♮, B for B♭), Italian solfège, or the
  Japanese iroha names, selectable and persisted.
- Named the app **Nitpitch**, and renamed the sources, schemes, and bundle id
  (`fi.misaki.nitpitch`) from the `Tuner` placeholder to match.
