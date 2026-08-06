# Roadmap

Planned work only — if it's not planned, it's not here. Settled decisions and
their rationale live in [AGENTS.md](AGENTS.md); what has shipped, and when, is
in [CHANGELOG.md](CHANGELOG.md).

**Where things stand:** v0.2.0 build 4 cut for beta, carrying far more than
v0.2 planned: the no-microphone survival story, the whole intonation arc
(string-view panel, grid layer), and temperaments (pure by default on bowed,
preset-carried). The "tuning the tuning" milestone's headline features
therefore shipped under 0.2.0 — the version number waits for a release that
earns it. Per-hop CPU was measured and retired as a concern — a 6-dial
guitar costs ~4.5 ms of the 46 ms hop on a desktop core (pinned by
`DetectorBankPerformanceTests`).

## 1. Tuning the tuning — what remains (violin, guitar, bass)

Improvements to the act of tuning itself, for the instruments actually on
hand. Intonation and temperaments shipped in 0.2.0 b4; what remains builds
on them, and is cohesive enough to be the next version when it ships.

### Interval tuning — the remaining half of double stops


The DSP shipped: `HarmonicEstimator` reads both strings of a double stop to
sub-cent accuracy (see AGENTS.md). What hasn't been built is the *display*
that matches how violinists actually use a fifth: set A from a reference,
then tune each remaining string against its neighbour by bowing both and
listening to the interval — D+A, then G+D, then A+E. The ear judges the
fifth, not either note alone. No mainstream tuner shows this.

- **The beat rate is likely the real prize.** In a fifth the lower note's
  3rd harmonic coincides with the upper's 2nd; near pure, those partials
  beat at a rate that *is* the tuning error, measurable from the amplitude
  envelope more precisely than either pitch. "3 beats/sec, slowing" is
  closer to what the ear does than two cent readings side by side.
- **Pure, not equal-tempered.** A violinist tuning by ear produces the just
  3:2 fifth, ~2 cents wider than equal-tempered — which the shipped pure
  temperament already encodes in the targets.
- **The UI is the genuine unknown** — two needles? a beat display? an
  interval-width indicator? Wants trying against the instrument, not
  designing on paper.
- **Known risk, not solvable in software:** sustaining a clean double stop
  is a bowing skill. The per-string signal bars already show when the bow
  favors one string; whether that's nuisance or dealbreaker is a
  real-instrument question.

### Fine-tuning display

A strobe or beat-frequency view, how professionals tune to a fraction of a
cent. Shares machinery with the interval display.

## 2. Piano — and why the target isn't always 2^(n/12)

Wanting to tune a piano with this breaks an assumption the app rests on
everywhere: that a note's correct frequency is `reference × 2^(semitones/12)`.

**Real pianos are tuned stretched.** String stiffness makes their partials
sharper than exact integer multiples of the fundamental — *inharmonicity* —
so a tuner matching octaves by ear ends up progressively sharp toward the
treble and flat toward the bass. That's the Railsback curve, roughly ±30
cents at the extremes. It isn't sloppiness: a piano tuned to exact equal
temperament sounds wrong, because its own overtones disagree with it.
Inharmonicity varies per instrument, so a good stretch curve is measured
from the piano in front of you; a published average is a starting point.

### The seam is small

Covered by the temperament seam in § 1 — piano stretch is exactly a
temperament: a per-instrument function from note to expected frequency.

### What a piano mode needs beyond that

- **The detection band itself.** The chromatic band (30–2100 Hz) was
  chosen for strings — the floor just under a 5-string bass's B0, the
  ceiling past a violin's E string — and a piano overhangs it at both
  ends: A0 and A♯0 duck under, C♯7…C8 sail over (confirmed on the
  digital piano). Neither end is a constants tweak: 27.5 Hz means too
  few periods in the ~93 ms window for MPM, and at 4 kHz its period is
  ~10 samples, where interpolation's cent resolution collapses — the
  top octave likely belongs to the spectral path.
- **88 notes, not N strings.** The grid doesn't scale to a keyboard; a piano
  wants different navigation — and the strips view already sketches its
  display: the keyboard is the strips bent into keys. Real key geometry,
  the tuning dots running vertically *inside* each key, names and cents
  above the black keys and below the white ones.
- **Unison tuning.** Most notes have two or three strings tuned to each
  other, and hearing the beats between them is most of the job — closer to
  § 1 than to the ordinary tuner.
- **Measuring inharmonicity**, if it goes beyond a published average curve.

A large feature, clearly not v0.2 — but the temperament seam is the part
everything else depends on, and worth putting in early.

## 3. Other features worth considering

- **Preset share + import** — a preset serializes into a URL fragment
  (small enough; no server) and renders as a QR code; importing shows a
  preview ("Guitar · Open G · A=442") with *Load once* and *Save*.
  nitpitch.app hosts the long tail — scordatura, historical setups — as
  those same links, so the collection grows without app updates.

- **iCloud sync** — instruments, presets, pins and order between devices.
  The design is settled: per-record last-writer-wins over
  `NSUbiquitousKeyValueStore` (one key per instrument/preset, `modifiedAt`
  as the currency — already stamped by the stores — plus deletion
  tombstones), which never duplicates because ids are stable: the factory
  seed uses template ids precisely so two devices seed identically and
  the first merge is clean. Opt-in like donpa: a toggle on the
  instruments page, off by default — because "nothing leaves the device"
  is a shipped promise (the macOS build carries no network entitlement),
  and the day sync ships, PRIVACY.md, the README and the App Store text
  all need the honest rewrite to "…unless you enable iCloud sync".
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
  and companion-shaped only in data, riding the parked iCloud sync
  rather than a bespoke WatchConnectivity protocol: instruments, pins,
  references and temperaments are exactly what sync already moves, so
  the watch is the second device that makes sync earn its keep. Phone
  and Mac stay the management surfaces; the wrist gets favorites, the
  haptic tuner, maybe chromatic — no editors on a 40 mm screen.
  Remaining unknowns: the real response curve versus the spec, watchOS
  session/measurement modes, and whether MPM alone carries a bass.

## 4. Toward 1.0

Not scheduled for any near milestone — the pile that matters when an App
Store release does.

- **Release mechanics** — port donpa's `Scripts/asc/` (listing and
  screenshot sync), minus the game-specific achievements parts.
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

## 5. Owed upstream to donpa

Found while porting its scaffold; fixed here, still broken there:

1. `Scripts/embed-commit-sha.sh` fails the build on a repo with no commits yet
   (fresh `git init`), not just on a non-git checkout.
2. SwiftLint's `excluded:` paths resolve relative to the invocation directory —
   worth a line in donpa's AGENTS.md, as here.
