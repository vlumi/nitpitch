import NitpitchCore
import XCTest

@testable import NitpitchData
@testable import NitpitchKit

/// The demo is the real pipeline hearing a synthetic signal — so the signal
/// itself carries the promises: a pose means those exact pitches, and the
/// detector must read them back to sub-cent accuracy or a "staged" screenshot
/// would quietly lie.
final class DemoSignalTests: XCTestCase {
    // MARK: - The pose language

    func testAPoseParses() throws {
        let score = try XCTUnwrap(DemoScore.parse("62,69@-1.8"))

        XCTAssertEqual(score.steps.count, 1)
        XCTAssertNil(score.steps[0].duration, "no duration = held forever")
        XCTAssertEqual(score.steps[0].voices.map(\.midi), [62, 69])
        XCTAssertEqual(score.steps[0].voices.map(\.cents), [0, -1.8])
    }

    func testASequenceParses() throws {
        let score = try XCTUnwrap(DemoScore.parse("1.5:55@-1.6;67@5.8"))

        XCTAssertEqual(score.steps.map(\.duration), [1.5, nil])
        XCTAssertEqual(score.steps.flatMap(\.voices).map(\.midi), [55, 67])
    }

    /// Refusal, not best-effort: a mistyped pose in a screenshot session
    /// must fail the launch (see `LaunchStores.audioInput`), never drift.
    func testGarbagePosesAreRefused() {
        for pose in [
            "",
            "sixty-nine",  // not a number
            "69@",  // dangling cents
            "69@2;62",  // an undurated step that isn't last
            "0:69",  // a zero-length step
            "69@250",  // a "cent offset" past any tuning error
            "12",  // below the detectable range
            "55,62,69",  // more voices than a double stop
        ] {
            XCTAssertNil(DemoScore.parse(pose), pose)
        }
    }

    /// The built-in drift score is data, so a typo in it is a launch-time
    /// crash in demo mode only — pin that it parses and covers the three
    /// elements the screens (and their UI tests) wait for.
    func testTheDriftScoreCarriesEveryElement() {
        let steps = DemoScore.drift.steps

        XCTAssertEqual(steps.compactMap(\.duration).count, steps.count, "it loops")
        XCTAssertLessThanOrEqual(
            steps.compactMap(\.duration).reduce(0, +), 4.0,
            "the UI tests allow 5 seconds; a longer loop flakes them")
        XCTAssertTrue(steps.contains { $0.voices.count == 2 }, "a double stop")
        let midis = steps.flatMap(\.voices).map(\.midi)
        XCTAssertTrue(
            midis.contains { midi in midis.contains(midi + 12) },
            "an open string and its octave, for the intonation delta")
    }

    // MARK: - The signal the detector hears

    /// Windows exactly as `DemoSignalInput` delivers them: sliding by
    /// `hopSize`, not butted end to end — the spectral engine reads
    /// frequency from phase advance between CONSECUTIVE HOPS, so the
    /// spacing is part of the contract.
    private func windows(pose: String, count: Int) -> [[Float]] {
        var signal = DemoSignal(score: DemoScore.parse(pose)!, sampleRate: 44100)
        // Skip the attack: amplitude eases in over ~20 ms, and the first
        // window spans it — the detector's territory is the steady state.
        _ = signal.render(count: Detection.windowSize)
        var window = signal.render(count: Detection.windowSize)
        var out = [window]
        for _ in 1..<count {
            window.removeFirst(Detection.hopSize)
            window += signal.render(count: Detection.hopSize)
            out.append(window)
        }
        return out
    }

    /// A pinned pose reads back at its exact cents — through the real
    /// detector, not a display shortcut. This is the fidelity the whole
    /// swap exists for.
    func testTheDetectorReadsAPoseBack() throws {
        let detector = PitchDetector(sampleRate: 44100)
        let expected = 440 * pow(2, 2.0 / 1200)

        for window in windows(pose: "69@2", count: 3) {
            let hz = try XCTUnwrap(detector.analyze(window).frequency)
            let cents = 1200 * log2(hz / expected)
            XCTAssertEqual(cents, 0, accuracy: 0.5, "the pose IS the pitch")
        }
    }

    /// Frequency changes are chirps on one running phase, never seams: the
    /// spectral engine measures phase advance BETWEEN windows, so a step
    /// boundary that reset phase would read as garbage. Render across a
    /// boundary and the detector must stay locked on the new pitch.
    func testStepChangesKeepThePhaseContinuous() throws {
        var signal = DemoSignal(
            score: DemoScore.parse("0.1:55;69")!, sampleRate: 44100)
        // 0.1 s = 4410 samples: the first window straddles the step change,
        // the next is pure A4.
        _ = signal.render(count: Detection.windowSize)
        _ = signal.render(count: Detection.windowSize)
        let settled = signal.render(count: Detection.windowSize)

        let detector = PitchDetector(sampleRate: 44100)
        let hz = try XCTUnwrap(detector.analyze(settled).frequency)
        XCTAssertEqual(1200 * log2(hz / 440), 0, accuracy: 0.5)
    }

    /// Both voices of a double stop are really in the signal, read the way
    /// the grid reads them — the spectral bank, since MPM is monophonic by
    /// construction. The violin's own targets and bands, D and A sounding
    /// together, and each string's slot answers with its own note.
    func testADoubleStopCarriesBothVoices() throws {
        let violin = Instrument.violin
        let bank = DetectorBank(
            sampleRate: 44100,
            targets: violin.notes.map { $0.frequency(reference: .standard) },
            bands: violin.stringBands())
        let expectedA = 440 * pow(2, -1.8 / 1200)

        // The spectral engine needs consecutive windows (frequency is read
        // from phase ADVANCE), so results firm up after the first.
        var found = (d: false, a: false)
        for window in windows(pose: "62,69@-1.8", count: 6) {
            let results = bank.analyze(window)
            if let d = results[1].frequency, abs(1200 * log2(d / 293.665)) < 1 {
                found.d = true
            }
            if let a = results[2].frequency, abs(1200 * log2(a / expectedA)) < 1 {
                found.a = true
            }
        }
        XCTAssertTrue(found.d, "the D string's slot heard its note")
        XCTAssertTrue(found.a, "the A string's slot heard its note, 1.8¢ low")
    }
}
