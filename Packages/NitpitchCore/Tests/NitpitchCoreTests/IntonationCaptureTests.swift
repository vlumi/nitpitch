import XCTest

@testable import NitpitchCore

/// The capture's gating rules, as arithmetic — pure state, no audio, so
/// every rule is a scripted frame sequence.
final class IntonationCaptureTests: XCTestCase {

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
}
