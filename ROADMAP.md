# Roadmap

Open future work only. Settled decisions live in [AGENTS.md](AGENTS.md); what
has shipped is in [CHANGELOG.md](CHANGELOG.md).

## 1. Pick the real name — blocks everything outward-facing

`Tuner` is a placeholder. It can't be trademarked, it's invisible in App Store
search, and it collides with several hundred existing apps. **The GitHub repo
and the App Store Connect records should not be created until this is settled**,
because renaming either afterwards is disproportionately painful (ASC bundle IDs
in particular are permanent).

**Preferred register: tongue-in-cheek.** A wry name is wanted over an earnest
one — but the joke has to be **about tuning**, not merely adjacent to it, and it
has to land in one step. `Pitchfork` and the *tine*/*tune* pun worked because
they sit on top of the subject; `Sumu`'s fog horn and `Fork Horn` failed because
they're funny about something else, or ask the reader to assemble too many
pieces.

### Screening checklist — run this BEFORE getting attached to a candidate

Brainstorming has repeatedly produced names that felt right and turned out to be
taken. Screen first, fall in love second. Every candidate must clear all of:

1. **App Store search** — is there an existing app with this name, especially in
   Music or Utilities? Check on the actual store, not from memory.
2. **Nordic + Baltic word check** — Swedish, Norwegian, Danish, Estonian.
   Finland's neighbours are close enough that a real word in one of them is a
   collision, not a coincidence. *(Killed `ForkA`: a Swedish verb and an
   existing Swedish service.)*
3. **Japanese check** — both as a word and as an existing company/site. One of
   the three target languages. *(Killed `Forklore`: an existing Japanese
   company.)*
4. **What does it mean in the OTHER two languages?** A word chosen for its sense
   in one target language may say something unhelpful in another. Borrowing
   across the three is the whole appeal of this shortlist, so check all three
   every time — a name only has to be wrong in one of them to be wrong.
   *(Killed `Sumu`: chosen for Japanese 澄む, "to become clear", but the Finnish
   sense is "fog" — and evokes a fog horn, which is the opposite of in-tune.)*
5. **Music-media trademarks** — the field is crowded and includes publications,
   not just software. *(Killed `Pitchfork`: the publication dominates music
   search regardless of app-listing availability.)*
6. **TMview / EUIPO**, Nice class 9 (software) and 15 (musical instruments).
7. **Domain** — a free `.app` or `.fi`.
8. **Bundle id** — `fi.misaki.<name>` free on App Store Connect.
9. **Pronounceable** by a Finnish, Japanese, and English speaker. Avoid
   consonant clusters Japanese can't render and `ä`/`ö`, which are friction in a
   bundle id and in search.
10. **Finnish word-boundary gemination** — for any two-word name. Some Finnish
   words double the next word's initial consonant across the boundary: "Vire
   Tuner" is said *viret-tuner*, and the name then fights its own pronunciation
   for the audience most likely to see it.

   **This is a per-word property, not a spelling rule** — it depends on the
   word's morphology (historically a final consonant that assimilated), so it
   can't be predicted from the vowel ending. *Vire* triggers it; *sumu* does
   not. **Ask a native speaker for each candidate**; don't infer it. A single
   compound word sidesteps the question entirely, having no boundary.

### What the structure should be

Single short words are exhausted — the space is picked over, and short
`Fork`+syllable constructions are especially prone to colliding with a real word
in a nearby language (see #2). **Two-word or compound names are the realistic
target**, in one of two shapes:

- **Coined compound** (`Tonefork`) — a real name, more trademarkable, and no
  word boundary for Finnish gemination to act on (checklist #10). **The preferred
  shape.**
- **Distinctive + generic** (`… Tuner`) — the first word carries the trademark,
  the second carries App Store search. The common pattern for music apps, and
  still open: just check the first word for gemination (#10) before committing,
  since some Finnish words mangle the second word's pronunciation and it can't
  be predicted from spelling.

### Directions explored

| Direction | Examples | Notes |
|---|---|---|
| Tuning-fork compounds | *Tonefork*, *FifthFork*, *BowFork* | The strongest direction: a tuning fork is concrete, specifically a tuning device, and gives the app icon for free. `Tonefork` is a calque of *Stimmgabel* / *äänirauta*, so it reads correctly to Europeans. **Avoid `Pitchfork`** — farm implement, and the publication owns music search. |
| Reference-point metaphor | *Polaris …* | A fixed point everything is measured against — semantically apt, and unrelated to the Finland/north angle, which doesn't carry meaning here. Heavily used commercially, so availability is doubtful. |
| Pitch/tuning vocabulary | *Cent*, *Detune*, *Concert A* | Meaningful to musicians; most are taken. **Avoid a number** (`Fork440`, `A440`): the players who most want an adjustable reference (442/443 orchestral, 415 baroque) are exactly those who'd read a fixed number as a statement, and it's a mouthful aloud in all three languages. |
| Violin-specific | *Peg*, *Fifths*, *Scroll*, *Bout* | Concrete and violin-native; risks being obscure to guitarists. |
| Tongue-in-cheek, on-topic | **`Nitpitch`**, *Wolf* / *Wolftone*, *Sour*, *Peg Leg* | A wry name is wanted — but **the joke has to be about tuning**, not merely adjacent to it. (`Sumu` was briefly appealing for its accidental fog-horn image; a fog horn is funny but says nothing about pitch, so it reads as disconnected.) **`Nitpitch` is the current front-runner** — see below. `Wolf` is the other strong one: a *wolf tone* is the real term for a note that howls on a badly-resonating string — violin-native, technical, and dryly funny to the target audience while reading as a normal short name to everyone else. |
| Tine / tune wordplay | *Tine Up*, *Tine*, *Attine* | A tuning fork's **tines** are the part that actually vibrates, so this is the mechanism rather than a decorative pun — and *tine* is one letter from *tune*. `Tine Up` (from "tune up") is the strongest form: two words, names the activity. **Caveat:** *tine* is uncommon English vocabulary and unknown in Finnish/Japanese, so for most users it reads as an odd spelling rather than wordplay. Check Norwegian first — *tine* is a verb (to thaw) and a major dairy brand. |
| Finnish | *Vire* (in tune), *Viritin* (tuner), *Sävel*, *Sointu* | `Vire` is semantically exact and reads as a clean coined name in EN/JA — but **only works standalone or as a compound**, never as `Vire <Word>` (checklist #10). `Viritin` ends in a consonant, so it pairs cleanly. |
| Japanese | *Oto* (音), *Choritsu* (調律, tuning) | Strict CV syllables make these pronounceable in all three languages — the reverse is often not true. **Check the Finnish meaning too**: *sumu* was a candidate for 澄む ("to become clear") until the Finnish sense (fog — and the fog-horn association) turned out to say the opposite of what a tuner promises. |

### Front-runner: `Nitpitch`

*Nitpick* with **pitch** substituted in. The first candidate to clear every
criterion above, at least on paper:

- **The joke is on-topic and lands in one step.** Nitpicking about pitch is
  literally what a cent-accurate tuner does — and it's self-deprecating about
  the app rather than mocking the player, which is the warmer register.
- **One word**, so the gemination question (#10) doesn't arise at all.
- **Pronounceable in all three**: no clusters Finnish or Japanese struggle with;
  renders as ニットピッチ.
- **Coined**, so more trademarkable than a dictionary word, and unlikely to
  collide the way single real words have.

Still to check: everything in the checklist, plus two specific risks — the *tp*
juncture is slightly more effortful to say than "nitpick", and some readers may
skim it as the real word and miss the joke entirely. Also confirm `nit` carries
nothing unfortunate in Finnish or Swedish.

**Never screened, worth a look:** `Nitpitch`, `Wolftone`, `Tonefork`,
`FifthFork`, `Tine Up`.

**Already eliminated:** `ForkA` (Swedish verb + existing Swedish service),
`Forklore` (existing Japanese company), `Pitchfork` (the publication owns music
search), `Tinetone` (stationery/graphic-design products), `Fork440` (implies a
fixed pitch to exactly the players who most want it adjustable), `Vire Tuner`
(Finnish gemination — *viret-tuner*), `Sumu` (Finnish "fog"/fog horn — funny,
but says nothing about pitch), `Fork Horn` (too many steps: spot the foghorn
substitution, connect fork to tuning fork, and a tuner still isn't a horn).

### A note on how to run this

Seven candidates have now been eliminated. Most died to facts — existing apps,
companies, trademarks, words in nearby languages, one phonological rule — none
of them guessable without looking. The rest died to taste: the joke pointing at
the wrong thing, or needing too much assembly. Brainstorming without screening
has a near-zero hit rate here and burns a real check per candidate to disprove.

**Generate and screen in the same sitting**, with the store and TMview open, and
**a native Finnish and Japanese ear available** for items #4 and #10. Those two
are judgement calls, not lookups: *sumu* is impeccable Japanese and a fog horn
in Finnish, and gemination can't be read off the spelling. The checklist is the
useful artifact; the candidate lists are just raw material.

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
