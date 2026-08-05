import XCTest

@testable import NitpitchCore
@testable import NitpitchKit

/// The grid's intonation layer, at the view-model seam: parity-flagged
/// results route to the octave slot and stand the open display down; the
/// layer off means the status quo, untouched.
@MainActor
final class GridIntonationTests: XCTestCase {
    private func makeTuner() -> StringTunerViewModel {
        StringTunerViewModel(
            audio: AudioSessionController(), target: Note(midi: 55), band: 100...400)
    }

    private func result(cents: Double, even: Bool) -> DetectionResult {
        let hz = Note(midi: 55).frequency() * pow(2, cents / 1200)
        return DetectionResult(
            frequency: hz, clarity: 0.95, rms: 0.1, level: 0.8, evenPartialsOnly: even)
    }

    func testOctaveFramesFeedTheOctaveSlotAndStandTheDialDown() {
        let tuner = makeTuner()
        tuner.begin()
        tuner.setIntonating(true)
        for _ in 0..<8 { tuner.ingest(result(cents: 6, even: true)) }
        XCTAssertEqual(tuner.octaveSample ?? .nan, 6, accuracy: 0.2)
        XCTAssertEqual(tuner.octaveCents ?? .nan, 6, accuracy: 0.6)
        if case .reading = tuner.state {
            XCTFail("the open dial must not read the octave")
        }
    }

    func testOpenThenOctaveMakesADelta() {
        let tuner = makeTuner()
        tuner.begin()
        tuner.setIntonating(true)
        for _ in 0..<8 { tuner.ingest(result(cents: -2, even: false)) }
        XCTAssertEqual(tuner.openSample ?? .nan, -2, accuracy: 0.2)
        if case .reading(let cents, _) = tuner.state {
            XCTAssertEqual(cents, -2, accuracy: 0.5, "the open reading still tunes")
        } else {
            XCTFail("an open reading must reach the dial")
        }
        for _ in 0..<8 { tuner.ingest(result(cents: 6, even: true)) }
        XCTAssertEqual(tuner.delta ?? .nan, 8, accuracy: 0.3)
    }

    /// With the layer off, parity changes nothing — the status quo the
    /// toggle protects: a fretted 12th still reads as the open string.
    func testTheLayerOffChangesNothing() {
        let tuner = makeTuner()
        tuner.begin()
        for _ in 0..<8 { tuner.ingest(result(cents: 6, even: true)) }
        XCTAssertNil(tuner.octaveSample)
        XCTAssertNil(tuner.octaveCents)
        if case .reading = tuner.state {
        } else {
            XCTFail("without the layer the reading passes through")
        }
    }

    func testRetargetAndLayerFlipForget() {
        let tuner = makeTuner()
        tuner.begin()
        tuner.setIntonating(true)
        for _ in 0..<8 { tuner.ingest(result(cents: 6, even: true)) }
        XCTAssertNotNil(tuner.octaveSample)
        tuner.retarget(Note(midi: 57))
        XCTAssertNil(tuner.octaveSample, "a moved target invalidates the measurement")

        for _ in 0..<8 { tuner.ingest(result(cents: 6, even: true)) }
        tuner.setIntonating(false)
        XCTAssertNil(tuner.octaveSample, "leaving the layer forgets it")
    }
}
