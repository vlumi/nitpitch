import XCTest

@testable import NitpitchCore

/// Two strings on one pitch — a user-made unison, which a shared link can
/// still carry however the editor refuses it — must degrade to "both dials
/// read the same note", never to two dark dials or a zero-width band.
final class UnisonStringTests: XCTestCase {
    /// The spectral engine skipped every partial the duplicate shared with
    /// "another target" — that is every partial — and both dials went dark
    /// for good on the shipped engine.
    func testAUnisonPairBothReadTheNote() {
        let d4 = Note(midi: 62).frequency()
        let strings = [55, 62, 62, 76]
        let bank = DetectorBank(
            sampleRate: sampleRate,
            targets: strings.map { Note(midi: $0).frequency() },
            bands: Instrument(id: "x", name: "x", strings: strings, family: .bowed).stringBands(),
            tuning: DetectionTuning(engine: .spectral))
        let signal = tone(d4, count: signalLength(hops: 4))
        var lit = (first: 0, second: 0)
        for hop in 0..<4 {
            let start = hop * Detection.hopSize
            let results = bank.analyze(Array(signal[start..<(start + Detection.windowSize)]))
            if results[1].frequency != nil { lit.first += 1 }
            if results[2].frequency != nil { lit.second += 1 }
        }
        XCTAssertGreaterThan(lit.first, 0, "the first of the pair reads")
        XCTAssertGreaterThan(lit.second, 0, "and so does the second")
    }

    /// The band split gave the pair the LOWER duplicate's position, so the
    /// upper bound landed on the target itself and a reading a hair sharp
    /// never registered. Distinct neighbours: one honest band, shared.
    func testAUnisonPairSharesOneHonestBand() {
        let bands = Instrument(id: "x", name: "x", strings: [50, 55, 55], family: .other)
            .stringBands()
        let target = Note(midi: 55).frequency()
        XCTAssertEqual(bands[1], bands[2], "the pair shares a band")
        XCTAssertGreaterThan(bands[1].upperBound, target * 1.05, "room above the target")
    }

    /// A band never leaves what the detector can search: at A=390 a
    /// 5-string bass's B0 sits at 27 Hz, below the 30 Hz floor.
    func testBandsStayInsideTheSearchableRange() {
        let bands = Instrument.bassGuitar5.stringBands(reference: ReferencePitch(hz: 390))
        XCTAssertGreaterThanOrEqual(bands[0].lowerBound, Detection.fullBand.lowerBound)
        XCTAssertGreaterThan(bands[0].upperBound, bands[0].lowerBound, "still a band")
    }
}
