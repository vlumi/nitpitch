# Roadmap

Planned work only — if it's not planned, it's not here. Settled decisions and
their rationale live in [AGENTS.md](AGENTS.md); what has shipped, and when, is
in [CHANGELOG.md](CHANGELOG.md).

**Where things stand:** v0.1.0 (build 1) is released on both platforms;
v0.2.0 is being cut.

## 1. Finishing v0.2

- **Preset share + import.** A preset serializes into a URL fragment (small
  enough; no server) and renders as a QR code. Importing — from a link or
  the camera — shows a preview ("Guitar · Open G · A=442") with *Load once*
  and *Save*. nitpitch.app hosts the long tail — scordatura, historical
  setups — as those same links, so the collection grows without app updates
  or App Review, and the in-app picker stays uncluttered.
- **Beta verification of unowned instruments.** On hand: violin, electric
  guitar, electric bass, digital piano; not on hand: viola, cello, double
  bass. The functional check is the piano — an instrument definition is a
  MIDI array, and a digital piano is a calibrated oscillator: select the
  instrument, play its open-string pitches, confirm the right dial lights
  near 0¢ and neighbours stay dark. What the piano can't verify is timbre
  (a bowed cello's noise floor against the gates); the TestFlight "What to
  Test" says which instruments are verified by their own kind and asks
  cellists and violists to report. No in-app "experimental" badge — it
  would communicate risk the math doesn't have, and a badge never bowed a
  cello.
- **Open measurements.** CPU with N dials live: each per-string detector is
  cheaper than the old full-band one and the spectral path is one FFT per
  hop, but that's reasoning, not measurement — profile on the SE. (Two
  levers already latent if it proves expensive: the grid is lazy, so only
  track visible cells; suspend the rest while one string is enlarged.)
  Also still untested: bass through the phone microphone in `.measurement`
  mode, which should extend the double-stop range downward.
- **Release mechanics.** Port donpa's `Scripts/asc/` (listing and
  screenshot sync) for the App Store submission, minus the achievements
  parts, which are game-specific.

## 2. Interval tuning — the remaining half of double stops

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
  3:2 fifth, ~2 cents wider than equal-tempered — so this display needs the
  temperament seam (§ 3) for its reference.
- **The UI is the genuine unknown** — two needles? a beat display? an
  interval-width indicator? Wants trying against the instrument, not
  designing on paper.
- **Known risk, not solvable in software:** sustaining a clean double stop
  is a bowing skill. The per-string signal bars already show when the bow
  favors one string; whether that's nuisance or dealbreaker is a
  real-instrument question.

## 3. Piano — and why the target isn't always 2^(n/12)

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

The equal-temperament assumption lives in exactly two places, both in
`Pitch.swift`:

- `Note.frequency(reference:)` — `reference.hz * pow(2, (midi - 69) / 12)`
- `PitchReading.init(frequency:reference:)` — `12 * log2(frequency / reference.hz)`

Everything else is downstream. So a **temperament** becomes a function from
note to expected frequency, with equal temperament as the identity, and both
call sites route through it. That one abstraction covers three roadmap items
at once — piano stretch, the just-intonation reference for fifths (§ 2), and
the temperaments entry (§ 4) — so it's worth building once, deliberately.

### What a piano mode needs beyond that

- **88 notes, not N strings.** The grid doesn't scale to a keyboard; a piano
  wants different navigation — and the strips view already sketches its
  display: the keyboard is the strips bent into keys. Real key geometry,
  the tuning dots running vertically *inside* each key, names and cents
  above the black keys and below the white ones.
- **Unison tuning.** Most notes have two or three strings tuned to each
  other, and hearing the beats between them is most of the job — closer to
  § 2 than to the ordinary tuner.
- **Measuring inharmonicity**, if it goes beyond a published average curve.

A large feature, clearly not v0.2 — but the temperament seam is the part
everything else depends on, and worth putting in early.

## 4. Other features worth considering

- **Tone generator** — play a reference pitch to tune against by ear; the
  fallback when a room is too noisy. Needs no DSP (`AVAudioSourceNode` and
  the existing targets). The design question is playback against capture:
  either detection suspends while a tone sounds, or the detector hears the
  app's own output and locks onto it.
- **Intonation, for fretted instruments** — whether a string plays in tune
  *along its length*, not just open: compare the open string against the
  12th-fret note or harmonic, move the saddle, repeat. A display question,
  not DSP — the missing piece is showing two readings for one string (open
  target and what's being played now). Belongs in the string view.
- **Fine-tuning display** — a strobe or beat-frequency view, how
  professionals tune to a fraction of a cent. Shares machinery with § 2.
- **Temperaments** — just intonation and Pythagorean, for ensembles tuning
  fifths pure. A genuine violin concern and a prerequisite for § 2; shares
  the seam described in § 3.
- **Localization** — Finnish and Japanese. The string catalogs are in place;
  a translation task, deferred until the UI text settles.
- **Watch app** — plausible, but microphone quality and screen size both
  work against it. Investigate before committing.

## 5. Owed upstream to donpa

Found while porting its scaffold; fixed here, still broken there:

1. `Scripts/embed-commit-sha.sh` fails the build on a repo with no commits yet
   (fresh `git init`), not just on a non-git checkout.
2. SwiftLint's `excluded:` paths resolve relative to the invocation directory —
   worth a line in donpa's AGENTS.md, as here.
