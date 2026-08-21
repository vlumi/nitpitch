import XCTest

@testable import NitpitchCore

/// The intonation check as a player performs it, end to end: a plucked
/// guitar low E, a refinger, then the 12th fret — decaying amplitudes and
/// all, because the check's whole job is to survive them.
///
/// This exists because a round of guards that each passed their own
/// synthetic test made this scenario impossible in the field: the octave's
/// partials land on the OPEN target's even slots by construction (that is
/// the parity design — see AGENTS.md), so any guard that treats "the same
/// slots as before" as "nothing new" silently eats the octave. Keep this
/// test honest about amplitude: a fretted 12th is quieter than the open
/// pluck that preceded it, and both decay.
final class IntonationPluckTests: XCTestCase {
    func testAPluckedOpenThenTwelfthFretMeasuresTheSaddleError() {
        let e2 = 82.407
        let analyzer = IntonationAnalyzer(
            sampleRate: sampleRate, target: e2, tuning: .default)
        analyzer.setActive(true)

        // A plucked string: struck loud, decaying. The open pluck, a gap
        // while the hand refingers, then the 12th fret — quieter, as a
        // fretted note is.
        func pluck(_ hz: Double, count: Int, peak: Double, harmonics: [Double]) -> [Float] {
            let raw = tone(hz, count: count, harmonics: harmonics)
            return raw.enumerated().map { index, sample in
                let decay = exp(-Double(index) / (sampleRate * 1.2))
                return Float(Double(sample) * decay * peak)
            }
        }

        var signal: [Float] = []
        // Open E2: all partials, fundamental weak the way a pickup hears it.
        signal += pluck(
            e2, count: 44100, peak: 1.0,
            harmonics: [0.4, 1.0, 0.7, 0.5, 0.3, 0.2])
        signal += [Float](repeating: 0, count: 8192)
        // The 12th fret at 2f, 12 cents sharp: its partials are 2f, 4f, 6f,
        // which land on the OPEN target's even slots (orders 2, 4, 6).
        signal += pluck(
            2 * e2 * pow(2, 12.0 / 1200), count: 44100, peak: 0.5,
            harmonics: [1.0, 0.6, 0.4, 0.25, 0.15, 0.1])

        var capture = IntonationCapture()
        var slots: [IntonationSlot] = []
        var hop = 0
        while (hop * Detection.hopSize + Detection.windowSize) <= signal.count {
            let start = hop * Detection.hopSize
            let window = Array(signal[start..<(start + Detection.windowSize)])
            if let frame = analyzer.analyze(window) {
                capture.ingest(frame)
                if case .note(let slot, _, _) = frame.sounding {
                    slots.append(slot)
                }
            }
            hop += 1
        }
        XCTAssertTrue(slots.contains(.open), "the open pluck must record")
        XCTAssertTrue(
            slots.contains(.octave),
            "the 12th fret must record — its partials share the open's even slots")
        XCTAssertEqual(capture.open ?? .nan, 0, accuracy: 1.5, "the open string is on target")
        XCTAssertEqual(
            capture.octave ?? .nan, 12, accuracy: 2,
            "the octave carries the synthesized saddle error")
        XCTAssertEqual(capture.delta ?? .nan, 12, accuracy: 2, "so the verdict is that error")
    }
}
