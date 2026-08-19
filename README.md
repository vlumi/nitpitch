# Nitpitch

[![CI](https://github.com/vlumi/nitpitch/actions/workflows/ci.yml/badge.svg)](https://github.com/vlumi/nitpitch/actions/workflows/ci.yml) [![codecov](https://codecov.io/gh/vlumi/nitpitch/branch/main/graph/badge.svg)](https://codecov.io/gh/vlumi/nitpitch)

A tuner for violin, guitar, bass, and more — on iPhone, iPad, Mac, and Apple Watch. Born **violin**-first, for the way string players actually tune, and every bit as at home on a guitar or bass.

*Nitpicking about pitch, which is the entire job.*

## What it does

- Shows the note you're playing, how far off you are in cents, and a needle.
- **Sub-cent accuracy** across the range, which is what tuning actually needs — a cent at A4 is about a quarter of a hertz.
- **No octave errors.** Bowed and plucked strings put more energy into their harmonics than their fundamental, which is what makes naive tuners jump an octave; the detector is built to resolve that (see below).
- **A dial per string.** Choose an instrument and every string gets its own dial, lit only by pitches near its own target — including **two strings bowed at once**, which is how violinists actually tune.
- **Adjustable reference pitch**, A=390 through 466, a hertz at a time. Defaults to A=440; European orchestras commonly sit at 442 or 443, and baroque ensembles at 415.
- **Instruments you own.** Each remembers its tuning, reference and padlock exactly as you left it; favorites sit on the launch screen with one-tap preset pins ("Strat → Gig"), and any shape can be strung up — a 9-string guitar is a creation choice, not a missing feature.
- **A tuner on the wrist.** The Apple Watch app tunes with its own microphone and speaks in haptics: taps at the string's real beat rate against its target — faster means further off, silence means in tune, the arc gives direction at a glance — so tuning never needs eyes. Ships inside the iPhone app and stands alone in the watch's App Store; setups arrive over iCloud sync.
- **Nothing leaves the device — unless you enable iCloud sync.** Audio is analyzed frame by frame in memory and discarded, always: no recording, and the app itself makes no network connections — the macOS build doesn't even carry the network entitlement, so the sandbox enforces it rather than merely documenting it. An opt-in switch (off by default) syncs your instruments, presets and favorites between your own devices through your iCloud account; audio is never part of it.

Supported: violin, viola, cello, double bass, guitar, bass guitar, and a chromatic mode.

### Why a Mac version

Electric instruments are easier to tune over a cable than through the air. A guitar or bass going into an audio interface or DI gives the detector a clean, loud signal with no room in the way — much better than a phone microphone listening to an amp across the room.

## How it works

Pitch detection is the whole app; the rest is presentation. It uses the **McLeod Pitch Method** — a normalized square difference function over a 4096-sample window (~93 ms at 44.1 kHz), then parabolic interpolation on the chosen peak.

FFT peak-picking, the obvious approach, fails on exactly this problem: string instruments routinely put their strongest partial an octave or two above the fundamental, so the tallest bin is the wrong answer. Normalizing the autocorrelation makes the fundamental's peak the tallest regardless of harmonic content, and choosing the *shortest-lag* qualifying peak rather than the tallest resolves what's left. Cent-level resolution comes from interpolating between samples, so a ~93 ms window is enough — no multi-second buffer, no laggy needle.

Frames that aren't confidently periodic — bow noise, room reflections, the gap between notes — are gated out by a clarity threshold rather than displayed, and the readout says "play a note" instead of flickering.

The per-string dials add a second path: MPM is monophonic by construction, so an instrument's strings are measured **spectrally** — each string's frequency read from the phase advance of its own harmonics between analysis windows, which handles two strings at once and can't mistake one string's subharmonic for another. The two engines run as a hybrid: spectral wherever it has an answer, MPM to find a badly slack string it doesn't.

Everything above is first-party: **Accelerate/vDSP** for the DSP, **AVFoundation** for capture, **SwiftUI** for the view. There are no third-party runtime dependencies.

## Development

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The `.xcodeproj` is generated and gitignored.

```sh
make test          # logic tests — the fast inner loop, no Xcode project needed
make generate      # regenerate Nitpitch.xcodeproj from project.yml
make run-iphone    # build + launch on a simulator (DEVICE="SE" to pick)
make run-mac       # build + launch the Mac app
make demo-watch    # the watch app in a simulator, on a synthesized signal
make uitest        # local-only UI tests (CI never runs these)
make               # list every target
```

**Use `make run-mac` to hear detection actually working** — it's real capture on real hardware, and the fastest way to check the app against an instrument. The iOS simulator reports a microphone but delivers silence, so it's good for layout and navigation only. Confirm on an iPhone before shipping: the iOS audio-session and permission code never compiles into a Mac build.

The detector itself is verified headlessly against synthesized waveforms (`swift test`, ~0.1 s), which is why the pure DSP lives in its own module. See [AGENTS.md](AGENTS.md) for the architecture, the invariants that are easy to break, and the contributor guide.

## AI assistance

This project is developed with AI coding assistance. The DSP is tested against known-frequency signals precisely because plausible-looking pitch code can be wrong in ways that are invisible by inspection — three such bugs were caught by those tests during the initial build.

## Privacy

Nothing is recorded, and there is no third-party code in the app. Nothing is transmitted either, unless you turn on iCloud sync — an opt-in switch, off by default, that moves your instruments, presets and favorites between your own devices through Apple's iCloud; nothing derived from audio is ever part of it, and nothing ever reaches the developer. The app itself still makes no network connections: the macOS build runs sandboxed without the network entitlement (iCloud's system daemon does the moving), so that is enforced by the OS rather than merely promised. Full statement in [PRIVACY.md](PRIVACY.md).

## License

[MIT](LICENSE).
