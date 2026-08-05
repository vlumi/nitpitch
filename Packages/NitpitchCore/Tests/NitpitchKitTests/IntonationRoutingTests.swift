import XCTest

@testable import NitpitchCore
@testable import NitpitchKit

/// The per-frame decision between the two tuners, as arithmetic. The field
/// case that forced the proximity rule: a bass A1 (55 Hz, one FFT bin), where
/// spectral fails its gates often, MPM finds the octave at 110 Hz, and parity
/// — which rides the same spectral gates — is silent on exactly those frames.
final class IntonationRoutingTests: XCTestCase {
    private let a1 = 55.0

    private func reading(_ hz: Double) -> DetectionResult {
        DetectionResult(frequency: hz, clarity: 0.95, rms: 0.1, level: 0.8)
    }

    private func octaveFrame(cents: Double) -> IntonationAnalyzer.Frame {
        IntonationAnalyzer.Frame(
            sounding: .note(slot: .octave, cents: cents, clarity: 1), level: 0.5)
    }

    private var nothingFrame: IntonationAnalyzer.Frame {
        IntonationAnalyzer.Frame(sounding: .nothing, level: 0.1)
    }

    /// Parity spoke: the bank's spectral misread (a fretted 12th anchored at
    /// even harmonics reads ≈0¢ on the open target) must not reach the dial.
    func testParityOctaveSilencesTheDialAndPassesTheFrame() {
        let routed = IntonationRouting.route(
            result: reading(a1 * 1.002),  // the misread: "open, +3¢"
            frame: octaveFrame(cents: 4.6),
            target: a1)
        XCTAssertNil(routed.dial.frequency, "the misread must not light the dial")
        XCTAssertEqual(routed.intonation, octaveFrame(cents: 4.6))
    }

    /// Parity silent, MPM found 2f: the frame is the octave's business —
    /// rerouted with its cents against 2f, never +1200 on the main dial.
    func testProximityReroutesAnMPMOctaveReading() {
        let sharpOctave = 2 * a1 * pow(2, 4.0 / 1200)
        let routed = IntonationRouting.route(
            result: reading(sharpOctave), frame: nothingFrame, target: a1)
        XCTAssertNil(routed.dial.frequency, "+1204 must not slam the dial")
        guard case .note(let slot, let cents, _) = routed.intonation?.sounding else {
            return XCTFail("the reading should become an octave frame")
        }
        XCTAssertEqual(slot, .octave)
        XCTAssertEqual(cents, 4, accuracy: 0.1)
    }

    /// A nil analyzer frame (mode inactive, in principle) with a 2f reading
    /// still reroutes — proximity doesn't need the analyzer at all.
    func testProximityWorksWithoutAnAnalyzerFrame() {
        let routed = IntonationRouting.route(
            result: reading(2 * a1), frame: nil, target: a1)
        XCTAssertNil(routed.dial.frequency)
        XCTAssertNotNil(routed.intonation)
    }

    /// The ordinary case passes through untouched: open-string reading to
    /// the dial, the analyzer's frame (whatever it says) to the monitor.
    func testAnOpenReadingPassesThrough() {
        let nearOpen = a1 * pow(2, -7.0 / 1200)
        let routed = IntonationRouting.route(
            result: reading(nearOpen), frame: nothingFrame, target: a1)
        XCTAssertEqual(routed.dial.frequency, nearOpen)
        XCTAssertEqual(routed.intonation, nothingFrame)
    }

    /// A neighbour string (a fifth up, +700¢) is NOT the octave: it stays on
    /// the dial and pins, which is this screen's contract for wrong notes.
    func testAFifthIsNotTheOctave() {
        let fifth = a1 * pow(2, 700.0 / 1200)
        let routed = IntonationRouting.route(
            result: reading(fifth), frame: nothingFrame, target: a1)
        XCTAssertNotNil(routed.dial.frequency)
        XCTAssertEqual(routed.intonation, nothingFrame)
    }

    /// The window's edges: just inside reroutes, just outside stays.
    func testTheOctaveWindowBinds() {
        let inside = a1 * pow(2, (1200 + IntonationRouting.octaveWindowCents - 1) / 1200)
        let outside = a1 * pow(2, (1200 + IntonationRouting.octaveWindowCents + 1) / 1200)
        XCTAssertNil(
            IntonationRouting.route(
                result: reading(inside), frame: nil, target: a1
            ).dial.frequency)
        XCTAssertNotNil(
            IntonationRouting.route(
                result: reading(outside), frame: nil, target: a1
            ).dial.frequency)
    }

    /// Silence routes as silence — no reading, no synthesis, frame passed.
    func testSilencePassesThrough() {
        let silent = DetectionResult(frequency: nil, clarity: 0.1, rms: 0.001)
        let routed = IntonationRouting.route(
            result: silent, frame: nothingFrame, target: a1)
        XCTAssertNil(routed.dial.frequency)
        XCTAssertEqual(routed.intonation, nothingFrame)
    }
}
