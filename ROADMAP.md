# Roadmap

Open future work only. Settled decisions live in [AGENTS.md](AGENTS.md); what
has shipped is in [CHANGELOG.md](CHANGELOG.md).

**Where things stand:** v0.1.0 (build 1) is released on both platforms. The
v0.2 centrepiece — a dial per string, with the detection to make it honest —
is merged: midpoint bands, the subharmonic filter, the spectral engine, and
the frame-level hybrid as default. What follows is the rest of v0.2, then the
larger ideas.

## 1. Finishing v0.2

### Design draft: from launch to one string

The whole flow — instruments, tunings, presets, favourites — designed as one
thing, because it is one thing. The organizing observation: the app hosts two
different acts. **Setting up** (what am I tuning?) happens once per session;
**tuning** happens constantly. Today's pain — two taps to reach the violin —
is setup friction on a *repeated* setup, and that's exactly what a favourite
is: a repeated setup converted into one tap.

**The yardstick for every iteration of this flow:** a beginning violinist
gets there with no vocabulary and no reading, and someone who knows the app
never hears about it — guidance that only appears in the moment it's needed,
through the gesture the user was already making. Expect a few rounds against
real hands before it holds.

#### The model: your instruments, and presets as stamps

```text
Tuning     = ordered [MIDI] + its canonical name when it has one
             ("Standard", "Drop D", "DADGAD") — or none, for Custom
Instrument = one YOU OWN: "Strat", "Acoustic", "My Violin" — a named
             instance of a template (guitar, violin…), holding its own
             mutable state (tuning + reference + lock), autosaved,
             waiting as you left it. One is auto-created per template
             ("My Guitar"), so nobody meets the plural until they own
             a plural: "Add another guitar…" is where it appears.
             THE STRING COUNT IS PART OF THE INSTRUMENT — it's a
             physical fact, set when you add one (a 7-string guitar is
             added as one), changed by editing the instrument, never by
             a tuning.
Preset     = a frozen setup under the USER'S name ("Bach No. 1").
             Not a place you visit — a stamp you LOAD onto an
             instrument, after which everything is freely tweakable.
             Saving is the only way values flow back: Save → "New
             preset…" / "Replace 'Bach No. 1'", with a confirm.
Lock       = per-instrument, optional: a padlock in the header holds
             the whole setup — the orchestral "keep my violin at 442",
             and stray-tap protection on a music stand.
Favourite  = an instrument pinned to the launch screen.
```

Three earlier drafts converged here, each killing a concept:

- **Instances killed favourite-presets.** People own several guitars, and
  each remembers its own state — so if your Violin sits at Bach No. 1,
  tapping "Violin" *is* one-tap-to-Bach-No.-1. The instrument is the
  memory. (A preset chip would also have had to guess *which* guitar to
  load onto.)
- **Load-semantics killed the locked preset session.** Presets stay frozen
  (loading copies values out; saving is explicit and confirmed), but
  there's no "being on a preset" — so there's only ever ONE kind of
  screen: your instrument, mutable. The trade, taken knowingly: drift
  after loading is *visible* rather than *impossible* — the header's
  "Strat · Bach No. 1" becomes "Strat · Bach No. 1 (edited)" on the first
  nudge.
- **The per-instrument padlock resurrected what the locked session did
  well, in its natural home.** "Hold this at A=442" is a property of
  *your violin*, not of a preset's honor. Locked controls keep the doors
  rule: they never mutate and never ignore a touch — touching one offers
  "This instrument is locked. Unlock to make changes?", Cancel means
  nothing happened, unlocking lands on the same screen with the control
  live. Loading a preset counts as a change, so the lock guards it too.

The reference pitch belongs to the instrument's state (and to presets),
not to a global setting: "Bach No. 1 at A=442" only means something if 442
is part of it. Chromatic keeps its own. Sharing stays a preset in a URL.
`Instrument` templates keep the catalog of known tunings; the midpoint band
scheme already accepts any string array, so custom tunings — odd string
counts included — need no special-casing downstream.

#### The navigation

```text
Chromatic launch  (unchanged: immediately usable, no setup)
├── favourites row: [My Violin] [Strat] [Acoustic] …   ← ONE tap, as you
│                                                        left it
└── "Instruments…" — pushed, not a sheet
        Your instruments (rename / string count / reorder / add another)
        Bowed / Fretted / … templates → opens (creating if first time)
                                        that template's default instance
        Import preset…                 (paste link / scan QR)

Grid — header "Strat · Bach No. 1", or "· Drop D (edited)"; 🔒 if locked
├── tuning menu: known tunings · load preset · Save as preset…
├── reference stepper
└── tap a cell → String view

String view (one string, full screen)
├── full dial, wide-band listening — tracks a slipped peg from anywhere
├── ◀ ▶ / swipe between strings; back → grid
└── the string's TARGET is a stepper here: nudge D2 down to C2 and the
    tuning label forks to "Custom"
```

Decisions this draft takes, and why:

- **Push the chooser; drop the accordion.** The accordion's one advantage —
  choosing tuning at instrument-choice time — is served better by
  favourites (the repeat case) and by the grid header's tuning menu (the
  change-of-mind case). With those, the chooser can stay a dumb list, and
  back finally walks the path you came.
- **Per-string editing lives in the string view.** "Choose individual
  tunings for each string" needs no new screen: you're already looking at
  one string full screen, so its target is editable right there. Retuning
  a string of "Drop D" relabels the instrument's tuning *Custom* — named
  tunings are never edited in place — and "Save as preset…" is how Custom
  gets a name. Tunings are purely about *pitches*: the string count
  belongs to the instrument, so the once-awkward "Customize…" list editor
  disappears from the tuning menu entirely.
- **Presets that don't fit your instrument don't offer themselves.** A
  7-string preset on a 6-string Strat is a type error, not a runtime
  surprise: it lists disabled, with the reason ("7 strings"). This closes
  what an earlier draft left open.
- **Locked controls are doors, not corpses** — on a locked *instrument*,
  since that's the only lock left. Never mutating, never ignoring: the
  novice discovers the way forward with the only gesture anyone tries
  first, the expert who leaves things unlocked never hears about any of
  it, and a stray tap on a music stand dies at a dialog.
- **"(edited)" is the drift alarm.** With no locked preset mode, noticing
  replaces impossibility: the header names what was loaded and admits
  what's changed. Anyone who wants impossibility back locks the
  instrument — that's what the padlock is.
- **Sharing is a URL, and the site is the library.** A preset serializes
  into a link fragment (small enough; no server) and renders as a QR
  code. Importing — from a link or the camera — shows a preview
  ("Guitar · Open G · A=442") with *Load once* and *Save*. nitpitch.app
  hosts the long tail — scordatura, historical setups — as those same
  links, so the collection grows without app updates or App Review, and
  the in-app picker stays uncluttered.
- **The user's name stays separate from the tuning's name.** Two presets
  can hold identical strings and differ only in purpose; renaming on save
  is the expected move, not an edge case. Instruments are named the same
  way — "Strat" is what it means to you, not what the factory called it.

Open, deliberately: favourites-row capacity (cap at ~4, overflow scrolls?),
whether presets and instruments sync via iCloud or stay per-device, and
whether favourite *presets* return one day — a chip that loads a preset onto
a remembered instrument. Instruments cover the one-tap need first; the chip
kind can wait for a real itch.

#### Build order

Shipped: the pushed chooser, the favourites chips, the string view, and the
instances themselves — the store, the tuning catalog with its header menu,
rename / add another / delete, and the padlock with its door dialogs. What
remains:

1. **Per-string target editing** in the string view; Custom relabeling.
   String counts ride with instrument creation/editing, so no separate
   tuning editor exists at all. (Creation currently copies the template's
   count; a string-count choice at add time joins when a 7-string template
   or count editing is wanted.)
2. **Presets**: save, load, name; then URL/QR share + import.

### The string view: what remains

The view itself shipped (full dial, whole-instrument band, arrows/swipe,
never follows the sound). Still to come there:

- **Target editing** (build order step 2): the same screen answers "how far
  is this string from D2" and "make this string's target C2".
- The intonation feature (§ 4), eventually.

### Landscape reflow

The grid scrolls vertically at any string count; what it doesn't yet do is
reflow for a wide, short landscape screen — fewer rows, more columns,
scrolling sideways where portrait scrolls down. Each dial stays upright
relative to the player either way, so sharp is always to the right.

### Open measurements

- **CPU with N dials live.** The per-string detectors are each cheaper than
  the old full-band one (shorter lag searches), and the spectral path is one
  FFT per hop — but that's reasoning, not measurement. Profile on the SE.
  Two levers if it proves expensive, both already latent in the design: only
  track visible cells (the grid is lazy), and suspend the rest while one
  string is enlarged.
- **Bass through an amp and through the phone.** Prediction on record: the
  spectral engine needs the string's own 1st/2nd harmonic (the anchor rule),
  and an unamplified bass through the Mac's voice-processed mic barely
  reads — 41/82 Hz sit under its rolloff. Through a DI or the phone's
  `.measurement` mode, 82 Hz should survive and spectral should recover;
  under the hybrid, MPM covers it meanwhile. The amp/phone session confirms
  or corrects this.

### Verifying instruments nobody here owns

On hand: violin, electric guitar, electric bass, digital piano. Not on hand:
viola, cello, double bass. Should the unverified ones ship marked
"experimental"? **No — verify them with the piano instead.**

- **An instrument definition is a MIDI array.** The detector doesn't know
  names; it knows frequencies. The failure modes worth fearing are *range*
  and *timbre*, not which label the picker shows.
- **Range is already covered.** Violin, electric guitar and electric bass
  together span 41–659 Hz of open strings; every string of every shipped
  instrument falls inside that. Double bass is literally the same MIDI array
  as bass guitar.
- **A digital piano is a calibrated reference oscillator.** The functional
  check for an unowned instrument takes five minutes: select it, play its
  open-string pitches on the piano, confirm the right dial lights near 0¢
  and its neighbours stay dark. (Piano stretch is negligible mid-range;
  don't use it to judge cents at the extremes.)

What the piano can't verify is timbre — a bowed cello's noise floor against
the gates. That's what the TestFlight beta is for: say in "What to Test"
which instruments are verified by their own kind and ask cellists/violists
to report. An in-app "experimental" badge would communicate risk the math
doesn't have, and would not catch the risk that does exist — a badge never
bowed a cello.

### Release mechanics

Donpa's `Scripts/asc/` (listing and screenshot sync) is deliberately not
copied yet — bring it over when the v0.2 release is close, minus the
achievements parts, which are game-specific.

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
  favours one string; whether that's nuisance or dealbreaker is a
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
  wants different navigation — a keyboard strip, or note-by-note.
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
  target and what's being played now). Belongs in the string view (§ 1).
- **Lock the settings** — freeze the reference and tuning so a stray tap
  mid-session can't move them. Most valuable exactly where the app is most
  exposed: on a stand, handled one-handed. Small to build; the design
  question is how you get *out* without that being just as easy to trigger.
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
