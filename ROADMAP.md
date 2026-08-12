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

- **nitpitch.app's tuning collection** — the plumbing has shipped: the
  site exists, preset links are universal links
  (`https://nitpitch.app/t#…` opens the app, or shows the payload to
  anyone without it). What remains is the collection itself — curated
  pages for the long tail, scordatura and historical setups, as static
  pages of those links, growing without app updates.

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
  rather than a bespoke WatchConnectivity protocol: instruments, pins,
  references and temperaments are exactly what sync already moves, so
  the watch is the second device that makes sync earn its keep. Phone
  and Mac stay the management surfaces; the wrist gets favorites, the
  haptic tuner, maybe chromatic — no editors on a 40 mm screen.
  Remaining unknowns: the real response curve versus the spec, watchOS
  session/measurement modes, and whether MPM alone carries a bass.

## 2. Toward 1.0

Not scheduled for any near milestone — the pile that matters when an App
Store release does.

- **Release mechanics** — port donpa's `Scripts/asc/` (listing and
  screenshot sync), minus the game-specific achievements parts. The App
  Store description and privacy answers must say what PRIVACY.md now
  says: nothing leaves the device *unless you enable iCloud sync*, and
  even then only setup data, only into the user's own iCloud account.
  And the copy must not sell simultaneous-string reading on fretted
  instruments: real plucked double stops rarely register both strings
  (see the field findings below) — the interval/beat display is a bowed
  feature in the copy, however true the fourths math is on paper.
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
- **Guitar/bass detection, three open field findings** (one `-debug`
  session, guitar in hand, likely one story):
  1. Playing the high e, the low E's dial captures the note fairly
     often. The shadow-memory theory is DISPROVEN (the confirmation gate
     already covers single-frame dropouts, and the app ships hybrid, not
     the MPM path it was tested against) — needs the debug screen's raw
     per-string readings before another hypothesis.
  2. The intonation Δ didn't visibly follow saddle adjustments in either
     direction. Could be the app, measurement noise, or old strings —
     undiagnosed, and not worth code until the raw readings say which.
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
