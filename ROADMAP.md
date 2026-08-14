# Roadmap

Planned work only — if it's not planned, it's not here. Settled decisions and
their rationale live in [AGENTS.md](AGENTS.md); what has shipped, and when, is
in [CHANGELOG.md](CHANGELOG.md).

**Where things stand:** v0.2.0 build 5 cut for beta. The "tuning the
tuning" milestone is COMPLETE, all of it under 0.2.0: intonation
(string-view panel, grid layer), temperaments (pure by default on bowed,
preset-carried), the reference tone, the interval/beat display, and the
fine-tuning strobe — plus the no-microphone survival story. The version
number waits for a release that earns it. Per-hop CPU was measured and
retired as a concern (pinned by `DetectorBankPerformanceTests`).

## 1. Other features worth considering

- **nitpitch.app's tuning collection** — plumbing shipped, first wave
  curated (31 tunings across seven instruments, one page per
  instrument, in review). It also backs the factory tunings now that
  they're deletable presets: every seeded tuning belongs on the site,
  so deleting one is never final. Remaining: a "ships in the app" group
  per instrument page, and more waves — Joni Mitchell tunings, drop A/E
  for the 7/8-strings, Biber's Mystery Sonatas as a page of their own.

- **Localization** — Finnish and Japanese. The string catalogs are in place;
  a translation task, deferred until the UI text settles.
- **Watch app** — more plausible than first assumed. The mic's reported
  response is 125 Hz–8 kHz, and the app already owns the machinery that
  floor demands: violin and viola fundamentals all sit above it; cello
  and guitar read through their 2nd harmonics, which is exactly the
  anchor-≤2 rule the estimator ships for phone mics; the 8 kHz ceiling
  is irrelevant (the highest partial used is ~4 kHz). Bass is the
  doubtful case — E1/A1's 2nd harmonics are below the floor too, so it
  would be MPM-only from harmonics 3+. Screen: the strips' light-dot
  vocabulary is already watch-sized. CPU: per-hop cost is measured in
  single-digit milliseconds on a desktop core against the 46 ms hop.
  The killer interaction is **haptic**: on the wrist you tune without
  looking at anything — both hands stay on the instrument, and taps say
  flat, sharp, in tune. Existing watch tuners prove the pattern. The
  natural vocabulary is the beat rate (taps slowing as you approach,
  stopping when pure — the same physics the interval display renders
  visually), within watchOS's preset-haptic palette; no custom waveform
  engine there. Phone haptics stay irrelevant: haptics need contact,
  and while tuning, the phone is by definition the thing not being
  held. Architecture, settled by the constraints: standalone where it
  counts — mic and DSP run on the watch (NitpitchCore is pure
  Swift + Accelerate, ports as-is), installable without the phone since
  watchOS 6, factory seeding gives a watch-only user a working tuner —
  and companion-shaped only in data, riding the shipped, field-verified iCloud sync
  rather than a bespoke WatchConnectivity protocol: instruments, PRESETS,
  pins/favorites, references and temperaments are exactly what sync
  already moves, so the watch is the second device that makes sync earn
  its keep. Phone
  and Mac stay the management surfaces; the wrist gets favorites, the
  haptic tuner, maybe chromatic — no editors on a 40 mm screen.
  **Scaffold SHIPPED**: `Nitpitch-watchOS` (watch-only bundle id,
  deliberately NOT embedded in the iOS app until it earns shipping —
  the target comment in project.yml says how to flip it), a chromatic
  one-dial screen on NitpitchCore's real pipeline — mic on the device,
  the demo's synthesized instrument in the simulator (`make
  demo-watch`), the light-strip vocabulary, and a footer that reports
  whether watchOS granted `.measurement` mode, so the wrist test
  answers that unknown at a glance. FIELD-VERIFIED: plucked violin and
  bass guitar read through the watch mic (bass E wants an amp, as
  predicted — its fundamental sits below the mic floor). Since grown:
  the hands-free one-string mode over the catalog instruments
  (`StringFocus` in Core, its rules pinned by tests; crown overrides;
  click/success haptics — the haptic vocabulary's first words), and
  the wrist's two knobs (reference pitch, temperament) shown on the
  tuner and editable in a crown-driven settings screen, stored locally
  until sync brings the real settings. Instrument LOCKS deliberately
  deferred with the same reasoning: a lock belongs to one of YOUR
  instruments, and those arrive with sync. The bass question is now
  half-closed by field test: tuning a bass WITH AN AMP works fine on
  the wrist, and the hands-free string switching felt smooth in the
  same session — the thresholds survived real hands. Unamplified bass
  stays the hard case (E1's fundamental sits below the mic floor),
  same as the phone.
  **Per-setting sync: SHIPPED** (decided and built from the first
  wrist⇄phone field session; AGENTS rule 8 has the semantics). Merging
  is done BY SETTING — each star/pin/preset-favorite its own stamped
  KVS value, stamped at the act, sync on or off — so the acceptance
  words hold: the initial not-set state of a favorite flag can never
  wipe the flag set on another device, devices used apart for weeks
  union their real choices, a stamped OFF sticks, and only the ORDERS
  remain whole-value (cosmetic stakes). The v1 blob decomposes once
  and its key is deleted.
  Same session, second decision: **duplicate on first-join conflicts.**
  Whole-record LWW silently discards one side when the SAME id (the
  seeded records) was edited on two devices before ever syncing. In
  steady state a true concurrent edit is undetectable without
  per-record base-version bookkeeping (differing stamps are what every
  routine sync looks like) — but at FIRST JOIN there is no shared
  history, so the rule is clean: same id, both sides really stamped,
  contents differ → keep both. The later edit keeps the id; the other
  becomes a copy with a fresh id and a name suffix — the keep-both
  vocabulary the preset-import collision flow already taught the app.
  Pins follow the id-keeper; the copy arrives unpinned. Nothing anyone
  did vanishes at the moment sync is first trusted; merging "Guitar"
  and "Guitar 2" back into one is the USER'S cleanup, done however
  they prefer with tools that already exist (delete, rename, re-pin) —
  the app's job ends at not deciding for them.
  SYNC HAS REACHED THE WRIST (in code; the wrist⇄phone field test is
  the remaining proof): the stores and engine moved to the portable
  NitpitchData target, the watch carries the same explicit KVS store
  id as iOS/macOS, and the root lists YOUR instruments — seeded on
  first launch like everywhere, starred first — each opening the
  hands-free tuner on ITS reference/temperament, with a detail screen
  for the lock, the knobs, and tap-to-load presets (pinned first).
  The sync switch lives in the watch settings with the phone's
  honesty: off by default, disabled-with-reason when signed out. The
  catalog section is GONE from the root — seeding makes it "my
  instruments" until pruned, and creating instruments stays a
  phone/Mac job. The settings footer wears button clothing now (the
  field note's discoverability fix).
  Wrist field notes (second session, 2026-08-14): the state so far is
  as designed — catalog only, no stars/presets/locks until sync — but
  one real finding: the "A=440 · Pure" footer IS the settings button,
  and the person who asked for the feature didn't find it. A footnote
  in tertiary text doesn't read as tappable on a 40 mm screen; give it
  button clothing (chevron, tint, or a bordered capsule) when the
  watch UI gets its next pass.
  Parked ideas from the same conversation, for after the wrist v1:
  - **Wrist double stops = the haptic beat vocabulary.** Detection
    already reads a bowed pair on the watch (same per-string bank, and
    `StringFocus` deliberately holds focus through a double stop that
    includes the focused string) — what's missing is only the readout,
    and the wrist's right form is not a shrunken chip but the
    long-planned haptics: taps at the beat rate, slowing as the fifth
    comes true, stopping when pure. Eyes never needed, which is the
    watch's whole reason to exist.
  - **Harmonic tuning, minimal twiddling.** Mostly already true: a
    sounded harmonic is a clean tone at k× the fundamental, so its cent
    error IS the string's, and chromatic mode reads it today — the
    scaffold supports tuning by harmonics with zero UI. The refinement
    worth building later: map a recognized pitch back to "that's the D
    string's 3rd harmonic" (targets × harmonics 1–4, nearest wins) so
    the display names the string, plus the haptic beat vocabulary. The
    near-unison two-harmonics-together technique is the hard case (two
    tones ~1 Hz apart in one band defeat a 93 ms window); the honest
    v1 answer is one harmonic at a time against the watch's ear.
  - **"Everything sounding" display** (watch, then maybe iOS/Mac): show
    all recognized pitches with debounced switching — appearance is
    already confirmation-gated and disappearance quiet-frames-gated;
    what's new is switching hysteresis (the shown pitch keeps the
    screen until a rival is confidently louder/closer for N frames).
    With an instrument chosen this is the grid the phone already has;
    target-free (chromatic) polyphony needs a candidate-fundamental
    corroboration sweep — real DSP work, bounded, not yet earned. The
    fretted copy-constraint applies to any such display: plucked pairs
    rarely both register, so it must never be sold as "see your whole
    strum".

## 2. Toward 1.0

Not scheduled for any near milestone — the pile that matters when an App
Store release does.

- **Release mechanics** — DONE in code: donpa's `Scripts/asc/` ported
  (listing + screenshot sync, minus the game-specific achievement
  parts), with the listing text written in `Scripts/asc/listing.json`
  and the shot list in `Scripts/asc/SCREENSHOTS.md` / `make shots`.
  Both copy constraints are baked into the text and noted at the top of
  the json: privacy says exactly what PRIVACY.md says (nothing leaves
  the device *unless you enable iCloud sync*, then only setup data into
  the user's own account), and the interval/beat display is sold for
  BOWED double stops only — plucked pairs rarely register both strings
  (field findings below). Remaining, deliberately deferred: create the
  app record in ASC, run `make asc-listing-apply` against it, and take
  the screenshots (`make shots`, then `make asc-screenshots-apply`).
- **Beta verification of unowned instruments** (viola, cello, double
  bass) — the digital piano verifies range in five minutes per
  instrument; timbre needs real players via TestFlight's "What to Test".
  No in-app "experimental" badge either way: it would communicate risk
  the math doesn't have, and a badge never bowed a cello.
- **Bass through the phone microphone** — a minutes-long field check:
  iOS already runs `.measurement` mode (AGC and processing off), so this
  is purely playing the bass at the iPhone, single strings and the
  D+G / E+A double stops. Also through an iRig-style interface: line
  level should be the happy path (no mic rolloff, no gate flicker), and
  the device hot-plug handling should swap capture over live — confirm
  both.
- **Guitar/bass detection field findings** (2026-08-14 retest: guitar
  into the MAC via iRig — the line-level happy path):
  1. RESOLVED on Mac/iRig: the high e reads confidently, no more
     low-E dial flashing while playing it. (The original report was
     air-mic; a phone-mic spot check would close it fully, but the
     line-level path is the one the Mac exists for.)
  2. LOOKING GOOD on Mac/iRig: all strings and intonations on standard
     tuning landed in the correct buckets. The saddle-direction
     question (does Δ follow adjustments?) wasn't re-run explicitly —
     still worth one deliberate check with fresh strings.
  3. Two simultaneous PLUCKED strings rarely both register, unlike bowed
     double stops. Accepted as a physics-shaped limitation (two decaying
     transients, and fretted players tune string-by-string anyway) — but
     it constrains the App Store copy below: the interval/beat display
     is advertised for BOWED double stops only, never as a fretted
     feature.

## 3. Owed upstream to donpa

Found while porting its scaffold; fixed here, still broken there:

1. `Scripts/embed-commit-sha.sh` fails the build on a repo with no commits yet
   (fresh `git init`), not just on a non-git checkout.
2. SwiftLint's `excluded:` paths resolve relative to the invocation directory —
   worth a line in donpa's AGENTS.md, as here.
3. Opening a shared link (donpa.app/s/…) with the app already running spawns a
   second window on macOS: the WindowGroup answers external events with a new
   scene unless the existing window volunteers —
   `.handlesExternalEvents(preferring: ["*"], allowing: ["*"])` on the window
   content is the fix, proven here on the same bug.
