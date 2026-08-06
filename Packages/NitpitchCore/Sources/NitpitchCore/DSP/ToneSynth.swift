import Foundation

/// The reference tone's waveform: a pure sine — the tuning fork's voice —
/// with a short amplitude ramp at both ends so starting and stopping click
/// nothing. Pure state advanced one sample at a time, so the rules are
/// testable as arithmetic; the audio engine wrapper (`ToneGenerator`) owns
/// threads and sessions.
public struct ToneSynth {
    public let sampleRate: Double
    /// Hertz. Changes are phase-continuous — retuning mid-note (swiping to
    /// the next string while the tone sounds) glides rather than clicks.
    public var frequency: Double
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

    public init(sampleRate: Double, frequency: Double) {
        self.sampleRate = sampleRate
        self.frequency = frequency
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
        let sample = sin(phase) * amplitude
        phase += 2 * .pi * frequency / sampleRate
        if phase > 2 * .pi { phase -= 2 * .pi }
        return Float(sample)
    }
}
