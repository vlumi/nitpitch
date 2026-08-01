# Tuner — agent & contributor guide

An instrument tuner for Apple platforms. **Violin is the point** — it's the
reason the app exists and the case every default is chosen for. Other string
instruments are supported because they cost almost nothing once the violin works
(an array of MIDI numbers each), not because they're equal goals. This file is
the canonical guidance for both humans and AI coding agents working in this repo.

> **The name `Tuner` is a placeholder.** It is not final and is not
> registrable — see [ROADMAP.md](ROADMAP.md). Renaming touches `project.yml`,
> the bundle id, the scheme names in `Scripts/*.sh` and `Makefile`, the Swift
> package/module names, and the `.xcstrings` display-name entries. Nothing else
> depends on it.

## Project facts

- **Platforms:** iOS 16+ (mostly iPhone) and macOS 14+.
  - iOS is the primary target: a phone in a case on a music stand.
  - macOS exists because electric instruments are easier to tune over a cable —
    a guitar or bass through a DI or audio interface into line-in, rather than a
    microphone hearing an amp across the room.
- **Toolchain:** Xcode 16+ / Swift 6, XcodeGen.
- **Bundle id:** `fi.misaki.tuner` (shared by both platforms for Universal
  Purchase). **License:** MIT. No monetization.
- **No third-party runtime dependencies.** Everything needed ships with the OS:
  AVFoundation for capture, Accelerate/vDSP for the DSP, SwiftUI for the view.
  Dev tools (SwiftLint, XcodeGen) don't count and aren't SPM deps.
- The `.xcodeproj` is a **generated artifact** (gitignored) — never edit or
  commit it. Signing/team settings live only in that local file.

## Architecture: pure DSP below, platform glue above

One seam carries the whole design: **everything that can be tested without a
microphone lives in `TunerCore`, and everything that can't lives in `TunerKit`.**

- **`TunerCore`** — note math (`Pitch.swift`), instrument definitions, the pitch
  detector, and the display smoother. No AVFoundation, no SwiftUI. Every type
  here is a deterministic function over plain values, so it's tested against
  *synthesized* waveforms with no audio hardware. Coverage-gated at 80%.
- **`TunerKit`** — `AudioInput` (AVAudioEngine), the view model, and the SwiftUI
  views. Needs a real microphone and a UI to exercise, so it's coverage-ignored
  wholesale.

**Keep logic in `TunerCore`.** That's what makes the gate meaningful — the
detector bugs found during the initial build (see below) were all caught by
`swift test` in under a tenth of a second, with no device involved.

### Structure

```text
tuner/
├── project.yml                  XcodeGen spec (iOS + macOS app targets)
├── Scripts/generate.sh          Regenerates the .xcodeproj (refuses if THIS project is open in Xcode)
├── Sources/{iOS,macOS}/         Thin @main app shells + Info.plist + entitlements
├── Sources/Shared/              Assets shared by both targets (the AppIcon set)
└── Packages/TunerCore/          Swift package — most of the code
    ├── Sources/TunerCore/       Pure logic: DSP + music theory, tested + coverage-gated
    │   ├── DSP/                 PitchDetector (MPM), Detection constants, ReadingSmoother
    │   └── Music/               Pitch/Note/ReferencePitch, Instrument
    └── Sources/TunerKit/        AVFoundation + SwiftUI, depends on Core; coverage-ignored
        ├── Audio/AudioInput.swift
        ├── App/                 Settings, LaunchStores
        └── Tuner/               TunerViewModel, TunerView
```

### How detection works, and why

**MPM (McLeod Pitch Method)**: a normalized square difference function over the
frame, then peak-picking with parabolic interpolation. Chosen over an FFT peak
because bowed and plucked strings put more energy in their harmonics than in the
fundamental — the tallest FFT bin is routinely the 2nd or 3rd harmonic, which
reads as an octave error. Normalization makes the fundamental's peak the tallest
regardless of harmonic content.

Three things are load-bearing and were each a real bug during the initial build.
**Do not "simplify" any of them without running the detector tests:**

1. **The autocorrelation input must be zero-padded by `maxLag`.** `vDSP_convD`
   reads `filterLength + resultLength - 1` samples; without the padding it reads
   past the frame and the long lags (the low notes) come back as noise.
2. **The parabolic interpolation denominator is `y0 - 2·y1 + y2`.** Inverting
   that sign reflects the estimate about the sample, biasing every reading — a
   few cents at violin pitch, catastrophically at the top of the range.
3. **The peak scan skips only the *descending* slope from `nsdf(0)`.** A blanket
   "skip everything positive" swallows the fundamental whenever the searched band
   starts near it, leaving its octave as the first candidate. `minLag` also
   carries two samples of headroom for the same reason.

Peak selection takes the **shortest-lag peak that clears
`peakPickThreshold × globalMax`**, not the tallest. A periodic signal peaks again
at every multiple of its period; taking the tallest picks one arbitrarily and
reports an octave too low.

The detector's output is deliberately **unsmoothed** — it's the truth, and the
tests assert against it. `ReadingSmoother` (median-then-exponential, in cents)
stabilizes only the *display*.

## Commands

```sh
# Logic tests (no Xcode needed) — the fast inner loop
make test          # or: cd Packages/TunerCore && swift test

# Generate the Xcode project, then build an app target
make generate
make build-ios / make build-mac

# Build + launch
make run-iphone    # DEVICE="SE" / "17 Pro" to pick a simulator
make run-mac

# Local-only UI regression tests (XCUITest)
make uitest        # NOT run by CI
```

`swift build` on macOS only compiles the `#if os(macOS)` branch of platform
code — build the iOS target via `xcodebuild` to exercise the iOS branch.

**The simulator has no usable microphone.** It reports an input device and
delivers silence, so pitch detection cannot be evaluated there. Use the
simulator for layout and navigation; verify detection on a real device. The UI
tests are written to this constraint — they assert on the status/idle states,
never on a live reading.

### Lint & format

```sh
swiftlint lint --strict                 # style + light correctness (.swiftlint.yml)
swift format lint --strict --recursive --configuration .swift-format \
  Packages/TunerCore/Sources Packages/TunerCore/Tests Sources
swift format --in-place --recursive --configuration .swift-format <paths>
```

**Run SwiftLint from the repo root.** Its `excluded:` paths resolve relative to
the invocation directory, so running it from inside `Packages/TunerCore` lints
the generated `.build` artifacts and reports dozens of false violations.

CI runs both with `--strict` (warnings fail). **swift-format is the authority on
whitespace/punctuation**; where SwiftLint conflicts (trailing commas, brace
placement) those SwiftLint rules are disabled rather than fought. Run the
formatter before committing.

**SwiftLint is pinned to a specific version** (`SWIFTLINT_VERSION` in
`.github/workflows/ci.yml`, currently **0.65.0**) so CI and local runs agree — an
unpinned `brew install` follows the rolling latest, so a new release can turn CI
red on untouched code. Bump the CI version deliberately and update this line.
swift-format needs no pin — it ships with the Xcode toolchain, which CI pins via
`XCODE_VERSION`.

## Pull requests & CI

Branch off `main`, one focused change per PR (details in
[CONTRIBUTING.md](CONTRIBUTING.md)). Agent-specific mechanics on top of that:

- **Commit trailer:** end commit messages with a
  `Co-Authored-By: <model> <noreply@anthropic.com>` line.
- **A user-facing PR writes its own CHANGELOG bullet** under
  `### Unreleased (next build)` — the release lane only stamps the build number,
  it never writes entries.
- **The whole TunerKit target is coverage-ignored** (the capture + SwiftUI
  layer). Keep testable logic OUT of it — it belongs in TunerCore, where it's
  tracked. Target is 80% on new, non-ignored code.

## Conventions

- **Comments minimal:** explain only what isn't obvious from the code. No
  historical / roadmap ("lands later") narration in source — that goes in commit
  messages. The DSP is the exception: the non-obvious invariants above are worth
  the lines, because each one silently produces *plausible* wrong answers.
- **Never analyse on the audio thread.** The tap callback copies into the ring
  buffer and returns; DSP runs on `analysisQueue`. The render thread has a hard
  real-time deadline.
- **Never assume the hardware sample rate.** It's 48 kHz on most Macs, 44.1 or 48
  on iPhones; `AudioInput` converts to a fixed rate and the detector is built for
  the converted one.
- **Everything persisted goes through `LaunchStores.defaults`**, never
  `UserDefaults.standard` — that's what makes the `-uitest-clean` isolation gate
  total rather than partial.
- Use `.onChangeCompat` rather than `onChange` (iOS 16 floor vs the macOS 14
  deprecation — neither overload is clean on both).
- `.vscode/` is gitignored and must not be pushed.

### String catalogs (`.xcstrings`)

Only English ships today. The catalogs and `defaultLocalization: "en"` exist so
adding a locale is a translation task, not a refactor — so **user-facing strings
must go through the catalog** (`Text(..., bundle: .module)`) even while there's
one language.

- **Xcode's serialized form is canonical** (spaced colons, 2-space indent).
  After any scripted/CLI edit, normalize before committing:
  `plutil -convert json -r -o FILE FILE`.
- **Renaming a key must update its explicit `en` unit too.** An entry carrying an
  `en` localization has that value *override* the key at runtime; renaming the
  key while keeping the old unit leaves English silently showing the old text.
- Localize the **concept**, not the word — each locale by a native ear.

## Gotchas

- SourceKit in-IDE diagnostics may report `No such module 'TunerCore'` for files
  it hasn't indexed — these are **false**. The authoritative checks are
  `swift build` / `swift test` / `xcodebuild`.
- `Scripts/embed-commit-sha.sh` writes `unknown` for a repo with no commits yet
  (fresh `git init`) as well as for a non-git checkout. Both must not fail the
  build — this bit the very first build of this project.
- macOS needs BOTH `com.apple.security.device.audio-input` (sandbox) and
  `NSMicrophoneUsageDescription` (consent) to capture. Line-in and audio
  interfaces are gated behind the same microphone permission as the built-in mic.
- iOS sets `AVAudioSession` mode `.measurement` deliberately: it disables the
  AGC/EQ/noise-suppression that voice modes apply, all of which distort the
  harmonic content the detector depends on.
