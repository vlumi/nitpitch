# Roadmap

Open future work only. Settled decisions live in [AGENTS.md](AGENTS.md); what
has shipped is in [CHANGELOG.md](CHANGELOG.md).

## 1. Features needed for v0.1

- **Reference-pitch control — mandatory.** `ReferencePitch` is done in the core
  (390–466 Hz, persisted, live-reconfiguring), but `NitpitchView` only *shows*
  it: `Text(verbatim: "A=\(Int(settings.reference.hz))")`. There is no control
  to change it, so the README's "adjustable reference pitch" is currently false.
  A UI gap over a finished model — bind a stepper or a tap-to-edit field to
  `settings.reference` and it's done. European orchestras at 442/443 are the
  case that makes this non-optional.
- **Decide what else v0.1 needs.** Everything in § 4 is currently unscheduled.
  The two worth weighing against a first release are the **tone generator** (the
  obvious companion to a tuner, and self-contained) and **string-specific mode**
  (useful when a string is slack enough to read as a different note). Neither is
  required to ship something honest; both are cheaper than double-stop fifths.

## 2. Before a first release

- **App icon and launch background.** Both are placeholder entries in the asset
  catalog right now; `AppIcon.appiconset` has no actual images, which will fail
  App Store validation. Donpa generates its icon from a committed script
  (`Scripts/assets/make-icon.swift`) — worth copying that reproducible-asset
  approach rather than hand-editing PNGs.
- **Wire the git remote.** `git remote add origin
  git@github.com:vlumi/nitpitch.git && git push -u origin main`. CI runs on
  first push; without a `CODECOV_TOKEN` secret the coverage upload soft-fails
  but the build stays green.
- **Verification against a real instrument — started, not finished.** A violin
  through `make run-mac` worked cleanly on a brief try, so the detector holds up
  outside synthesized waveforms. Still to check, on an iPhone: vibrato, the
  clarity gate through quiet bowing and string crossings, and whether the
  smoothing feels right to tune against.
- **App Store Connect tooling.** Donpa's `Scripts/asc/` (listing and screenshot
  sync) is deliberately not copied yet — bring it over when a release is close,
  minus the achievements parts, which are game-specific.
- **PRIVACY.md.** The privacy story is unusually simple (nothing is recorded,
  nothing is transmitted) but the App Store requires it stated.

## 3. Double-stop fifths — the differentiating feature (v0.2)

**How violinists actually tune:** set A from a reference, then tune each
remaining string against its neighbour by bowing *both at once* and listening to
the fifth — D+A, then G+D, then A+E. The ear judges the interval, not either
note in isolation. No mainstream tuner shows this, and it fits the violin-first
thesis better than anything else on this list.

**Deliberately v0.2, not v0.1.** It's a *second detector*, not a tweak, and
building it before the monophonic path is validated against a real instrument
(§ 2) risks stacking on unverified ground. Ship the ordinary tuner first.

### Why the current detector can't do it

`PitchDetector` is monophonic by construction: MPM finds *the* period of a
frame. Two simultaneous notes give an NSDF carrying both fundamentals plus their
interactions, and `pickPeak()` returns one lag. It does not degrade into two
answers — it degrades into an unstable single answer flickering between them.
Don't try to coax it; add a parallel path.

### Why this specific case is tractable anyway

General polyphonic pitch detection is a research problem. This isn't that — the
constraints collapse it into something much smaller:

- **Both target frequencies are known in advance**, from `Instrument.strings`.
  It's measurement, not discovery.
- **The ratio is fixed at 3:2**, so the partials coincide: the 3rd harmonic of
  the lower note is the 2nd of the upper. That coincidence *is* the beat a
  violinist listens for.
- Only each note's deviation is needed, not identification.

### Sketch

Not autocorrelation. Two narrow **bandpass filters** (or a phase-vocoder / FFT
with phase-derived frequency) centred on the two expected notes, each yielding
an independent estimate. vDSP has the biquad and FFT primitives.

```text
FifthDetector(lower: Note, upper: Note)
  → (lowerCents: Double?, upperCents: Double?, beatRate: Double?)
```

**The beat rate is likely the real prize.** Near a pure fifth, the coinciding
harmonics beat at a rate that *is* the tuning error, measurable from the
amplitude envelope far more precisely than either pitch alone. "3 beats/sec,
slowing" is closer to what the ear does than two cent readings side by side.

**Pure, not equal-tempered.** A just 3:2 fifth is ~2 cents wider than the
equal-tempered one, and a violinist tuning by ear produces the *pure* interval.
The reference for this mode must therefore be just intonation — which pulls the
temperaments item (below) forward as a dependency, at least for fifths.

Testable headlessly against synthesized two-tone signals, exactly like the
existing suite. Estimate: ~150–250 lines of DSP plus tests, a day or two. The UI
is the genuine unknown — two needles? a single beat display? an interval-width
indicator? — and wants trying against a real violin rather than designing on
paper.

**Known risk, not solvable in software:** sustaining a clean double stop is a
bowing skill. If the bow favours one string, the quieter note's estimate gets
unreliable. Worth checking early whether this is a nuisance or a dealbreaker on
a real instrument.

## 4. Other features worth considering

- **Tone generator** — play a reference pitch to tune against by ear. The
  obvious companion to a tuner and probably the highest-value small addition.
- **String-specific mode** — lock to one open string and show only distance to
  it, instead of resolving chromatically. Useful when a string is so slack it
  reads as a different note entirely. Also a natural stepping stone toward the
  double-stop mode above, since it establishes per-string targeting in the UI.
- **Fine-tuning display** — a strobe or a beat-frequency view, which is how
  professionals actually tune to a fraction of a cent. Shares machinery with the
  beat detection above.
- **Temperaments** — just intonation and Pythagorean, for ensembles that want
  fifths tuned pure rather than equal-tempered. A genuine violin concern, and a
  **prerequisite for double-stop fifths** (see above) rather than an independent
  feature.
- **Localization** — Finnish and Japanese. The string catalogs and
  `defaultLocalization` are already in place, so this is a translation task
  rather than a refactor. Deliberately deferred until the UI text settles.
- **Watch app** — a tuner on the wrist is plausible but the microphone quality
  and screen size both work against it. Unclear; investigate before committing.

## 5. Owed upstream to donpa

Found while porting its scaffold; fixed here, still broken there:

1. `Scripts/embed-commit-sha.sh` fails the build on a repo with no commits yet
   (fresh `git init`), not just on a non-git checkout.
2. SwiftLint's `excluded:` paths resolve relative to the invocation directory —
   worth a line in donpa's AGENTS.md, as here.
