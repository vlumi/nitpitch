# Roadmap

Planned work only — if it's not planned, it's not here. Settled decisions and
their rationale live in [AGENTS.md](AGENTS.md); what has shipped, and when, is
in [CHANGELOG.md](CHANGELOG.md).

**Where things stand:** v0.2.0 build 8 on beta — iPhone, Mac, and the watch
(embedded in the iPhone build; the next cut carries it to TestFlight). The
sync-robustness round is built and unit-proven; its cross-device field pass
is the open verification. The version number waits for a release that earns
it.

## 1. Other features worth considering

- **nitpitch.app's tuning collection, next waves** — Joni Mitchell
  tunings, drop A/E for the 7/8-strings, and Biber's Mystery Sonatas as
  a page of their own.
- **Localization** — Finnish and Japanese. The string catalogs are in
  place; a translation task, deferred until the UI text settles.
- **The watch's remaining wants** (architecture and scope are settled —
  AGENTS.md "The watch"):
  - **Harmonic tuning, minimal twiddling** — concretely: NO mode, no
    setting. Playing a string's OCTAVE harmonic instead of its open
    already works today — the spectral engine folds even-partials-only
    content back to the fundamental (field-verified: the demo's G4
    phase reading +10¢ on the G string), so dial, arc and the
    haptics behave identically whether you bow the open or touch the
    node. Two refinements earn the name: (1) a LABEL — when the sound
    is best explained as harmonic k of the focused string, the header
    adds "· 2nd harmonic" under the string name, so the display
    explains why it says D2 while the ear hears D3; (2) the 3rd/4th
    harmonics — today only k=2 folds (the estimator's anchor-≤2 rule
    refuses a 3rd-harmonic-only reading), so bass-style 5th/7th-fret
    harmonics need the anchor rule relaxed behind an explicit
    harmonic-aware mapping (targets × harmonics 1–4, nearest wins),
    never silently. The near-unison two-harmonics-together technique
    stays out: two tones ~1 Hz apart defeat a 93 ms window, and with
    beat-rate haptics, one harmonic at a time is equally eyes-free.
- **Sync discoverability, designed rather than patched** — a user on a
  second device (most sharply: a watch installed alone from its own
  App Store) probably wants iCloud sync on, and today nothing says so
  until they go looking in Settings. The constraint that makes this a
  DESIGN task: whatever advertises sync must earn its place in both
  states — a main-screen toggle sells the feature well but is pure
  noise once it's on, and one-time hints/badges are out (a one-shot
  hack reeks of patching bad design). Candidate directions to weigh
  when this is picked up: a surface that reports sync state usefully
  forever (and therefore may sit on the main screen honestly), or
  making the seeded-only state itself communicate ("your instruments
  from iPhone arrive here" as the empty-custom-data framing), never a
  dismissable banner.
- **"Everything sounding" display** (watch first, maybe iOS/Mac): show
  all recognized pitches with debounced switching — appearance is
  already confirmation-gated and disappearance quiet-frames-gated; the
  new piece is switching hysteresis (the shown pitch keeps the screen
  until a rival is confidently louder/closer for N frames). With an
  instrument chosen this is the grid the phone already has;
  target-free (chromatic) polyphony needs a candidate-fundamental
  corroboration sweep — real DSP work, bounded, not yet earned. The
  bowed-only copy constraint (AGENTS.md) applies to any such display.

## 2. Toward 1.0

Not scheduled for any near milestone — the pile that matters when an App
Store release does.

- **Store submission legwork** — the plumbing is built (`Scripts/asc/`,
  listing text, shot list); what remains is running it: take the
  screenshots (`make shots` per platform, `make asc-screenshots-apply`),
  push the listing (`make asc-listing-apply`), and answer ASC's own
  questionnaires (App Privacy, age rating, pricing) by hand.
- **Beta verification of unowned instruments** (viola, cello, double
  bass) — the digital piano verifies range in five minutes per
  instrument; timbre needs real players via TestFlight's "What to Test".
  No in-app "experimental" badge either way: it would communicate risk
  the math doesn't have, and a badge never bowed a cello.
- **Bass through the phone microphone** — a minutes-long field check:
  iOS already runs `.measurement` mode (AGC and processing off), so this
  is purely playing the bass at the iPhone, single strings and the
  D+G / E+A double stops. Also through an iRig-style interface (the
  guitar already passed that path on the Mac), and the device hot-plug
  handling should swap capture over live — confirm both.
- **Two open guitar checks** (the high-e capture resolved on Mac/iRig;
  see CHANGELOG and the field notes in git history):
  1. A phone-mic spot check of the high e — the original air-mic report
     hasn't been re-run since the line-level pass came back clean.
  2. The saddle-direction question: does the intonation Δ visibly
     follow bridge adjustments? One deliberate check with fresh
     strings.
- **Cross-device sync field pass** — the built robustness round, proven
  on real devices: per-setting stars/pins union from any join order,
  unstars stick, and a first join with both-edited seeds keeps both
  ("Guitar 2").

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
