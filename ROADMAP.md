# Roadmap

Open future work only. Settled decisions live in [AGENTS.md](AGENTS.md); what
has shipped is in [CHANGELOG.md](CHANGELOG.md).

## 1. Pick the real name — blocks everything outward-facing

`Tuner` is a placeholder. It can't be trademarked, it's invisible in App Store
search, and it collides with several hundred existing apps. **The GitHub repo
and the App Store Connect records should not be created until this is settled**,
because renaming either afterwards is disproportionately painful (ASC bundle IDs
in particular are permanent).

What the name has to do:

- Be findable in App Store search (so: not a generic dictionary word).
- Be pronounceable and spellable by a Finnish, Japanese, and English speaker —
  the localization plan targets those three.
- Have a free `.app` or `.fi` domain and a free bundle id.
- Not collide with an existing music-software trademark, which is a crowded
  field.

Directions worth exploring, roughly from most to least conservative:

| Direction | Examples | Notes |
|---|---|---|
| Pitch/tuning vocabulary, obliquely | *Cent*, *Detune*, *Concert A*, *A440* | Meaningful to musicians; several are taken, and `A440` is a common product name already. |
| Violin-specific | *Peg*, *Fifths*, *Openstring*, *Scroll*, *Bout* | `Peg` and `Scroll` are the tuning peg and the head carving — short, concrete, violin-native. Risk: too obscure for guitarists. |
| Finnish | *Viritin* (tuner), *Sävel* (tone/melody), *Puhdas* (pure/clean) | Distinctive and almost certainly free; `ä` in a bundle id and App Store search is a real friction point. |
| Japanese | *Onkai* (音階, scale), *Choritsu* (調律, tuning) | *Choritsu* is literally "tuning" and reads as a coined name in English. |
| Coined / abstract | — | Maximum registrability, zero built-in meaning. |

A shortlist worth checking availability on: **Peg**, **Fifths**, **Cent**,
**Choritsu**, **Viritin**.

Once chosen, renaming touches: `project.yml` (name, bundle id, product names,
entitlements paths), the scheme names in `Makefile` and `Scripts/*.sh`, the
Swift package and module names, `Sources/{iOS,macOS}/` file and plist names, and
the display-name entries in the `.xcstrings`. Nothing else depends on it.

## 2. Before a first release

- **App icon and launch background.** Both are placeholder entries in the asset
  catalog right now; `AppIcon.appiconset` has no actual images, which will fail
  App Store validation. Donpa generates its icon from a committed script
  (`Scripts/assets/make-icon.swift`) — worth copying that reproducible-asset
  approach rather than hand-editing PNGs.
- **Real-device verification of the detector.** Everything so far is
  synthesized-waveform tests; a real violin in a real room is a different
  signal. Specifically worth checking: the clarity threshold against actual bow
  noise, and behaviour during vibrato.
- **App Store Connect tooling.** Donpa's `Scripts/asc/` (listing and screenshot
  sync) is deliberately not copied yet — bring it over when a release is close,
  minus the achievements parts, which are game-specific.
- **PRIVACY.md.** The privacy story is unusually simple (nothing is recorded,
  nothing is transmitted) but the App Store requires it stated.

## 3. Features worth considering

- **Tone generator** — play a reference pitch to tune against by ear. The
  obvious companion to a tuner and probably the highest-value addition.
- **String-specific mode** — lock to one open string and show only distance to
  it, instead of resolving chromatically. Useful when a string is so slack it
  reads as a different note entirely.
- **Fine-tuning display** — a strobe or a beat-frequency view, which is how
  professionals actually tune to a fraction of a cent.
- **Temperaments** — just intonation and Pythagorean, for ensembles that want
  fifths tuned pure rather than equal-tempered. This is a genuine violin concern
  (violins tune in perfect fifths, which equal temperament slightly narrows) and
  would be a real differentiator.
- **Localization** — Finnish and Japanese. The string catalogs and
  `defaultLocalization` are already in place, so this is a translation task
  rather than a refactor. Deliberately deferred until the UI text settles.
- **Watch app** — a tuner on the wrist is plausible but the microphone quality
  and screen size both work against it. Unclear; investigate before committing.

## 4. Known limitations

- The **simulator has no usable microphone**, so no automated test can exercise
  live detection. UI tests cover navigation and state only; the detector is
  covered headlessly. There's no good way around this — it's an Apple platform
  constraint.
- The **detector assumes a single monophonic source**. Two strings sounding at
  once (double stops, or an open string ringing sympathetically) will produce an
  unstable reading. Polyphonic detection is a substantially harder problem and
  is not planned.
