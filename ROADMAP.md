# Roadmap

Planned work only — if it's not planned, it's not here. Settled decisions and their rationale live in [AGENTS.md](AGENTS.md); what has shipped, and when, is in [CHANGELOG.md](CHANGELOG.md).

**Where things stand:** v0.2.0 build 10 on beta — iPhone, Mac, and the watch (embedded in every iPhone build and standalone-installable from the watch's own App Store). The sync-robustness round is built and unit-proven; its cross-device field pass is the open verification. The version number waits for a release that earns it.

## 1. Other features worth considering

- **nitpitch.app's tuning collection, next waves** — Joni Mitchell tunings, drop A/E for the 7/8-strings, and Biber's Mystery Sonatas as a page of their own.
- **Localization** — Finnish and Japanese. The string catalogs are in place; a translation task, deferred until the UI text settles.
- **Sync discoverability, designed rather than patched** — a user on a second device (most sharply: a watch installed alone from its own App Store) probably wants iCloud sync on, and today nothing says so until they go looking in Settings. The constraint that makes this a DESIGN task: whatever advertises sync must earn its place in both states — a main-screen toggle sells the feature well but is pure noise once it's on, and one-time hints/badges are out (a one-shot hack reeks of patching bad design). Candidate directions to weigh when this is picked up: a surface that reports sync state usefully forever (and therefore may sit on the main screen honestly), or making the seeded-only state itself communicate ("your instruments from iPhone arrive here" as the empty-custom-data framing), never a dismissable banner.
- **A freeze control for the string view** — hands-free following is always on (watch parity, by field verdict); a snowflake to pin the screen to one string would be the opt-out, off by default, self-clearing on a manual string switch, with a keyboard shortcut on the Mac. Deferred as complication without a demonstrated need: a swipe already overrides any walk, and work on the focused string already resets every rival's claim.
- **"Everything sounding" display** (watch first, maybe iOS/Mac): show all recognized pitches with debounced switching — appearance is already confirmation-gated and disappearance quiet-frames-gated; the new piece is switching hysteresis (the shown pitch keeps the screen until a rival is confidently louder/closer for N frames). With an instrument chosen this is the grid the phone already has; target-free (chromatic) polyphony needs a candidate-fundamental corroboration sweep — real DSP work, bounded, not yet earned. The bowed-only copy constraint (AGENTS.md) applies to any such display.

## 2. Toward 1.0

Not scheduled for any near milestone — the pile that matters when an App Store release does.

- **Store submission legwork** — the plumbing is built (`Scripts/asc/`, listing text, shot list); what remains is running it: take the screenshots (`make shots` per platform, `make asc-screenshots-apply`), push the listing (`make asc-listing-apply`), and answer ASC's own questionnaires (App Privacy, age rating, pricing) by hand.
- **Beta verification of unowned instruments** (viola, cello, double bass) — the digital piano verifies range in five minutes per instrument; timbre needs real players via TestFlight's "What to Test". No in-app "experimental" badge either way: it would communicate risk the math doesn't have, and a badge never bowed a cello.
- **Bass through the phone microphone** — *passed on b16 (2026-08-21)*: bass through an amp reads fine at the iPhone, and violin D+G double stops stay legible (both strings' values readable, the interval delta continuously visible). Still open on this item: the iRig path on iOS specifically, and device hot-plug swapping capture over live.
- **Two open guitar checks** (the high-e capture resolved on Mac/iRig; see CHANGELOG and the field notes in git history):
  1. A phone-mic spot check of the high e — the original air-mic report hasn't been re-run since the line-level pass came back clean.
  2. The saddle-direction question: does the intonation Δ visibly follow bridge adjustments? One deliberate check with fresh strings.
- **Sympathetic-ring rejection for DIAL LIGHTING** — a design gap, not a regression: bisected across every build from b2 (2026-08-03) to b16, a violin D+G double stop lights the A and E dials *more often than the strings being bowed* once sympathetic ringing clears the presence floor (G×2 lands in A's band, D×2 and G×3 in E's — real partials of the notes being played, in neighbours' bands). Identical probe numbers at every build, so nothing broke; severity scales with input level, which is why a hot Mac input makes it feel new while an iPhone mic stays legible. `rivalLevelShare` already rejects rings for FOCUS; there is no equivalent for lighting, because from the bank's view a ringing string IS sounding. Candidate shape: when two strings a fifth apart both read, ask whether the higher one's estimate is explainable as the lower's partial AND materially weaker — the reasoning `SubharmonicFilter` applies to octave shadows, extended to the fifth. Needs its own design pass: it interacts directly with the double-stop interval feature, which depends on both strings reading at once.
- **Harmonics on low strings are energy-limited, not broken** — a bass or guitar 7th-fret harmonic is a quiet, nearly pure tone; probed through the real bank it registers down to ~1% amplitude and dies below ~0.2% against room noise, which is the clarity/strength gates working as designed. Field-confirmed hard-to-produce on b16. If this is ever worth improving it is a capture/gain question, not a detection one.
- **Cross-device sync field pass** — the built robustness round, proven on real devices: per-setting stars/pins union from any join order, unstars stick, and a first join with both-edited seeds keeps both ("Guitar 2").

## 3. Owed upstream to donpa

Found while porting its scaffold; fixed here, still broken there:

1. `Scripts/embed-commit-sha.sh` fails the build on a repo with no commits yet (fresh `git init`), not just on a non-git checkout.
2. SwiftLint's `excluded:` paths resolve relative to the invocation directory — worth a line in donpa's AGENTS.md, as here.
3. Opening a shared link (donpa.app/s/…) with the app already running spawns a second window on macOS: the WindowGroup answers external events with a new scene unless the existing window volunteers — `.handlesExternalEvents(preferring: ["*"], allowing: ["*"])` on the window content is the fix, proven here on the same bug.
