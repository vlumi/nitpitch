import XCTest

@testable import NitpitchCore
@testable import NitpitchData
@testable import NitpitchKit

/// The grid cell's aggregate verdict, at the view-model seam: holding in
/// tune earns it, silence keeps it, sustained off-target reading takes it
/// back. The arithmetic itself is pinned in Core (`SettleMeter`, through
/// `StringFocusTests`); this pins the wiring — the verdict judged on the
/// same smoothed cents the dial shows.
@MainActor
final class GridSettleTests: XCTestCase {
    private func makeTuner() -> StringTunerViewModel {
        StringTunerViewModel(
            audio: AudioSessionController(), target: Note(midi: 55), band: 100...400)
    }

    private func result(cents: Double) -> DetectionResult {
        let hz = Note(midi: 55).frequency() * pow(2, cents / 1200)
        return DetectionResult(
            frequency: hz, clarity: 0.95, rms: 0.1, level: 0.8, evenPartialsOnly: false)
    }

    func testHoldingInTuneSettlesTheCellAndSilenceKeepsIt() {
        let tuner = makeTuner()
        tuner.begin()
        for _ in 0..<(SettleMeter.settledFrames + 5) { tuner.ingest(result(cents: 1)) }
        XCTAssertTrue(tuner.isSettled, "a held in-tune reading earns the green")

        for _ in 0..<40 { tuner.ingest(.silent) }
        XCTAssertTrue(tuner.isSettled, "the bow lifting is not un-tuning")
    }

    func testSustainedOffTargetReadingUnsettles() {
        let tuner = makeTuner()
        tuner.begin()
        for _ in 0..<(SettleMeter.settledFrames + 5) { tuner.ingest(result(cents: 1)) }
        XCTAssertTrue(tuner.isSettled)

        // Well past the band: even through the display smoothing's lag,
        // every frame reads out of tune within a few frames of the change.
        for _ in 0..<(SettleMeter.unsettleFrames + 20) { tuner.ingest(result(cents: 30)) }
        XCTAssertFalse(tuner.isSettled, "backing off the peg takes the green back")
    }
}
