import XCTest

@testable import NitpitchCore
@testable import NitpitchData
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

    // MARK: - The grid router: the bass field case

    /// Bass E1 A1 D2 G2 — the tuning whose fourths and low fundamentals
    /// starved parity in the field: only G's octave ever classified, while
    /// MPM put E's 12th fret on the D dial at +200¢.
    private var bass: [Double] {
        [28, 33, 38, 43].map { Note(midi: $0).frequency() }
    }

    private func mpmReading(_ hz: Double) -> DetectionResult {
        DetectionResult(frequency: hz, clarity: 0.95, rms: 0.1, level: 0.8)
    }

    private var silent: DetectionResult {
        DetectionResult(frequency: nil, clarity: 0.2, rms: 0.05)
    }

    /// The field report itself: E's fretted 12th lands in the D string's
    /// band, so MPM hands it to the D dial. The router claims it for E, in
    /// parity shape, and quiets the dial it landed on.
    func testAFrettedTwelfthOnANeighboursDialIsClaimedByItsOwner() {
        let e12th = 2 * bass[0] * pow(2, 6.0 / 1200)
        let routed = GridIntonationRouting.route(
            results: [silent, silent, mpmReading(e12th), silent], targets: bass)
        XCTAssertNil(routed[2].frequency, "the D dial must not pin at +200")
        XCTAssertTrue(routed[0].evenPartialsOnly, "E claims its octave in parity shape")
        XCTAssertEqual(
            1200 * log2((routed[0].frequency ?? 1) / bass[0]), 6, accuracy: 0.1,
            "the claim carries the octave's cents on the open scale")
    }

    /// Ordinary tuning readings — in a string's own neighbourhood — are
    /// nobody's octave and pass through untouched.
    func testInBandTuningReadingsPassUntouched() {
        let flatD = bass[2] * pow(2, -30.0 / 1200)
        let routed = GridIntonationRouting.route(
            results: [silent, silent, mpmReading(flatD), silent], targets: bass)
        XCTAssertEqual(routed[2].frequency, flatD)
    }

    /// A claim never overwrites live evidence: when the owner's own dial is
    /// reading this frame, the octave finding is dropped, not forced in.
    func testAClaimNeverOverwritesLiveEvidence() {
        let openE = bass[0] * pow(2, 3.0 / 1200)
        let e12th = 2 * bass[0]
        let routed = GridIntonationRouting.route(
            results: [mpmReading(openE), silent, mpmReading(e12th), silent], targets: bass)
        XCTAssertEqual(routed[0].frequency, openE, "the open reading stands")
        XCTAssertFalse(routed[0].evenPartialsOnly)
        XCTAssertNil(routed[2].frequency, "the stray landing still quiets")
    }

    /// The D string's octave sits ABOVE every band — only the bank's
    /// sentinel ever sees it (the second field report: 12th fret on D
    /// registered nothing at all). The sentinel's reading joins the claims.
    func testAnAboveBandOctaveIsClaimedThroughTheSentinel() {
        let d12th = DetectionResult(
            frequency: 2 * bass[2] * pow(2, 4.0 / 1200), clarity: 0.9, rms: 0.1, level: 0.7)
        let routed = GridIntonationRouting.route(
            results: [silent, silent, silent, silent], targets: bass, above: d12th)
        XCTAssertTrue(routed[2].evenPartialsOnly, "D claims its octave from the sentinel")
        XCTAssertEqual(
            1200 * log2((routed[2].frequency ?? 1) / bass[2]), 4, accuracy: 0.1)
    }

    /// The octave-tuning ambiguity lights BOTH meanings: in Drop D the low
    /// string's 2f IS the open D3, so the reading keeps its own dial — the
    /// player knows which string they played — while the low string's
    /// octave slot hears it too. One frequency, two honest displays;
    /// consensus and latest-wins govern the record, as everywhere.
    func testDropDLightsBothMeanings() {
        let dropD = [38, 45, 50, 55, 59, 64].map { Note(midi: $0).frequency() }
        let openD3 = dropD[2] * pow(2, 2.0 / 1200)
        let routed = GridIntonationRouting.route(
            results: [
                silent, silent, mpmReading(openD3), silent, silent, silent,
            ],
            targets: dropD)
        XCTAssertEqual(routed[2].frequency, openD3, "the D3 dial keeps its reading")
        XCTAssertTrue(routed[0].evenPartialsOnly, "the low D's octave slot hears it too")
        XCTAssertEqual(
            1200 * log2((routed[0].frequency ?? 1) / dropD[0]), 2, accuracy: 0.1,
            "claimed in parity shape: halved, cents on the open scale")
    }

    /// Spectral parity frames are already shaped and keep their dial slot —
    /// the router only claims unflagged readings.
    func testParityFramesPassUntouched() {
        let parity = DetectionResult(
            frequency: bass[3], clarity: 0.9, rms: 0.1, level: 0.8, evenPartialsOnly: true)
        let routed = GridIntonationRouting.route(
            results: [silent, silent, silent, parity], targets: bass)
        XCTAssertEqual(routed[3], parity)
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
