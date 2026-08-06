import XCTest

@testable import NitpitchCore

/// The beat arithmetic, pinned against the ear's own numbers: a pure fifth
/// is beatless, equal temperament's fifth beats at ~1 Hz, and the sign says
/// which way to move.
final class IntervalBeatTests: XCTestCase {
    private let violin = Instrument.violin
    private let bass = Instrument.doubleBass

    private func violinTargets(_ temperament: Temperament) -> [Double] {
        let offsets = temperament.offsets(for: violin.strings)
        return zip(violin.notes, offsets).map { note, offset in
            note.frequency() * pow(2, offset / 1200)
        }
    }

    func testAPureFifthIsBeatless() {
        let pure = violinTargets(.pure)
        let reading = IntervalBeat.resolve(
            frequencies: [nil, pure[1], pure[2], nil], midis: violin.strings)!
        XCTAssertEqual(reading.kind, .fifth)
        XCTAssertEqual(reading.lowerIndex, 1, "D–A is the sounding pair")
        XCTAssertEqual(reading.beatHz, 0, accuracy: 0.001)
        XCTAssertEqual(reading.wideCents, 0, accuracy: 0.001)
    }

    /// The number every violinist knows without knowing it: equal
    /// temperament's fifth is ~2¢ narrow, which beats at about 1 Hz around
    /// the D–A coincidence (~880 Hz).
    func testAnEqualTemperedFifthBeatsAtAboutOneHertz() {
        let equal = violinTargets(.equal)
        let reading = IntervalBeat.resolve(
            frequencies: [nil, equal[1], equal[2], nil], midis: violin.strings)!
        XCTAssertEqual(reading.beatHz, 1.0, accuracy: 0.05)
        XCTAssertLessThan(reading.wideCents, 0, "equal's fifth is narrow")
    }

    /// The target respects the temperament: pure aims at silence, equal
    /// aims at its own ~1 Hz — pretending zero would tune the player away
    /// from their targets.
    func testTheTargetBeatFollowsTheTemperament() {
        let pure = violinTargets(.pure)
        let equal = violinTargets(.equal)
        XCTAssertEqual(
            IntervalBeat.targetBeatHz(
                kind: .fifth, lowerTargetHz: pure[1], upperTargetHz: pure[2]),
            0, accuracy: 0.001)
        XCTAssertEqual(
            IntervalBeat.targetBeatHz(
                kind: .fifth, lowerTargetHz: equal[1], upperTargetHz: equal[2]),
            1.0, accuracy: 0.05)
    }

    /// The bass rides the same physics one ratio over: pure fourths are
    /// beatless at 4:3.
    func testABassFourthResolves() {
        let offsets = Temperament.pure.offsets(for: bass.strings)
        let targets = zip(bass.notes, offsets).map { note, offset in
            note.frequency() * pow(2, offset / 1200)
        }
        let reading = IntervalBeat.resolve(
            frequencies: [targets[0], targets[1], nil, nil], midis: bass.strings)!
        XCTAssertEqual(reading.kind, .fourth)
        XCTAssertEqual(reading.beatHz, 0, accuracy: 0.001)
    }

    /// The sign is the advice: a D pressed sharp narrows the fifth, and the
    /// beat grows with it — ~0.5 Hz per cent at the D–A coincidence.
    func testNarrowReadsNarrowAndBeatsGrow() {
        let pure = violinTargets(.pure)
        let sharpD = pure[1] * pow(2, 4.0 / 1200)
        let reading = IntervalBeat.resolve(
            frequencies: [nil, sharpD, pure[2], nil], midis: violin.strings)!
        XCTAssertEqual(reading.wideCents, -4, accuracy: 0.01)
        XCTAssertEqual(reading.beatHz, 2.0, accuracy: 0.1)
    }

    func testASingleStringIsNoInterval() {
        let pure = violinTargets(.pure)
        XCTAssertNil(
            IntervalBeat.resolve(
                frequencies: [nil, pure[1], nil, nil], midis: violin.strings))
    }

    /// A non-fifth/fourth gap — Drop D's low seventh, a guitar's G–B
    /// third — is nobody's pure interval and resolves to nothing.
    func testAnUntunablePairResolvesToNothing() {
        let guitar = Instrument.guitar
        let g3 = guitar.notes[3].frequency()
        let b3 = guitar.notes[4].frequency()
        let frequencies: [Double?] = [nil, nil, nil, g3, b3, nil]
        XCTAssertNil(IntervalBeat.resolve(frequencies: frequencies, midis: guitar.strings))
    }
}
