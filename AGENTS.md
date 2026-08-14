# Nitpitch — agent & contributor guide

An instrument tuner for Apple platforms. **Violin is the point** — it's the
reason the app exists and the case every default is chosen for. Other string
instruments are supported because they cost almost nothing once the violin works
(an array of MIDI numbers each), not because they're equal goals. This file is
the canonical guidance for both humans and AI coding agents working in this repo.

## Project facts

- **Platforms:** iOS 16+ (mostly iPhone) and macOS 14+.
  - iOS is the primary target: a phone in a case on a music stand.
  - macOS exists because electric instruments are easier to tune over a cable —
    a guitar or bass through a DI or audio interface into line-in, rather than a
    microphone hearing an amp across the room.
- **Toolchain:** Xcode 16+ / Swift 6, XcodeGen.
- **Bundle id:** `fi.misaki.nitpitch`, shared by both platforms for Universal
  Purchase, and matching the App Store Connect record. **Don't change it** — an
  ASC bundle id can't be edited or reused once the record exists.
  **License:** MIT. No monetization.
- **No third-party runtime dependencies.** Everything needed ships with the OS:
  AVFoundation for capture, Accelerate/vDSP for the DSP, SwiftUI for the view.
  Dev tools (SwiftLint, XcodeGen) don't count and aren't SPM deps.
- The `.xcodeproj` is a **generated artifact** (gitignored) — never edit or
  commit it. Signing/team settings live only in that local file.

## Architecture: pure DSP below, platform glue above

One seam carries the whole design: **everything that can be tested without a
microphone lives in `NitpitchCore`, and everything that can't lives in `NitpitchKit`.**

- **`NitpitchCore`** — note math (`Pitch.swift`), instrument definitions, the pitch
  detector, and the display smoother. No AVFoundation, no SwiftUI. Every type
  here is a deterministic function over plain values, so it's tested against
  *synthesized* waveforms with no audio hardware. Coverage-gated at 80%.
- **`NitpitchKit`** — `AudioInput` (AVAudioEngine), the view model, and the SwiftUI
  views. Needs a real microphone and a UI to exercise, so it's coverage-ignored
  wholesale and verified by hand (`make run-mac`, then on a device).

**Keep logic in `NitpitchCore`.** That's what makes the gate meaningful — the
detector bugs found during the initial build (see below) were all caught by
`swift test` in under a tenth of a second, with no device involved.

### Structure

```text
nitpitch/
├── project.yml                     XcodeGen spec (iOS + macOS app targets)
├── Scripts/generate.sh             Regenerates the .xcodeproj (refuses if THIS project is open in Xcode)
├── Sources/{iOS,macOS}/            Thin @main app shells + Info.plist + entitlements
├── Sources/Shared/                 Assets shared by both targets (the AppIcon set)
└── Packages/NitpitchCore/          Swift package — most of the code
    ├── Sources/NitpitchCore/       Pure logic: DSP + music theory, tested + coverage-gated
    │   ├── DSP/                    PitchDetector (MPM), HarmonicEstimator (spectral),
    │   │                           DetectorBank (engines + arbitration), SubharmonicFilter,
    │   │                           Detection constants, DetectionTuning, ReadingSmoother
    │   ├── Music/                  Pitch/Note/ReferencePitch, Instrument (+ string bands)
    │   ├── Sharing/                PresetLink (+ codec), PresetImport rules
    │   └── Sync/                   SyncMerge (last-writer-wins + tombstones)
    │                               (transport: NitpitchKit/App/
    │                               {KeyValueSyncStore,SyncEngine}.swift)
    └── Sources/NitpitchKit/        AVFoundation + SwiftUI, depends on Core; coverage-ignored
        ├── Audio/                  AudioInput, AudioSessionController (one engine, fan-out)
        ├── App/                    Settings + SettingsView, DetectionSettings, LaunchStores,
        │                           AppearancePreference
        └── Nitpitch/               RootView, ChromaticTunerView, InstrumentGridView,
                                    StringTuners + StringTunerViewModel, DialView + CompactDial,
                                    DetectorDebugView
```

### How detection works, and why

**MPM (McLeod Pitch Method)**: a normalized square difference function over the
frame, then peak-picking with parabolic interpolation. Chosen over an FFT peak
because bowed and plucked strings put more energy in their harmonics than in the
fundamental — the tallest FFT bin is routinely the 2nd or 3rd harmonic, which
reads as an octave error. Normalization makes the fundamental's peak the tallest
regardless of harmonic content.

Three things are load-bearing and were each a real bug during the initial build.
**Do not "simplify" any of them without running the detector tests:**

1. **The autocorrelation input must be zero-padded by `maxLag`.** `vDSP_convD`
   reads `filterLength + resultLength - 1` samples; without the padding it reads
   past the frame and the long lags (the low notes) come back as noise.
2. **The parabolic interpolation denominator is `y0 - 2·y1 + y2`.** Inverting
   that sign reflects the estimate about the sample, biasing every reading — a
   few cents at violin pitch, catastrophically at the top of the range.
3. **The peak scan skips only the *descending* slope from `nsdf(0)`.** A blanket
   "skip everything positive" swallows the fundamental whenever the searched band
   starts near it, leaving its octave as the first candidate. `minLag` also
   carries two samples of headroom for the same reason.

Peak selection takes the **shortest-lag peak that clears
`peakPickThreshold × globalMax`**, not the tallest. A periodic signal peaks again
at every multiple of its period; taking the tallest picks one arbitrarily and
reports an octave too low.

The detector's output is deliberately **unsmoothed** — it's the truth, and the
tests assert against it. `ReadingSmoother` (median-then-exponential, in cents)
stabilizes only the *display*.

**`PitchDetector` is monophonic by construction and must stay that way.** MPM
finds *the* period of a frame; on two simultaneous notes it returns one lag that
flickers between them rather than reporting both. Do not try to make it return
two pitches — that job already has its own type: **`HarmonicEstimator`**, the
phase-vocoder path that measures every string of an instrument from one
spectrum against its known target, double stops included. `DetectorBank`
combines them: the shipped default is the frame-level hybrid — spectral wins
any frame it reads, MPM takes the frames spectral leaves silent (slack
strings, missing fundamentals). Frame-level, never per string: on a double
stop MPM invents subharmonic ghosts, so mixing engines within one frame would
reinsert exactly what spectral prevents. The debug screen's Engine switch
exposes the pure modes for diagnosis.

### Per-string detection: the settled decisions

Each one below was a real observed failure, has a regression test, and reads
as removable to fresh eyes. **It isn't.**

- **Bands split at the midpoint between neighbouring strings**, in MIDI space
  (pitch is logarithmic), with 4 semitones of headroom past the outermost.
  Not a fixed ±N: fixed widths leave dead zones wherever strings sit further
  apart than 2N, and a string slack enough to fall in one lights nothing —
  exactly when it most needs finding. Midpoints tile for any tuning,
  including custom ones. In practice each string catches ±200–400¢ depending
  on the instrument.
- **A detector never reports outside its band, and clarity is clamped to 1.**
  `minLag` headroom plus interpolation can walk a peak past the band edge
  (D4 reported 197 Hz for a played A4), and uncapped interpolated clarity
  (1.286, observed) defeats the very gate it's measured against.
- **`SubharmonicFilter`: a reading that integer-divides a higher reading is a
  shadow and goes dark.** Playing A lit G at its exact half. The tempting
  rule — distance from target — is wrong: guitar's high E4 makes the E2
  detector read a *perfect* E2 two octaves down.
- **A sentinel detector watches above the top string's band.** A note above
  every band (a stopped A5) casts ÷2 and ÷3 shadows in a 3:2 ratio the
  octave filter can't fault — landing at A −0¢ and D −2¢, plausibly in tune.
  The sentinel hands the filter the true fundamental and is never displayed.
- **Spectral readings must be anchored by the string's own 1st or 2nd
  harmonic** with real energy. G's 11th harmonic sits 35¢ inside A's
  5th-harmonic window; a foreign harmonic masquerading in an upper slot
  never brings a fundamental with it.
- **Dials light only after 2 consecutive frames agree** (one hop ≈ 46 ms at
  first light-up, instant tracking after) — single-frame coincidences never
  reach the screen. All thresholds live in `DetectionTuning`; the debug
  screen's sliders are their calibration rig.

The swept guarantee tying it together: **one pitch, at most one dial**, at
every semitone from 130 to 2000 Hz (`testAnySinglePitchLightsAtMostOneDial`).

### The tuning flow: the settled model

The product model around the detection — converged over three design drafts
and several field rounds. The changelog carries what shipped when; what's
below is *why it is the way it is*, so fresh eyes don't redesign it back into
one of the drafts that lost.

- **An instrument is one you own**: a named instance of a template
  ("Strat"), holding its own mutable state — tuning, reference, lock —
  autosaved, waiting as you left it. **Instruments exist only by seeding
  or deliberate creation, never by navigation**: first launch seeds the
  whole factory list as ordinary instances (ids = template ids, stable
  for sync and old favorites), all of them renamable and deletable down
  to an empty list; opening an instrument is just opening it. The star
  is the launch screen: starred instruments form the drag-ordered
  Favorites section whose order IS the rack's; everything else sits
  family-grouped and stable below. Duplicate opens the creation sheet
  prefilled from the source. **The string count is part of the
  instrument** — a physical fact, set at creation (uncommon counts extend
  the template's own interval pattern), never changed by a tuning.
- **A preset is a stamp, not a place**: it carries **only the fields it was
  saved with** (tuning alone, or tuning + reference), decided at save time.
  Loading copies values out; saving — with a replace confirm — is the only
  way values flow back. Presets that don't fit the instrument (template or
  string count) are never offered.
- **The factory tunings ARE presets — seeded, not special.** The catalog
  holds exactly Standard, because Standard is a fact about the TEMPLATE
  (what the instrument's name means), not a thing anyone owns. Everything
  else that used to be catalog (guitar's Drop D/DADGAD/Open G/Half-step
  down, bass's Drop D/Half-step down) is seeded once by `PresetStore` as
  ordinary presets: deletable, renameable, shareable, synced — and
  mirrored on nitpitch.app, so deleting one is never final. The load-
  bearing details: ids are stable (`seed:guitar:drop-d`) so two devices
  seed identically and old catalog PINS migrate by construction
  (`Settings.migrateCatalogPins`, one-time); the seed stamp is NIL — the
  instrument seed's `.distantPast` lesson respelled — so a real edit
  beats a seed, a deletion's tombstone beats a fresh install's re-seed,
  and the browser shows no invented date; a name the user already took
  is skipped, never twinned. Consequence for NAMING: the pill and every
  tuning label resolve past Standard through the user's own presets by
  value (`PresetStore.tuningDisplayName`) — renamed shows their word,
  deleted honestly says Custom. Trimming the seed list only affects
  fresh installs.
- **A shared preset is a value, and importing is a save from elsewhere.**
  The link carries the payload only — template, pitches, optional
  reference and temperament, and a suggested name — in the URL's
  *fragment*, which is never sent to a server, so a static host learns
  nothing about what anyone shared. **Emitted as a universal link**
  (`https://nitpitch.app/t#…`) with the fragment **base64url-armored**:
  the bare format's separators percent-encode (%7C soup), and percent
  sequences are what intermediaries re-encode and corrupt — armored, no
  character of the link ever needs encoding. Bare `v1|` fragments decode
  forever (the alphabets can't collide; `|` isn't base64url), and the
  landing page unarmors client-side. Tappable in every messenger (custom
  schemes often don't linkify), opens the app directly when installed,
  and falls back to nitpitch.app/t — a static page whose JS renders the
  fragment client-side, the one deliberate exception to the site's
  no-JS rule. The `nitpitch://preset#…` scheme is accepted FOREVER
  (shared QR codes don't expire) and is what the landing page's
  open-in-app button mints; macOS receives universal links as a
  browsing-web `NSUserActivity`, so RootView wires both
  `onOpenURL` and `onContinueUserActivity` to one receiver. Deliberately **no id, no device, no
  timestamp**: carrying the sender's id would make the link the identity
  rather than the name, letting a re-share silently overwrite edits the
  receiver made to their own copy, and putting two people who derived
  from one original in a fight over one entry — and ids are what sync
  merges on, so an imported one could collide with a preset the receiver
  already owns elsewhere.
  The **receiver takes full ownership**: an accepted preset is an
  ordinary preset — editable, deletable, synced — because the app has no
  account, no channel to push corrections through and no way to revoke,
  so "still the sender's" would be a promise the architecture can't keep
  (and fiction anyway, since sync rewrites presets under
  last-writer-wins). A re-import is therefore an ordinary **name
  collision**, resolved by the rule saving already uses — template +
  case-insensitive name, confirm before overwriting — offering Replace
  ("here's the corrected version") or Keep both ("here's a variant"),
  an intent only the user can tell apart. Unreadable links and links
  fitting no owned instrument are refused plainly: applying a tuning
  nobody sent is worse than a link that doesn't open.
- **An instrument's SHAPE is fixed once it exists.** Editing a string
  count in place was wrong in both directions: the live screen builds one
  tuner per string at init, so `configure`'s `zip` silently truncated (a
  7th string with no dial; a removed string's dial still showing), and
  every preset saved at the old shape was stranded, since a preset loads
  only onto an instrument with the same number of strings. So
  `InstrumentStore.setEditedStrings` refuses a count change — the guard
  is the store's, not the UI's — `StringListEditor` grows and shrinks
  only while `canResize` (the creation sheet), and the editor offers
  "Change string count…", which opens the creation sheet prefilled from
  this instrument. Discoverability is the point: without that button,
  "make a 7-string" means finding the + menu and knowing it offers
  counts. A creation started from an INSTRUMENT lands on the result and
  REPLACES that screen (`path = [.chooser, .instrument(new)]`), so Back
  leads to the list rather than stacking the old instrument behind the
  new one; a creation started from the chooser stays on the list, since
  you may be adding several. **The destination is `.id(instance.id)`**:
  replacing the top of the stack with another `.instrument` route reuses
  the view — and its `StateObject` tuners, one per string of the OLD
  instrument — so a five-string instrument arrived at a four-string
  screen and tripped the per-string assertion. Identity is per
  instrument, not per route slot.
- **An orphaned preset says so, and has a way back.** A preset whose
  template + string count matches nothing owned (its instrument deleted,
  or it arrived by link for a shape nobody has) can't be loaded.
  `PresetFit` decides that; the browser labels the row ("No 8-string
  Guitar") and its tap opens the creation sheet already shaped to fit —
  a row that silently does nothing reads as broken. Tapping a loadable
  preset loads it and goes there, asking WHICH instrument only when
  several fit, most recently used first: loading onto the wrong guitar
  retunes an instrument the user didn't mean.
- **The browser is YOUR collection; the per-instrument sheet is one
  instrument's window onto it.** `PresetBrowser` (the launch screen's
  "All presets…" row) lists saved presets across every instrument, with
  filter, sort — recently changed / name / instrument — rename, delete,
  favorite and share. Two things it deliberately does NOT have, both
  because they are *about an instrument*: **catalog tunings**, which
  belong to templates rather than to the user and would put a dozen rows
  they can't rename, delete or share in front of the handful they made;
  and **pinning**, since a pin is the (instrument, preset) pair and a
  global list has no instrument to bind to. `PresetManager` keeps both,
  being scoped to one instrument where "the tunings this guitar can
  wear" is short and meaningful. The row appears only once something is
  saved — a door onto an empty collection teaches nothing — so
  `LaunchRack.height(for:expanded:hasPresets:)` counts it, or the
  chromatic canvas fill goes wrong. `modifiedAt` is OPTIONAL: presets
  saved before stamping existed have none, so "recently changed" sorts
  them last and rows show no date rather than an invented one.
- **Provenance, not protection**: the header pill names the loaded preset;
  granular edits keep the claim and show "(edited)"; only an explicit menu
  pick replaces it. Drift-clears-the-claim was tried first and made the
  pill announce catalog tunings nobody picked. The tuning menu's checkmark
  is identity — the row you picked — and an equals sign marks rows that
  would change nothing if loaded.
- **The padlock is ambient and silent**: a fixed toolbar toggle (grid and
  string view alike) freezing the instrument's whole setup. Locked controls
  simply dim — the closed lock over dimmed controls IS the explanation.
  Dialog-per-touch ("unlock to make changes?") was designed and rejected:
  popups on a music stand are exactly the wrong thing.
- **Intonation is parity, not a second detector — and ambient, not a
  mode.** The string view tells the open string from its octave by which
  partials showed up: open always brings odd evidence (3f, 5f — even
  when a phone mic rolls the fundamental off), a note at 2f sounds even
  slots only. An octave *target* is impossible in the estimator by
  construction (every partial shared), so the one open-string target
  serves both notes, and the cents come out on the same scale either way.
  The screen shows everything at once: the main dial stays "how far is
  the OPEN string" and stands down while the octave plays (the bank's
  2nd-harmonic anchor would misread a fretted 12th as the open string,
  roughly in tune); the octave gets its own compact tuner below, beside
  the captures and Δ. Two classifiers route frames, because each catches
  what the other can't: parity unmasks spectral's even-anchor misread,
  and *proximity* (any reading within 150¢ of +1200) reroutes the frames
  parity can't see — MPM finds the octave exactly when spectral's gates
  failed, and the analyzer rides the same gates (the bass field case:
  55 Hz spans one FFT bin, MPM carries the frames, the 12th fret slammed
  the dial to +1200). A toggle mode was shipped first and unshipped:
  pane identity removes the ambiguity a mode would guard against, and
  nobody tunes a string an octave sharp. Captures record only from a
  consensus: six same-slot inliers around the run's rolling median (16
  frames of history, ±2¢ band, four quiet frames of grace) — outliers
  are discarded, never given a veto; a picked bass demanded the shape
  and its player proposed it. Latest run wins; live cross-talk
  may flicker, recorded numbers must not. Measurement only — works on
  locked instruments. Bowed instruments keep it: fingered-octave practice
  and the traditional false-string check (a harmonic consistently off the
  open string's promise).
- **The grid's intonation layer is claims, not new detectors** — and
  behind a toggle, unlike the string view's ambient panel: the grid is
  a tuning surface first. A string's own octave NEVER lands on its own
  dial (bands top out a few semitones past their string), so octave
  findings are claimed where they land: parity-flagged spectral frames
  on the string's own result; MPM strays within ±75¢ of some string's
  2f on a neighbour's dial; above every band, the sentinel's reading —
  which the hybrid consults even on spectral-won frames, or the top
  strings starve on exactly the instruments where spectral is healthy
  (guitar B and e, field-found). Claims normalize into parity shape so
  the view models keep one octave path, and a claim never overwrites a
  dial's live evidence. A reading that is also plausibly an OPEN string
  (Drop D's D3 is the low string's 2f) lights BOTH meanings rather than
  neither — the player chose generous display twice; consensus and
  latest-wins guard the record.
- **Temperament is a property of the targets, offered only where the
  instrument allows a choice — and pure is the bowed DEFAULT.** Beatless
  fifths by ear ARE pure (3:2, ~2¢ wide of equal); defaulting to equal
  was a keyboard convention imposed on instruments that never used it.
  Anchored at the A string, pure fifths and fourths outward, exotic
  intervals stepping equal. Worn beside the reference stepper as an
  Equal/Pure chip (tap flips; the tuning menu keeps the long-form
  picker) — the state must be readable on the tuning screens, since a
  ±2¢ target shift redraws nothing a dial would show. Storage: nil =
  never chosen = family default; explicit choices verbatim, so Equal on
  a violin sticks. Frets ARE equal temperament,
  so fretted instruments never see the row; the chromatic screen keeps
  naming equal-tempered notes (re-tempering all twelve needs a root — a
  different feature); the intonation layer needs nothing (octaves are
  2:1 everywhere). Presets carry temperament explicitly — a preset is a
  situation, and an equal preset must RESTORE equal onto a pure
  instrument, so "equal" and "unspecified" have different spellings
  (nil = legacy or unticked = leave alone). The save sheet chooses the
  payload with checkboxes — pitches always, reference and temperament
  each opt-out, labels showing the values they'd capture; the alert's
  one-button-per-combination stopped scaling at three dimensions. Just-vs-Pythagorean is moot for adjacent
  open strings — fifths and fourths are pure in both — which is why the
  one non-equal choice is just called "pure".
- **Piano was considered and parked** — wiped from the roadmap
  deliberately, not forgotten. Three arguments, all pointing the same
  way: piano owners don't tune their own pianos (hammer, mutes,
  technique — an amateur with an app can break strings), professional
  tuners are already served deep by decade-mature tools built around
  per-piano measured inharmonicity (CyberTuner, Verituner, TuneLab),
  and the casual "is my piano flat enough to call someone" case is
  already answered by the chromatic tuner. Meanwhile it was the hardest
  work on the roadmap: the detection band fails at BOTH ends for
  non-tweakable reasons (A0 has too few periods in the ~93 ms window
  for MPM; at the top octave a ~10-sample period collapses
  interpolation's cent resolution), the grid doesn't scale to 88 keys,
  and unison tuning means sub-cent resolution of two or three strings
  on the SAME note — harder detection than anything shipped. Maximum
  effort, minimum audience. The analysis already paid its rent: piano
  stretch being "exactly a temperament" is why the temperament seam is
  shaped as a per-instrument note→frequency function. If a real
  audience ever materializes, start from that seam.
- **The reference tone yields, mixes, and defers.** Detection SUSPENDS
  while the tone sounds — the roadmap's open design question, answered:
  the alternative was the detector locking onto the app's own voice —
  and the dial goes honestly idle rather than freezing (a lesson paid
  for once already). On iOS the tone plays under `.ambient`: it MIXES
  with the user's music and RESPECTS the silent switch — a reference
  tone is a courtesy, not an alarm, and an accidental ring switch
  should silence it. Capture itself runs `.playAndRecord + 
  .mixWithOthers` — plain `.record` paused the user's music the moment
  any tuner listened, which is the kind of behavior apps get deleted
  for. The tone follows retargets by GLIDING — exponential (one-pole in
  cents, ~20 ms τ), because a rate-limited glide made small steps
  effectively instantaneous again (a ±1 Hz reference step is ~4¢ —
  crossed in 0.4 ms, same kink as no glide; both found in the field).
  ONE engine app-wide, on the session controller: exclusivity is
  structural — when each screen owned a generator, two could sound at
  once. Tags say whose it is ("tone", "reference", "string.N");
  navigation begins in silence; the reference readout itself is the
  reference tone's button wherever the stepper appears, and the padlock
  freezes only the ± — listening changes no state.
- **The interval display speaks in beats, derived, and never reflows.**
  Beats are the ear's units — |3·f_L − 2·f_U| for a fifth — DERIVED from
  the double stop's two pitches rather than measured off the amplitude
  envelope: the estimator reads both notes sub-cent and its
  skip-shared-partials rule keeps each pitch clean of the very
  coincidence partial that beats (envelope measurement, which would add
  inharmonicity, waits for the field to ask). The aim follows the
  temperament — pure tunes to silence, equal's fifth honestly aims at
  ~1 Hz. Placement: the strips get the chip on the pair's shared
  boundary (adjacent strings ARE adjacent rows there); the dial grid
  gets a fixed lane under the meter with the pair edged in tint,
  because adjacent strings aren't reliably adjacent cells (two-column
  violin puts D–A on a diagonal). Both homes are overlays or reserved
  height: NOTHING may reflow the dials mid-bow. Thirds stay out
  (fretted instruments tune to frets); the beat number is the watch's
  future haptic vocabulary verbatim.
- **The strobe renders error as motion, and hands off from the
  needle.** Sub-cent error is invisible to any position display — the
  log arc made the needle honest but can't cure that — so the strobe
  band crawls at the error's own rate (one revolution per hertz-second,
  integrated from the same smoothed readings the dial shows; no new
  DSP). Self-gating within ±10¢ of the tempered target, no toggle; NO
  dead-band — a 0.2¢-flat string crawls slowly because it IS flat, and
  jitter wobbles around a truthful mean drift, as hardware strobes
  always have. String view only: grid cells are coarse by design, and
  chromatic's wandering nearest-note target defeats slow-crawl reading.
  A11y-hidden — the cents number is the accessible channel; the band is
  pure motion, and it honors Reduce Motion by not appearing.
- **Navigation is a pushed path; favorites are instruments.** Chromatic
  root → instrument list → grid → string view, and back walks the same
  path. Pinned chips jump straight to an instance; the instance
  remembering its state is what makes one tap enough — a favorite-preset
  chip would also have had to guess which guitar to load onto.
- **The Mac's launch screen scrolls its rack; the phone's scales.** A
  phone has a fixed screen, so the rack and the tuner share ONE design
  canvas scaled as a unit — every pinned row costs the dial size, which
  is what `LaunchRack.rowCap` (4) protects. A window can be resized and
  its rack can scroll, so `ChromaticTunerView+Mac.swift` serves them in
  the other order: **the tuner is paid first** (`macTunerShare`, 0.55 of
  a stacked window) and the rack scrolls in the remainder, uncapped —
  `rowCap: nil`, because a scrolling list has nothing to protect.
  Three things about this were each a real mistake:
  1. **`TunerDial` is a FIXED-size unit** (a 110pt arc with the readout
     stacked below), so widening its frame only spreads the same short
     arc into a flat smear. It must be `scaleEffect`-ed as a whole, the
     way the phone's canvas always did — then a bigger window means a
     bigger tuner with its proportions intact, and no aspect bound is
     needed to defend the shape.
  2. **Side-by-side is chosen on leftover WIDTH, not aspect ratio.** With
     a fixed 320pt rack column, a 670×580 window passed a `width >
     height × 1.15` test and left the dial ~300pt — squeezed and worse
     than stacking. The question is "is there a real dial's worth of
     width after the rack?" (`minSideBySideDialWidth`).
  3. **Pin chips wrap** (`ChipFlow`). An `HStack` distributes a shortfall
     by compressing its children, so five pinned tunings in a 320pt
     column read "S ta" and "D rc" — a shortcut nobody can read is not a
     shortcut.
- **Vertical string order is low-at-bottom by default — strips and the
  dial grid's rows alike.** Pitch intuition and tab notation agree, and a
  violin has no view in which its strings stack vertically at all; "low
  string on top" (real only as the looking-down-a-fretted-neck view) is a
  Settings preference that flips both views together — a one-column grid
  visually IS the strips, so they must agree. Within a grid row, pitch
  ascends left to right. iOS enters the strips by device shape, the Mac by
  a layout-menu toggle — a window edge-drag is not a request to change
  metaphors. Handedness needs nothing anywhere: a lefty's mirrored
  stringing and mirrored hold cancel, so string order is identical.
- **The user's name is never the tuning's name.** Instruments and presets
  carry the user's words verbatim ("Strat", "Bach No. 1"), never localized;
  catalog names localize. A tuning's displayed name is derived by matching
  pitches against the catalog — identity follows the values, so it can't
  drift from what's strung.
- **Syncing merges whole records, last writer wins, deletions leave
  tombstones.** The rules are pure functions in `NitpitchCore/Sync` and
  are tested with no iCloud, no network and no second device
  (`SyncMergeTests`); Kit adds transport only. Whole-record LWW, not
  field-level merging: a device that changed only the name would
  otherwise resurrect a tuning the other device deliberately replaced —
  a half-record nobody ever saved. LWW can lose an edit in a genuine
  race; it can never invent a state that never existed. Deletion needs
  its own record because absence carries no date: without a tombstone
  the surviving copy looks like news and merges straight back, which
  the factory seed's deliberately stable ids make a certainty rather
  than a risk. A tombstone loses to an edit that postdates it (the user
  changed their mind on some device), is dropped once its record
  returns (or the next round trip would re-delete it forever), and
  expires after six months so the set can't grow without bound. An
  unstamped record — anything stored before syncing existed — yields to
  any stamped copy. The property that matters most is symmetry: merging
  in both directions gives the same answer, or two devices disagree
  permanently, each convinced it is right.
- **Syncing's ordering rules, each of which was a real bug.** The
  transport is a `SyncEngine` over a `KeyValueSyncStore` protocol, so
  the whole of it runs against a dictionary in tests (`FakeSyncStore`,
  two engines sharing one instance = two devices). Everything below was
  caught by those tests and would have been near-invisible in the
  field:
  1. **Apply tombstones to records BEFORE pruning tombstones against
     records.** Pruning first asks "does this record still exist?" of a
     list that hasn't heard about the deletion yet, so the device
     holding the doomed record drops the very stone meant to kill it —
     and re-uploads the record forever.
  2. **The factory seed stamps `.distantPast`, not `Date()`.** A seeded
     instrument is what was there before the user did anything, so it
     must lose to every real edit. Stamped `now`, a fresh install's
     pristine "Violin" overwrites the "Konzertmeister" you renamed on
     another device last week — the newer write wins, and it is newer.
  3. **Stamp before merging, not after.** A local edit made since the
     last sync is undated until something stamps it, and an undated
     value loses every merge — so `sync()` stamps first, then applies,
     or it destroys the change the user just made.
  4. **Stamp only what actually changed.** Stamping the settings on
     every store notification made renaming an instrument mark this
     device's untouched pins as freshly edited, which then beat the
     other device's real ones.
  5. **Ties break on content, not on which side is local.** Identical
     stamps are not "the same save" — two devices seeding on first
     launch collide routinely — and preferring local resolves a tie
     differently on each device, which is the one outcome that never
     converges.
  6. **Nothing reaches the iCloud daemon on the launch path.**
     `SyncEngine.init` runs while the first frame is being built, and both
     `NSUbiquitousKeyValueStore.synchronize()` and
     `FileManager.ubiquityIdentityToken` are variable-latency calls into
     `ubd` — cheap when it's warm, visibly slow on a cold start. So the
     initializer only reads `UserDefaults`, availability starts `false`
     (the honest answer while nothing is known), and `begin()` — called
     from a `.task`, with the token read on a detached task — does the
     first round trip. `begin()` is idempotent because SwiftUI re-runs a
     `.task` on reappearance. `SyncEngineLaunchTests` asserts that
     construction touches nothing, and fails if this is undone.
  7. **A fresh joiner adopts the cloud's settings — it never announces
     its own.** A device that has never stamped is carrying install
     seeds, and "never stamped" must not read as "everything just
     changed": the first `stampSettingsIfChanged()` records the baseline
     WITHOUT a stamp, so the cloud's real settings win the first merge
     (rule 2, spoken in whole-value terms). Field-found: the first
     watch to join stamped its factory favorites fresh and wiped months
     of the phone's stars and pins off iCloud. Also a watch-platform
     fact from the same session: `ubiquityIdentityToken` is DEFINED as
     always-nil on watchOS (the signed-out gate must not use it there —
     KVS itself works).
  8. **Settings merge BY SETTING, stamped at the act.** Each star/pin/
     preset-favorite is its own KVS value (`SyncMerge.mergedFlag`),
     stamped by its store THE MOMENT the user toggles it — sync on or
     off — so devices used apart for weeks union their real choices on
     joining. A stamp exists only for values a user actually set:
     never-set can never wipe set, a stamped OFF is a real act (beats
     an older ON, loses to a newer one), and ties break to ON on both
     sides (local-wins ties never converge). Only the ORDERS stay
     whole-value — a lost order race costs cosmetics, not data. The v1
     `s.settings` blob decomposes into flags once (a stamped blob's
     absent universal seed becomes a stamped OFF — "exactly these" was
     its word) and the key is deleted.
- **Readouts are the local note name on scientific octaves.** Every
  readout — targets and detections alike — leads with the player's own
  spelling ("H₃", "Si₃"), the octave as a scientific subscript, and the
  scientific spelling in parens on the full-size dials. Helmholtz
  (`E A d g h e′`), the classically native German form, was considered
  and parked: its case-and-prime encoding needs comma prefixes exactly
  in this app's extended low range, case-as-meaning collides with a UI
  that styles note letters, and the scientific octave is the app's own
  cross-reference (A4=440, presets, docs). It could return as a third
  notation option if real users ask; it is not a relabeling.

## Commands

```sh
# Logic tests (no Xcode needed) — the fast inner loop
make test          # or: cd Packages/NitpitchCore && swift test

# Generate the Xcode project, then build an app target
make generate
make build-ios / make build-mac

# Build + launch
make run-iphone    # DEVICE="SE" / "17 Pro" to pick a simulator
make run-mac

# Local-only UI regression tests (XCUITest)
make uitest        # NOT run by CI
```

`swift build` on macOS only compiles the `#if os(macOS)` branch of platform
code — build the iOS target via `xcodebuild` to exercise the iOS branch.

**The iOS simulator has no usable microphone.** It reports an input device and
delivers silence, so pitch detection cannot be evaluated there. Use it for
layout and navigation only; the UI tests are written to this constraint and
assert on status/idle states, never on a live reading.

**To actually hear the detector work, use `make run-mac`.** The Mac app is real
capture on real hardware — no simulator involved — so it exercises the whole
audio path: permission, the engine, sample-rate conversion, the ring buffer, hop
timing, and the detector against a real instrument. It's the fast manual loop.

Two things the Mac loop can't reach, which need an actual iPhone:

- The `#if os(iOS)` branches — `AVAudioSession` with `.measurement` mode, the
  iOS 17 vs 16 permission split in `AudioInput.requestPermission()`, and
  interruption handling. A Mac build never compiles them.
- Representative input. The built-in Mac mic is voice-processed and macOS has no
  equivalent of `.measurement` to opt out, so it's noisier than the detector
  deserves. Don't tune the clarity threshold against it — use an external mic or
  interface, and confirm on a phone.

**Cross-checking absolute accuracy** (how v0.1 was verified): compare against an
independent tuner twice — once at *different* references (Nitpitch at 440, the
other at 442 gave the constant +7.85¢ = `1200·log₂(442/440)` offset), once at
the same. The match confirms the absolute reading; the offset confirms the
reference moves every reading by exactly what it should, and rules out a shared
bias that a same-reference comparison alone could hide. An offset that holds
flat across all strings is the tell — a detector fault would drift with
frequency.

### The detector diagnostics screen

`make debug-mac` / `make debug-iphone` launch with `-debug`, which adds a
**Detector…** entry to the menu on an instrument's screen. It shows what every
string's detector is seeing — frequency, cents from that string, clarity, RMS,
and the band it searched — above an engine switch and sliders for the clarity
gate, the peak-pick threshold, the spectral strength gate, the confirmation
frame count, the silence floor, and the band width.

Two gates matter for noise, and they cover different ground. The **silence
floor** judges the whole frame, so it only rejects actual quiet — while
anything plays, the frame is loud and it passes. The **strength gate**
(spectral only) is per reading, in the same 0...1 units as the cells' signal
bars: a bowed string reads at or near full, junk scraped off a loud frame sits
below half, and readings under the gate are dropped.

The engine switch exposes `DetectorBank`'s three modes: **Hybrid** — the
shipped default, spectral winning any frame it reads and MPM taking the frames
spectral leaves silent — plus pure **MPM** and pure **Spectral** for
diagnosis. Same instrument, same room, flip the switch mid-note.

The two halves only work together. Moving a threshold blind tells you nothing;
watching the numbers without being able to move anything tells you what's wrong
but not what to do. Play one note and watch which rows light: a row that isn't
the note you played is the bug worth chasing.

A launch argument rather than `#if DEBUG` on purpose. The numbers only mean
anything against a real instrument in a real room, which often means a
TestFlight build rather than one run from Xcode — compiling it out of release
would put it exactly where it can't be used. Nothing reaches it without the
flag, and a UI test asserts that.

Nothing is persisted: values reset to the shipped defaults on every launch, so a
session of experimenting can't leave the app quietly detuned. A value worth
keeping goes into `Detection` as the new constant. While anything is off its
default the menu's icon turns orange, so a surprising reading is never mistaken
for how the app really behaves.

### Lint & format

```sh
swiftlint lint --strict                 # style + light correctness (.swiftlint.yml)
swift format lint --strict --recursive --configuration .swift-format \
  Packages/NitpitchCore/Sources Packages/NitpitchCore/Tests Sources
swift format --in-place --recursive --configuration .swift-format <paths>
```

**Run SwiftLint from the repo root.** Its `excluded:` paths resolve relative to
the invocation directory, so running it from inside `Packages/NitpitchCore` lints
the generated `.build` artifacts and reports dozens of false violations.

CI runs both with `--strict` (warnings fail). **swift-format is the authority on
whitespace/punctuation**; where SwiftLint conflicts (trailing commas, brace
placement) those SwiftLint rules are disabled rather than fought. Run the
formatter before committing.

**SwiftLint is pinned to a specific version** (`SWIFTLINT_VERSION` in
`.github/workflows/ci.yml`, currently **0.65.0**) so CI and local runs agree — an
unpinned `brew install` follows the rolling latest, so a new release can turn CI
red on untouched code. Bump the CI version deliberately and update this line.
swift-format needs no pin — it ships with the Xcode toolchain, which CI pins via
`XCODE_VERSION`.

## Pull requests & CI

Branch off `main`, one focused change per PR (details in
[CONTRIBUTING.md](CONTRIBUTING.md)). Agent-specific mechanics on top of that:

- **Commit trailer:** end commit messages with a
  `Co-Authored-By: <model> <noreply@anthropic.com>` line.
- **A user-facing PR writes its own CHANGELOG bullet** under
  `### Unreleased (next build)` — the release lane only stamps the build number,
  it never writes entries.
- **The whole NitpitchKit target is coverage-ignored** (the capture + SwiftUI
  layer). Keep testable logic OUT of it — it belongs in NitpitchCore, where it's
  tracked. Target is 80% on new, non-ignored code.

## Conventions

- **Comments minimal:** explain only what isn't obvious from the code. No
  historical / roadmap ("lands later") narration in source — that goes in commit
  messages. The DSP is the exception: the non-obvious invariants above are worth
  the lines, because each one silently produces *plausible* wrong answers.
- **Never analyze on the audio thread.** The tap callback copies into the ring
  buffer and returns; DSP runs on `analysisQueue`. The render thread has a hard
  real-time deadline.
- **Never assume the hardware sample rate.** It's 48 kHz on most Macs, 44.1 or 48
  on iPhones; `AudioInput` converts to a fixed rate and the detector is built for
  the converted one.
- **Everything persisted goes through `LaunchStores.defaults`**, never
  `UserDefaults.standard` — that's what makes the `-uitest-clean` isolation gate
  total rather than partial.
- Use `.onChangeCompat` rather than `onChange` (iOS 16 floor vs the macOS 14
  deprecation — neither overload is clean on both).
- `.vscode/` is gitignored and must not be pushed.

### String catalogs (`.xcstrings`)

Only English ships today. The catalogs and `defaultLocalization: "en"` exist so
adding a locale is a translation task, not a refactor — so **user-facing strings
must go through the catalog** (`Text(..., bundle: .module)`) even while there's
one language.

- **Xcode's serialized form is canonical** (spaced colons, 2-space indent).
  After any scripted/CLI edit, normalize before committing:
  `plutil -convert json -r -o FILE FILE`.
- **Renaming a key must update its explicit `en` unit too.** An entry carrying an
  `en` localization has that value *override* the key at runtime; renaming the
  key while keeping the old unit leaves English silently showing the old text.
- Localize the **concept**, not the word — each locale by a native ear.

## Gotchas

- **`onKeyPress` fires only in the FOCUSED view hierarchy.** The string
  view's arrow keys need `.focusable()` + `.focusEffectDisabled()` +
  focus-grabbed-on-appear for exactly that reason; a bare `onKeyPress`
  on a screen that focuses nothing (the grid, the chooser) never fires,
  while building and linting green. For a key that must work regardless
  of focus, use a key equivalent — a hidden button with
  `.keyboardShortcut` (RootView's Escape-goes-back) — which dispatches
  through the window and lets a modal sheet intercept it first.
- SourceKit in-IDE diagnostics may report `No such module 'NitpitchCore'` for files
  it hasn't indexed — these are **false**. The authoritative checks are
  `swift build` / `swift test` / `xcodebuild`.
- **Building in Xcode prunes string-catalog keys that are looked up at
  runtime** — instrument names, family names, tuning names, kind tags.
  They live as plain Swift values in `NitpitchCore` and reach the screen
  through `Text(LocalizedStringKey(name), bundle: .module)`, so Xcode's
  extractor sees no literal in `NitpitchKit`'s source and deletes them as
  orphans; SwiftPM never puts them back, because they were hand-authored
  in the first place. The fix, already applied to all 17: mark them
  `"extractionState": "manual"` in
  `NitpitchKit/Resources/Localizable.xcstrings`, which the extractor
  leaves alone. **Any new runtime-resolved key needs the same marker**,
  or the next Xcode build silently drops it — and the day translations
  land, dropping a key drops its translations with it.
- **A string catalog only gains keys when someone builds in Xcode**, so a
  PR written entirely from the command line ships UI text with no catalog
  entry at all (this is how PR #106's three sync strings landed
  uncovered). `swift build` does NOT extract. After adding user-facing
  text, either build once in Xcode or add the entry by hand — and read
  `git diff` on the catalog for **deletions** as well as additions, since
  Xcode reformats the whole file and a silent removal reads as reflow.
- `Scripts/embed-commit-sha.sh` writes `unknown` for a repo with no commits yet
  (fresh `git init`) as well as for a non-git checkout. Both must not fail the
  build — this bit the very first build of this project.
- macOS needs BOTH `com.apple.security.device.audio-input` (sandbox) and
  `NSMicrophoneUsageDescription` (consent) to capture. Line-in and audio
  interfaces are gated behind the same microphone permission as the built-in mic.
- iOS sets `AVAudioSession` mode `.measurement` deliberately: it disables the
  AGC/EQ/noise-suppression that voice modes apply, all of which distort the
  harmonic content the detector depends on.
