# Roadmap

Open future work only. Settled decisions live in [AGENTS.md](AGENTS.md); what
has shipped is in [CHANGELOG.md](CHANGELOG.md).

## 1. Naming — settled

**The name is `Nitpitch`** — *nitpick* with "pitch" substituted in. The rename
from the `Tuner` placeholder is done; the sources, schemes, and bundle id all
carry it.

Registered and therefore fixed: the GitHub repo at
<https://github.com/vlumi/nitpitch>, the `nitpitch.app` domain, and the App
Store Connect record under bundle id **`fi.misaki.nitpitch`**. That last one
makes the name **irreversible in practice** — an ASC bundle id cannot be edited
or reused once the record exists, only abandoned.

Why it won: the joke is **about tuning** (nitpicking about pitch is literally
what a cent-accurate tuner does) and lands in one step; it's self-deprecating
about the app rather than mocking the player; it's one word, so Finnish
word-boundary gemination doesn't arise; it's pronounceable in English, Finnish,
and Japanese (ニットピッチ); and being coined, it's more trademarkable than the
dictionary words that kept colliding.

### If a name is ever needed again

The screening rules below were expensive to learn — eight candidates died to
them. Two checks need a **native ear, not a lookup**: Finnish word-boundary
gemination is a per-word morphological property that **cannot be inferred from
spelling** (*vire* triggers it, *sumu* does not), and a word can be perfect in
one target language while meaning something unhelpful in another (*sumu* is
Japanese for "become clear" and Finnish for "fog"). Generating candidates
without screening them in the same sitting has a near-zero hit rate.

Screening checklist: App Store search · Nordic + Baltic word check · Japanese
word/company check · what it means in the *other* two languages · music-media
trademarks (publications, not just software) · TMview/EUIPO classes 9 and 15 ·
domain · bundle id · pronounceable in all three · Finnish gemination.

Eliminated along the way: `ForkA` (Swedish verb + existing service), `Forklore`
(Japanese company), `Pitchfork` (the publication owns music search), `Tinetone`
(stationery products), `Fork440` (implies a fixed pitch to exactly the players
who want it adjustable), `Vire Tuner` (gemination — *viret-tuner*), `Sumu`
(Finnish "fog"), `Fork Horn` (too many steps to get the joke).

## 2. Before a first release

- **App icon and launch background.** Both are placeholder entries in the asset
  catalog right now; `AppIcon.appiconset` has no actual images, which will fail
  App Store validation. Donpa generates its icon from a committed script
  (`Scripts/assets/make-icon.swift`) — worth copying that reproducible-asset
  approach rather than hand-editing PNGs.
- **Verification against a real instrument.** Everything so far is
  synthesized-waveform tests; a real violin in a real room is a different
  signal. Worth checking specifically: the clarity threshold against actual bow
  noise, behaviour during vibrato, and whether the smoothing constants feel
  right to play against.

  Start on the Mac (`make run-mac`) — it's real capture and the fastest loop.
  Then repeat on an iPhone, which is both the primary target and the only way to
  exercise the iOS audio-session and permission branches. Prefer an external mic
  or interface over the built-in Mac one when judging thresholds (see § 5).
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

## 5. Known limitations

- The **iOS simulator has no usable microphone**, so no *automated* test can
  exercise live detection: UI tests cover navigation and state only, and the
  detector is covered headlessly against synthesized waveforms. This is an Apple
  platform constraint with no way around it.

  It is not, however, a limit on manual verification — **`make run-mac` is a
  real app with real capture on real hardware**, and is the intended loop for
  hearing the detector work. What it can't reach is the `#if os(iOS)` code:
  the `AVAudioSession` `.measurement` configuration, the iOS 17 vs 16 permission
  split, and audio-interruption handling. Those need a device.
- **The built-in Mac microphone is voice-processed**, and macOS offers no
  equivalent of iOS's `.measurement` mode to opt out of it. Readings through it
  will be noisier than the detector is capable of; an external mic or audio
  interface is the honest reference when tuning thresholds.
- **`PitchDetector` assumes a single monophonic source.** Two strings sounding at
  once — a double stop, or an open string ringing sympathetically — produce an
  unstable reading that flickers between them rather than reporting either. The
  *deliberate* two-note case is addressed by the separate detector in § 3;
  general polyphonic detection remains out of scope.
