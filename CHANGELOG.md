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

- A device joining sync for the first time now ADOPTS your existing
  setup instead of announcing its own factory state: the first sync
  treats never-touched settings as unstamped, so months of stars and
  pins on iCloud can no longer be wiped by a fresh install's defaults
  (found the hard way by the first watch to join). The watch's sync
  switch also works now — watchOS pretends to be signed out of iCloud
  to the check the other platforms use, and got its own.
- The string view can follow your hands: a Follow toggle (the little
  location arrow beside the string dots) walks the screen to the string
  you're actually playing — a brushed neighbour never steals it, only a
  string played on purpose, and once the current string has held in tune
  a moment the next one takes over almost instantly. Off by default:
  swiping and the arrows stay the only movers until you ask.

### build 8 — 2026-08-12

- Tap a preset in the Manage-presets sheet to load it onto the
  instrument you came from — no menu detour. An equals mark shows the
  row the instrument is already on, so a tap that would change nothing
  says so up front.
- An instrument's Manage-presets sheet shows only presets it can
  actually wear: a nine-string experiment no longer clutters your
  six-string's list. Everything still lives in All presets, which can
  pick the right instrument — or offer to create it.
- The built-in tunings are yours now: Drop D, DADGAD, Open G and the
  rest arrive as ordinary presets — delete the ones you'll never use,
  rename them, pin them, share them, and they sync like anything you
  saved yourself. Deleting one sticks (even across your devices), and
  every one of them lives on nitpitch.app if you ever want it back.
  Standard stays built in: it's what the instrument's name means. One
  visible consequence: hand-tune to pitches you have a preset for and
  the header names it YOUR way — renamed it, and it shows your word;
  deleted it, and it honestly says Custom.
- Mac: opening a shared preset link no longer spawns a second tuner
  window — the one you already have takes it.
- Preset links are real web links now: sharing gives
  `https://nitpitch.app/t#…`, which is tappable in any messenger, opens
  the app directly when it's installed, and shows the tuning to anyone
  without it. The payload travels in a form that needs no escaping
  anywhere, so no mail client or messenger can mangle it in transit.
  Old `nitpitch://` links and QR codes keep working, and what travels
  is unchanged — the setup itself, never sent to any server.
- Mac: the launch screen's instrument list stopped misbehaving around
  its scrollbar — no more flashing layout when expanding an instrument's
  presets, no scrollbar on a list that visibly fits, and in a tall
  window the list now uses the space the dial can't, scrolling only when
  the collection genuinely outgrows the window.
- Mac: Escape goes up a level — string view to grid to instrument list
  to the tuner — the keyboard's answer to the phone's edge swipe. A
  sheet still takes the key first, and at the root it does nothing.

### build 7 — 2026-08-10

- Mac: the launch screen's instrument list scrolls instead of shrinking
  the tuner. However many instruments you keep, the dial gets the space —
  and it now grows with the window rather than stopping at a fixed size,
  side by side in a wide window or above the list in a tall one.
- Mac: an instrument's pinned tunings wrap onto more lines instead of
  squeezing into unreadable slivers.
- Making an instrument from another one — "Change string count…", or
  Duplicate from inside an instrument — now opens the one you just made,
  instead of leaving you on the old one wondering whether it worked.
- Adding or removing strings on an instrument you already have is gone,
  and that's a fix: the screen kept showing dials for the old strings
  until you left and came back, and every preset you'd saved for that
  instrument quietly stopped fitting it. A different number of strings is
  a different instrument — "Change string count…" in the string editor
  makes one, keeping the original.
- All presets: tap one to load it — it asks which instrument when several
  fit — and a preset that fits nothing you own now says so and offers to
  make the instrument it needs, instead of just refusing.
- All your presets in one place: a row on the launch screen (once you've
  saved one) opens the whole collection across every instrument —
  filterable by instrument, sortable by what you changed last, by name,
  or by instrument, and each row says which instrument it fits, what it
  carries and when you last touched it. Rename lives here too, which
  nothing offered before: a typo used to mean saving again and deleting
  the old one.
- Presets can be shared: the ↑ on a saved preset shows a QR code for a
  bandmate to scan and a link to send. Opening one offers to load it
  once or keep it, and what you keep is yours — editable, and a later
  version of the same thing asks whether to replace it or keep both
  rather than overwriting your edits. Nothing but the setup travels.
- Launching is quick again on a cold start: with iCloud sync on, the app
  was talking to iCloud before it drew anything, and how long that took
  was up to the system. Syncing now begins after the tuner is on screen.

### build 6 — 2026-08-08

- iCloud sync, off until you turn it on: a switch at the foot of the
  instrument list keeps your instruments, presets and favorites the same
  on every device signed in to your iCloud account. Off, nothing leaves
  the device, exactly as before; signed out of iCloud, the switch
  disables itself and says why.
- The fine-tuning strobe: a band under the string view's dial that shows
  sub-cent error as motion — crawling right is sharp, left is flat,
  stationary is in tune, one revolution per hertz-second. It wakes
  within ten cents of the tempered target, where the needle runs out of
  resolution, and has no dead-band: a string a fifth of a cent flat
  crawls slowly, because it is flat.
- Pinned presets moved behind their instrument's accordion: a separated
  trailing chevron discloses the chips while the row itself still opens
  the instrument. Rows without pins carry no chevron, the expansion is
  remembered, and the chips grew into proper finger targets.
- The dial's sweep is logarithmic now, like the dots always were: equal
  RATIOS of error get equal angles, so the in-tune boundary sits at 18
  degrees instead of 3.6, and the scale ticks ride the same curve.
- The launch screen's instrument rows grew into proper finger targets
  (they sat under Apple's 44-point floor), their names sized with them.
- The screen stays awake while you tune — and only while: a confident
  reading or a sounding tone holds it, released ninety seconds after the
  last sign of life. Mac displays get the same courtesy.
- The reference tone is properly audible now, low strings included: it
  carries harmonics a phone speaker CAN produce and the ear rebuilds the
  pitch from them, at a higher playing level, edges still clickless.

### build 5 — 2026-08-06

- Bowing two adjacent strings shows the interval itself, in the ear's
  own units: BEATS — the pulse rate IS the tuning error. A chip reads
  "D–A · 2.7/s" with a dot pulsing at the true rate, in a fixed lane
  under the dial grid's meter (the sounding pair edged in tint) or, in
  the strips, straddling exactly the two strips it names. The advice is
  drawn, not written: arrows spreading mean widen, converging mean bring
  together, a green checkmark means leave it be. The aim follows the
  temperament — pure tunes to silence, equal honestly aims at its own
  ~1 beat per second — and fourths ride the same physics on bass and
  guitar.
- A reference tone: the speaker in the string view sounds the current
  string's tempered target, to tune against by ear or to survive a room
  too noisy to detect in. Swiping strings mid-tone glides the pitch, as
  do reference steps; detection pauses while it sounds, the tone mixes
  with whatever you're listening to instead of pausing it, and it
  respects the silent switch. The grid grew speakers of its own — one
  per cell, one per strip card — and the reference readout itself is now
  the tone's button on every screen it appears. One engine serves the
  whole app, so two screens can never sound at once; a locked
  instrument's padlock freezes only the ± steps, never the listening.
- The tuner no longer pauses your music: capturing used a non-mixable
  audio session, so opening any tuner silenced whatever was playing.

### build 4 — 2026-08-05

- The presets sheet fits phones again: its Mac minimum width (400pt) was
  forced onto a 375pt iPhone, eating the list's horizontal margins. The
  rows' payload line gained the tuning menu's "· pure" vocabulary.
- Saving a preset chooses its payload with checkboxes: the pitches
  always ride, while the reference and — on bowed instruments — the
  temperament are labeled toggles showing what they'd capture, both on
  by default. The old alert had one button per combination.
- Bowed instruments tune the way orchestras do, by default: pure fifths
  (fourths on the double bass) anchored at A, so a violin's E sits +2¢
  and G −4¢ against equal temperament. Presets carry the choice as part
  of the situation, presets saved before this leave it alone, and
  fretted instruments never see the row — frets are equal temperament
  cast in metal. The state is worn as an Equal/Pure chip beside the
  reference stepper; the tuning menu keeps the long-form picker.
- Mac: ← and → walk the strings in the string view, live from the
  moment the screen opens.
- The intonation check scales to the whole instrument: a "Check
  intonation" toggle in the grid's … menu lights the octave layer on
  every cell and strip at once — a tiny second light strip above each
  string's dots, the Δ verdict beside it. Octave findings are claimed by
  their owners wherever the engines put them, and in octave tunings like
  Drop D an ambiguous note lights both of its meanings rather than
  neither.
- The string view checks intonation ambiently — no mode to find: below
  the switcher sits the octave's own tuner, both captured samples, and
  the verdict between them (Δ positive = octave sharp; a guitar's saddle
  wants to move back). One detector tells the two notes apart by what's
  missing — an open string always sounds odd partials, its octave only
  even ones — so the main dial now stands down honestly while the octave
  plays, readings near +1200¢ route to the octave whatever engine found
  them, and capture locks meet a picked bass halfway: six frames
  agreeing around the run's median, with grace at the strength gate.
- A Mac with no microphone at all no longer crashes at launch: the app
  checks for input devices before asking the engine, and says so — "No
  audio input device", with a Retry button for when one arrives.
- …and the message actually appears: the tuner now observes the audio
  status instead of sampling it once in a race it usually lost, so a
  mic-less Mac no longer shows a stale "Not listening" forever.
- Unplugging the microphone mid-run no longer strands the tuner: capture
  rebuilds itself around whatever the input is — unplug drops to "No
  audio input device", replug picks the tuning back up on its own.
  Device events arrive in storms, so they coalesce into a single rebuild
  once the hardware settles; answering each directly crashed mid-replug.

### build 3 — 2026-08-04

- Instruments are deliberate now, and the factory list is real: first
  launch seeds one ordinary, fully editable instrument per catalog
  kind — rename the violin "Guarneri", delete the ones you'll never
  touch (all of them, if you like; a big Add button takes their place).
  Each row carries a small kind tag (Vln, Gtr, Bass…) and its current
  tuning, so which is which reads at a glance.
- The star is the launch screen: starred instruments form a
  drag-ordered Favorites section whose order IS the home screen's,
  everything unstarred sits below, family-grouped. The old truncating
  chips grew into a rack of full rows (kind tag, name, tuning, padlock)
  that say what they'll open into, capped at four, "All instruments…"
  one row below.
- Presets and tunings can be pinned to an instrument — Standard
  included: light the 📌 in Manage presets… and a chip under that
  instrument's launch row opens it with that setup loaded, an explicit
  pick that overwrites any drift. The pin is the (instrument, preset)
  pair, so pinning Gig to one guitar never surfaces it on another;
  pinned entries float to the top of the tuning menu, and on a locked
  instrument the chips dim and only navigate. Presets gained
  template-wide ★ favorites of their own.
- Adding an instrument is one sheet: pick the kind from the + menu and
  the name and strings are decided together — common string counts as
  one-tap chips (double bass 4/5, guitar 6/7/8, bass 4/5/6), the full
  string list behind a disclosure, nothing ever labelled "custom".
  Duplicate opens the same sheet prefilled from the source.
- The instrument's own screen manages the instrument: an … menu carries
  Rename, Duplicate, Edit strings and Delete alongside the column
  picker. The string list is editable everywhere it appears: add a
  string at either end (the proposed pitch continues the instrument's
  own pattern — a violin grows a viola's C3 below), nudge targets in
  place, remove down to the last.
- The strips look like strings now: each row a compact card — name,
  dots, cents — threaded on a line that runs edge to edge at the
  string's own gauge, the lowest fattest. The cents sit on the side the
  pitch leans — left when flat, right when sharp — so the peg direction
  reads before the number does.
- The dial grid follows the strips' order: lowest string at the bottom,
  rows climbing so up-and-right always means higher. The "Low string on
  top" switch flips both views together.
- Every readout leads with your own name for the note — the chromatic
  tuner included: in German naming a guitar reads E₂ A₂ D₃ G₃ H₃ E₄
  everywhere, octave as a subscript. The chromatic note grew into the
  space its parens gave back; grid cells stack the name over the cents.
- On the Mac, the grid's menus no longer snap shut the moment the
  microphone hears anything — the level meter was re-rendering the whole
  screen, and macOS closes a menu whose anchor rebuilds. It ticks alone.
- Rotating an iPhone to the strips and back lands on the same grid you
  left: the collapsed title bar was handing the return trip a taller
  viewport and honestly a different column count. The title stays large
  in portrait.

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
