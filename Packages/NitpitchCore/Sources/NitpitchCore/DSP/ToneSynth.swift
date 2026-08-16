import Foundation

/// The reference tone's waveform: a sine with a tail of harmonics, and a
/// short amplitude ramp at both ends so starting and stopping click
/// nothing. Pure state advanced one sample at a time, so the rules are
/// testable as arithmetic; the audio engine wrapper (`ToneGenerator`) owns
/// threads and sessions.
///
/// The harmonics are load-bearing, not tone color: a phone speaker cannot
/// reproduce a low string's fundamental at all (E2's 82 Hz, let alone a
/// bass E1), and a pure sine at low pitch is doubly cursed by the ear's
/// equal-loudness curves — the field verdict was "hard to hear even at max
/// volume". The overtones are what the speaker CAN produce, and the ear
/// reconstructs the pitch from them: the missing-fundamental effect, the
/// same reason a bass line survives a phone call.
public struct ToneSynth {
    public let sampleRate: Double
    /// Where the pitch is heading, in hertz. The sounding `frequency` GLIDES
    /// there — an instantaneous jump is phase-continuous but not
    /// slope-continuous, and that derivative kink is a broadband transient:
    /// the field report was "a cutting noise, pretty painful if the volume
    /// is up". The glide is cents-linear and fast (~70 ms across a fifth) —
    /// portamento, not a slide.
    public var targetFrequency: Double
    /// The pitch actually sounding right now.
    public private(set) var frequency: Double
    /// Where the envelope is heading: `playingAmplitude`, or 0 on the way
    /// out. The ramp covers ~30 ms — immediate to the ear, clickless to
    /// the waveform.
    public var targetAmplitude: Double = 0
    public private(set) var amplitude: Double = 0
    private var phase: Double = 0

    /// The playing level: clearly audible, comfortable over music left
    /// playing underneath. The partial weights below are normalized to sum
    /// to 1, so this is the true waveform peak — no clipping headroom
    /// games.
    public static let playingAmplitude = 0.8

    /// The harmonic recipe, fundamental first, normalized at render time.
    /// Enough overtone energy to carry a low note through a small
    /// speaker, decaying fast enough to stay a reference tone rather than
    /// an organ.
    public static let partials: [Double] = [1.0, 0.5, 0.35, 0.25]
    /// Envelope slope per second of audio: the playing level in ~30 ms.
    public static let rampPerSecond = 25.0
    /// The glide's time constant. Exponential rather than rate-limited: a
    /// linear glide made SMALL steps effectively instantaneous again — a
    /// ±1 Hz reference step is ~4¢, crossed in 0.4 ms, the same audible
    /// kink as no glide at all ("smaller ticks", the second field report).
    /// A one-pole approach in cents space is smooth at both ends for any
    /// step size: a fifth still lands in ~70 ms, a reference step spreads
    /// over ~40.
    public static let glideTimeConstant = 0.02
    /// Close enough to snap: the exponential's asymptote, cut off where no
    /// ear follows.
    public static let glideSnapCents = 0.05

    public init(sampleRate: Double, frequency: Double) {
        self.sampleRate = sampleRate
        self.frequency = frequency
        self.targetFrequency = frequency
    }

    /// Whether there's anything left to hear — false once a release ramp
    /// has fully landed, which is when the engine may stop.
    public var isAudible: Bool { amplitude > 0 || targetAmplitude > 0 }

    public mutating func nextSample() -> Float {
        let step = Self.rampPerSecond / sampleRate
        if amplitude < targetAmplitude {
            amplitude = min(targetAmplitude, amplitude + step)
        } else if amplitude > targetAmplitude {
            amplitude = max(targetAmplitude, amplitude - step)
        }
        if frequency != targetFrequency {
            let diffCents = PitchMath.cents(from: frequency, to: targetFrequency)
            if abs(diffCents) <= Self.glideSnapCents {
                frequency = targetFrequency
            } else {
                let pull = 1 - exp(-1 / (Self.glideTimeConstant * sampleRate))
                frequency *= pow(2, diffCents * pull / 1200)
            }
        }
        var sample = 0.0
        let norm = Self.partials.reduce(0, +)
        for (index, weight) in Self.partials.enumerated() {
            sample += sin(phase * Double(index + 1)) * weight / norm
        }
        sample *= amplitude
        phase += 2 * .pi * frequency / sampleRate
        if phase > 2 * .pi { phase -= 2 * .pi }
        return Float(sample)
    }
}
