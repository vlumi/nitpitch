# Tuner

An instrument tuner for iPhone, iPad, and Mac. Built for **violin** first —
that's the reason it exists — with the other string instruments along for the
ride.

> **⚠️ The name is a placeholder.** "Tuner" is neither distinctive nor
> registrable, and it's invisible in App Store search. Picking the real name is
> the first open item in [ROADMAP.md](ROADMAP.md); nothing ships until it's
> settled.

## What it does

- Shows the note you're playing, how far off you are in cents, and a needle.
- **Sub-cent accuracy** across the range, which is what tuning actually needs —
  a cent at A4 is about a quarter of a hertz.
- **No octave errors.** Bowed and plucked strings put more energy into their
  harmonics than their fundamental, which is what makes naive tuners jump an
  octave; the detector is built to resolve that (see below).
- **Adjustable reference pitch**, A=390 through 466. Defaults to A=440;
  European orchestras commonly sit at 442 or 443.
- **Nothing leaves the device.** Audio is analysed frame by frame in memory and
  discarded. No recording, no network — the macOS build doesn't even carry the
  network entitlement, so the sandbox enforces it rather than merely documenting
  it.

Supported: violin, viola, cello, double bass, guitar, bass guitar, and a
chromatic mode.

### Why a Mac version

Electric instruments are easier to tune over a cable than through the air. A
guitar or bass going into an audio interface or DI gives the detector a clean,
loud signal with no room in the way — much better than a phone microphone
listening to an amp across the room.

## How it works

Pitch detection is the whole app; the rest is presentation. It uses the
**McLeod Pitch Method** — a normalized square difference function over a
4096-sample window (~93 ms at 44.1 kHz), then parabolic interpolation on the
chosen peak.

FFT peak-picking, the obvious approach, fails on exactly this problem: string
instruments routinely put their strongest partial an octave or two above the
fundamental, so the tallest bin is the wrong answer. Normalizing the
autocorrelation makes the fundamental's peak the tallest regardless of harmonic
content, and choosing the *shortest-lag* qualifying peak rather than the tallest
resolves what's left. Cent-level resolution comes from interpolating between
samples, so a ~93 ms window is enough — no multi-second buffer, no laggy needle.

Frames that aren't confidently periodic — bow noise, room reflections, the gap
between notes — are gated out by a clarity threshold rather than displayed, and
the readout says "play a note" instead of flickering.

Everything above is first-party: **Accelerate/vDSP** for the DSP,
**AVFoundation** for capture, **SwiftUI** for the view. There are no third-party
runtime dependencies.

## Development

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated and gitignored.

```sh
make test          # logic tests — the fast inner loop, no Xcode project needed
make generate      # regenerate Tuner.xcodeproj from project.yml
make run-iphone    # build + launch on a simulator (DEVICE="SE" to pick)
make run-mac       # build + launch the Mac app
make uitest        # local-only UI tests (CI never runs these)
make               # list every target
```

**Use `make run-mac` to hear detection actually working** — it's real capture on
real hardware, and the fastest way to check the app against an instrument. The
iOS simulator reports a microphone but delivers silence, so it's good for layout
and navigation only. Confirm on an iPhone before shipping: the iOS audio-session
and permission code never compiles into a Mac build.

The detector itself is verified headlessly against synthesized waveforms
(`swift test`, ~0.1 s), which is why the pure DSP lives in its own module. See
[AGENTS.md](AGENTS.md) for the architecture, the invariants that are easy to
break, and the contributor guide.

## AI assistance

This project is developed with AI coding assistance. The DSP is
tested against known-frequency signals precisely because plausible-looking pitch
code can be wrong in ways that are invisible by inspection — three such bugs
were caught by those tests during the initial build.

## License

[MIT](LICENSE).
