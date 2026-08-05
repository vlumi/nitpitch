import XCTest

@testable import NitpitchCore

/// The intonation check rests on one physical claim — parity: an open string
/// always brings odd partials, a note an octave up sounds even slots only.
/// Verified the way the estimator itself is: synthesized waveforms, no audio
/// hardware. The capture's gating rules are pure state and tested as such.
final class IntonationTests: XCTestCase {
    private let sampleRate = 44100.0

    /// A harmonically rich tone the way a plucked string is.
    private func tone(
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

    private func detuned(_ hz: Double, cents: Double) -> Double {
        hz * pow(2, cents / 1200)
    }

    /// Run a signal through an analyzer as `AudioInput` would deliver it:
    /// hop-consecutive windows, all frames collected.
    private func frames(
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

    private func signalLength(hops: Int) -> Int {
        Detection.windowSize + hops * Detection.hopSize
    }

    // MARK: - Classification: the parity claim

    func testClassifiesTheOpenString() {
        let g3 = 196.0
        let signal = tone(detuned(g3, cents: -7), count: signalLength(hops: 3))
        let sounded = frames(of: signal, target: g3, hops: 3).compactMap(\.note)
        XCTAssertFalse(sounded.isEmpty, "an open string must be heard")
        for (slot, cents) in sounded {
            XCTAssertEqual(slot, .open)
            XCTAssertEqual(cents, -7, accuracy: 1)
        }
    }

    /// The fretted 12th (or the fingered octave): partials at 2f, 4f, 6f —
    /// exclusively even slots of the open target — and its cents measured
    /// against 2f, on the same scale the open string uses against f.
    func testClassifiesTheOctave() {
        let g3 = 196.0
        let signal = tone(
            detuned(2 * g3, cents: 6), count: signalLength(hops: 3),
            harmonics: [1.0, 0.6, 0.4])
        let sounded = frames(of: signal, target: g3, hops: 3).compactMap(\.note)
        XCTAssertFalse(sounded.isEmpty, "the octave must be heard")
        for (slot, cents) in sounded {
            XCTAssertEqual(slot, .octave)
            XCTAssertEqual(cents, 6, accuracy: 1)
        }
    }

    /// A phone microphone rolls off a bass low E's fundamental — the note
    /// arrives with orders 2...6 and nothing at f. Order 3 is odd evidence,
    /// so parity still says open; a missing fundamental must never read as
    /// a fretted octave.
    func testRolledOffFundamentalIsStillTheOpenString() {
        let e2 = 82.4
        let signal = tone(
            detuned(e2, cents: 4), count: signalLength(hops: 3),
            harmonics: [0.0, 1.0, 0.8, 0.5, 0.3, 0.2])
        let sounded = frames(of: signal, target: e2, hops: 3).compactMap(\.note)
        XCTAssertFalse(sounded.isEmpty)
        for (slot, cents) in sounded {
            XCTAssertEqual(slot, .open)
            XCTAssertEqual(cents, 4, accuracy: 1)
        }
    }

    func testSilenceSoundsNothing() {
        let silence = [Float](repeating: 0, count: signalLength(hops: 2))
        for frame in frames(of: silence, target: 196, hops: 2) {
            XCTAssertEqual(frame.sounding, .nothing)
        }
    }

    func testInactiveAnswersNil() {
        let analyzer = IntonationAnalyzer(sampleRate: sampleRate, target: 196)
        let window = tone(196, count: Detection.windowSize)
        XCTAssertNil(analyzer.analyze(window))
    }

    // MARK: - Capture: the gating rules, as arithmetic

    private func note(
        _ slot: IntonationSlot, _ cents: Double
    ) -> IntonationAnalyzer.Frame {
        IntonationAnalyzer.Frame(
            sounding: .note(slot: slot, cents: cents, clarity: 1), level: 0.5)
    }

    private var nothing: IntonationAnalyzer.Frame {
        IntonationAnalyzer.Frame(sounding: .nothing, level: 0)
    }

    func testAStableRunRecordsItsMedian() {
        var capture = IntonationCapture()
        for cents in [-2.0, -1.5, -2.5, -2.0, -1.8, -2.2] {
            capture.ingest(note(.open, cents))
        }
        XCTAssertEqual(capture.open ?? .nan, -2.0, accuracy: 0.11)
        XCTAssertNil(capture.octave)
    }

    func testAWobblingRunRecordsNothing() {
        var capture = IntonationCapture()
        for cents in [-2.0, 3.0, -1.0, 4.0, -3.0, 2.0] {
            capture.ingest(note(.open, cents))
        }
        XCTAssertNil(capture.open, "a spread past the window is a note still settling")
    }

    /// A decaying note hovers at the strength gate and flickers
    /// note/nothing — a brief dropout must not restart the clock.
    func testABriefDropoutDoesNotBreakARun() {
        var capture = IntonationCapture()
        for _ in 0..<5 { capture.ingest(note(.open, -2)) }
        for _ in 0..<IntonationCapture.quietGraceFrames { capture.ingest(nothing) }
        capture.ingest(note(.open, -2))
        XCTAssertEqual(capture.open ?? .nan, -2, accuracy: 0.01)
    }

    func testSustainedSilenceBreaksARun() {
        var capture = IntonationCapture()
        for _ in 0..<5 { capture.ingest(note(.open, -2)) }
        for _ in 0..<(IntonationCapture.quietGraceFrames + 1) { capture.ingest(nothing) }
        capture.ingest(note(.open, -2))
        XCTAssertNil(capture.open, "past the grace, the run starts over")
    }

    /// An outlier costs one extra frame of evidence, never a restart: the
    /// lock waits for `stableFrames` inliers around the run's median, and
    /// the recorded value is the median of the inliers alone.
    func testAnOutlierDelaysTheLockByOneFrameAndLeavesNoTrace() {
        var capture = IntonationCapture()
        for cents in [-2.0, -1.8, -2.2, 6.0, -2.0, -1.9] {
            capture.ingest(note(.open, cents))
        }
        XCTAssertNil(capture.open, "five inliers are not yet a consensus")
        capture.ingest(note(.open, -2.1))
        XCTAssertEqual(capture.open ?? .nan, -2.0, accuracy: 0.1)
    }

    /// A picked bass note: wobbly attack, wild frames scattered through a
    /// decaying pluck — the run collects evidence wherever it lands, and
    /// the outliers are discarded rather than given a veto.
    func testAScatteredPluckStillLocks() {
        var capture = IntonationCapture()
        let pluck = [6.0, -2.0, -1.8, 7.0, -2.2, -2.0, -8.0, -1.9, -2.1]
        for cents in pluck { capture.ingest(note(.open, cents)) }
        XCTAssertEqual(capture.open ?? .nan, -2.0, accuracy: 0.15)
    }

    func testASlotSwitchStartsANewRun() {
        var capture = IntonationCapture()
        for _ in 0..<5 { capture.ingest(note(.open, -2)) }
        for _ in 0..<6 { capture.ingest(note(.octave, 6)) }
        XCTAssertNil(capture.open, "five open frames never completed a run")
        XCTAssertEqual(capture.octave ?? .nan, 6, accuracy: 0.01)
    }

    /// A re-play after a saddle adjustment: the pause between plucks
    /// outlives the quiet grace, so the old evidence is gone and the new
    /// run speaks alone.
    func testTheLatestStableRunWins() {
        var capture = IntonationCapture()
        for _ in 0..<6 { capture.ingest(note(.octave, 6)) }
        for _ in 0..<(IntonationCapture.quietGraceFrames + 1) { capture.ingest(nothing) }
        for _ in 0..<6 { capture.ingest(note(.octave, 3)) }
        XCTAssertEqual(capture.octave ?? .nan, 3, accuracy: 0.01)
    }

    func testDeltaIsOctaveAgainstOpenPromise() {
        var capture = IntonationCapture()
        XCTAssertNil(capture.delta)
        for _ in 0..<6 { capture.ingest(note(.open, -2)) }
        XCTAssertNil(capture.delta, "one sample is not a comparison")
        capture.ingest(nothing)
        for _ in 0..<6 { capture.ingest(note(.octave, 6)) }
        XCTAssertEqual(capture.delta ?? .nan, 8, accuracy: 0.01)
    }

    func testResetForgetsEverything() {
        var capture = IntonationCapture()
        for _ in 0..<6 { capture.ingest(note(.open, -2)) }
        capture.reset()
        XCTAssertNil(capture.open)
        XCTAssertNil(capture.delta)
    }

    // MARK: - End to end: signal in, samples out

    func testAHeldOctaveReachesTheCapture() {
        let g3 = 196.0
        let hops = IntonationCapture.stableFrames + 3
        let signal = tone(
            detuned(2 * g3, cents: 9), count: signalLength(hops: hops),
            harmonics: [1.0, 0.6, 0.4])
        var capture = IntonationCapture()
        for frame in frames(of: signal, target: g3, hops: hops) {
            capture.ingest(frame)
        }
        XCTAssertEqual(capture.octave ?? .nan, 9, accuracy: 1)
    }
}

extension IntonationAnalyzer.Frame {
    /// The sounding note's parts, for terse assertions.
    fileprivate var note: (slot: IntonationSlot, cents: Double)? {
        guard case .note(let slot, let cents, _) = sounding else { return nil }
        return (slot, cents)
    }
}
