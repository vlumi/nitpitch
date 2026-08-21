import Foundation

@testable import NitpitchCore

/// The synthesized-signal diet shared by the intonation test files:
/// tones the way a plucked string sounds, windows the way `AudioInput`
/// delivers them.
/// The intonation check rests on one physical claim — parity: an open string
/// always brings odd partials, a note an octave up sounds even slots only.
/// Verified the way the estimator itself is: synthesized waveforms, no audio
/// hardware. The capture's gating rules are pure state and tested as such.
let sampleRate = 44100.0

/// A harmonically rich tone the way a plucked string is.
func tone(
    _ hz: Double, count: Int,
    harmonics: [Double] = [0.3, 1.0, 0.8, 0.5, 0.3, 0.2]
) -> [Float] {
    let raw = (0..<count).map { i in
        let t = Double(i) / sampleRate
        var s = 0.0
        for (k, a) in harmonics.enumerated() {
            s += a * sin(2 * .pi * hz * Double(k + 1) * t)
        }
        return s
    }
    let peak = raw.map(abs).max() ?? 1
    return raw.map { Float($0 / max(peak, 1e-12) * 0.8) }
}

func detuned(_ hz: Double, cents: Double) -> Double {
    hz * pow(2, cents / 1200)
}

/// Run a signal through an analyzer as `AudioInput` would deliver it:
/// hop-consecutive windows, all frames collected.
func frames(
    of signal: [Float], target: Double, hops: Int
) -> [IntonationAnalyzer.Frame] {
    let analyzer = IntonationAnalyzer(
        sampleRate: sampleRate, target: target, tuning: .default)
    analyzer.setActive(true)
    return (0..<hops).compactMap { hop in
        let start = hop * Detection.hopSize
        return analyzer.analyze(Array(signal[start..<(start + Detection.windowSize)]))
    }
}

func signalLength(hops: Int) -> Int {
    Detection.windowSize + hops * Detection.hopSize
}

extension IntonationAnalyzer.Frame {
    /// The sounding note's parts, for terse assertions.
    var note: (slot: IntonationSlot, cents: Double)? {
        guard case .note(let slot, let cents, _) = sounding else { return nil }
        return (slot, cents)
    }
}
