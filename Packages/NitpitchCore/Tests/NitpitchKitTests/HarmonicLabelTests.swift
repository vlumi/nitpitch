import XCTest

@testable import NitpitchCore
@testable import NitpitchData
@testable import NitpitchKit

/// The "· 2nd harmonic" / "· 3rd harmonic" label's state machine, which had
/// two field bugs and no test: it must not flicker on a single odd frame,
/// and it must not stand under the dial once the dial has nothing to say
/// (the routing silences the dial while the octave sounds, and a label left
/// behind reads as a live claim).
@MainActor
final class HarmonicLabelTests: XCTestCase {
    private func makeTuner() -> StringTunerViewModel {
        StringTunerViewModel(
            audio: AudioSessionController(), target: Note(midi: 55), band: 100...400)
    }

    private func reading(harmonic: Int) -> DetectionResult {
        DetectionResult(
            frequency: Note(midi: 55).frequency(), clarity: 0.95, rms: 0.1, level: 0.8,
            evenPartialsOnly: false, harmonic: harmonic)
    }

    func testTheLabelNeedsThreeAgreeingFramesAndNeverFlickers() {
        let tuner = makeTuner()
        tuner.begin()
        for _ in 0..<5 { tuner.ingest(reading(harmonic: 1)) }
        XCTAssertEqual(tuner.harmonic, 1)

        // Two frames claiming the 3rd is not enough — a label must never
        // appear on a coincidence.
        tuner.ingest(reading(harmonic: 3))
        tuner.ingest(reading(harmonic: 3))
        XCTAssertEqual(tuner.harmonic, 1, "two frames is a flicker, not a claim")

        tuner.ingest(reading(harmonic: 3))
        XCTAssertEqual(tuner.harmonic, 3, "three agreeing frames is a claim")
    }

    func testASilencedFrameDropsTheClaim() {
        let tuner = makeTuner()
        tuner.begin()
        for _ in 0..<4 { tuner.ingest(reading(harmonic: 2)) }
        XCTAssertEqual(tuner.harmonic, 2)

        // The routing hands the dial nothing while the octave sounds. The
        // label must go with it rather than standing as a live claim.
        for _ in 0..<3 { tuner.ingest(.silent) }
        XCTAssertEqual(tuner.harmonic, 1, "no reading, no harmonic claim")
    }
}
