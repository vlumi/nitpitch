import Foundation

/// The reference tone's waveform: a pure sine — the tuning fork's voice —
/// with a short amplitude ramp at both ends so starting and stopping click
/// nothing. Pure state advanced one sample at a time, so the rules are
/// testable as arithmetic; the audio engine wrapper (`ToneGenerator`) owns
/// threads and sessions.
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
    /// playing underneath.
    public static let playingAmplitude = 0.3
    /// Envelope slope per second of audio: full scale in ~30 ms.
    public static let rampPerSecond = 10.0
    /// Glide speed: a fifth (700¢) crossed in 70 ms.
    public static let glideCentsPerSecond = 10_000.0

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
            let stepCents = Self.glideCentsPerSecond / sampleRate
            let diffCents = 1200 * log2(targetFrequency / frequency)
            if abs(diffCents) <= stepCents {
                frequency = targetFrequency
            } else {
                frequency *= pow(2, (diffCents > 0 ? stepCents : -stepCents) / 1200)
            }
        }
        let sample = sin(phase) * amplitude
        phase += 2 * .pi * frequency / sampleRate
        if phase > 2 * .pi { phase -= 2 * .pi }
        return Float(sample)
    }
}
