import XCTest

@testable import NitpitchCore
@testable import NitpitchData
@testable import NitpitchKit

/// A retarget is a new string: every piece of frame-to-frame memory in the
/// dial's model describes the OLD string's last note, and each carried a
/// stale verdict across a swipe — the harmonic label opened on the
/// neighbour's claim, and the old string's "was reading open" flag vetoed
/// the new string's fresh octave as a decaying tail.
@MainActor
final class StringRetargetTests: XCTestCase {
    private func makeTuner() -> StringTunerViewModel {
        StringTunerViewModel(
            audio: AudioSessionController(), target: Note(midi: 55), band: 100...400)
    }

    private func reading(midi: Int, harmonic: Int = 1, evenOnly: Bool = false) -> DetectionResult {
        DetectionResult(
            frequency: Note(midi: midi).frequency(), clarity: 0.95, rms: 0.1, level: 0.8,
            evenPartialsOnly: evenOnly, harmonic: harmonic)
    }

    func testTheHarmonicLabelDoesNotSurviveASwipe() {
        let tuner = makeTuner()
        tuner.begin()
        for _ in 0..<4 { tuner.ingest(reading(midi: 55, harmonic: 2)) }
        XCTAssertEqual(tuner.harmonic, 2)

        // The label was the old string's claim; the new dial must open
        // clean, not under a neighbour's "· 2nd harmonic".
        tuner.retarget(Note(midi: 57))
        XCTAssertEqual(tuner.harmonic, 1, "a new target starts with no harmonic claim")
    }

    func testTheOldStringsOpenDoesNotVetoTheNewStringsOctave() {
        let tuner = makeTuner()
        tuner.setIntonating(true)
        tuner.begin()
        // The old string reads open right up to the swipe.
        for _ in 0..<4 { tuner.ingest(reading(midi: 55)) }

        tuner.retarget(Note(midi: 57))
        // The new string's first note is its octave — a fresh attack, not
        // the OLD string's decaying tail, which is the only thing the
        // "even-only continuing an open" rule exists to catch.
        tuner.ingest(reading(midi: 57, harmonic: 2, evenOnly: true))
        XCTAssertNotNil(
            tuner.octaveCents,
            "a stale was-reading-open flag must not eat the new string's octave")
    }
}
