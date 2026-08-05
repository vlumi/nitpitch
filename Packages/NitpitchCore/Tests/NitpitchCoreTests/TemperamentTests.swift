import XCTest

@testable import NitpitchCore

/// The pure-interval arithmetic, pinned: anchored at A, beatless fifths and
/// fourths outward, graceful degradation everywhere else.
final class TemperamentTests: XCTestCase {
    private let fifth = Temperament.pureFifthCents - 700  // ≈ +1.955

    func testEqualOffersNoOffsets() {
        XCTAssertEqual(
            Temperament.equal.offsets(for: Instrument.violin.strings), [0, 0, 0, 0])
    }

    /// The canonical case: G D A E anchored at A — E a pure fifth up, D and
    /// G pure fifths down, each accumulating ≈1.955¢ of narrowness repaired.
    func testViolinAnchorsAtAWithPureFifths() {
        let offsets = Temperament.pure.offsets(for: Instrument.violin.strings)
        XCTAssertEqual(offsets[2], 0, "the A string is the anchor")
        XCTAssertEqual(offsets[3], fifth, accuracy: 0.001, "E, one pure fifth up")
        XCTAssertEqual(offsets[1], -fifth, accuracy: 0.001, "D, one pure fifth down")
        XCTAssertEqual(offsets[0], -2 * fifth, accuracy: 0.001, "G, two down")
    }

    /// Viola and cello: C G D A — the anchor is the top string, everything
    /// below accumulates downward.
    func testViolaWalksDownFromItsA() {
        let offsets = Temperament.pure.offsets(for: Instrument.viola.strings)
        XCTAssertEqual(offsets[3], 0)
        XCTAssertEqual(offsets[0], -3 * fifth, accuracy: 0.001, "C, three pure fifths down")
    }

    /// The double bass rides for free: fourths are inverted fifths, so the
    /// same anchor logic tunes E A D G beatless — E BELOW the anchor gets
    /// +1.955 (a pure fourth is narrower than equal going down).
    func testBassFourthsInvertTheSign() {
        let offsets = Temperament.pure.offsets(for: Instrument.doubleBass.strings)
        XCTAssertEqual(offsets[1], 0, "A1 is the anchor")
        XCTAssertEqual(offsets[0], fifth, accuracy: 0.001, "E, a pure fourth below")
        XCTAssertEqual(offsets[2], -fifth, accuracy: 0.001, "D, a pure fourth up")
        XCTAssertEqual(offsets[3], -2 * fifth, accuracy: 0.001, "G, two up")
    }

    /// A custom tuning with no A has no anchor — silently equal rather than
    /// guessing at one.
    func testNoAMeansNoOffsets() {
        XCTAssertEqual(Temperament.pure.offsets(for: [55, 60, 65]), [0, 0, 0])
    }

    /// An exotic interval steps equal-tempered; the pure steps around it
    /// still apply. A (69) up a tritone (75), then that plus a fifth (82):
    /// the tritone contributes nothing, the fifth its excess.
    func testAnOddIntervalDegradesGracefully() {
        let offsets = Temperament.pure.offsets(for: [69, 75, 82])
        XCTAssertEqual(offsets[1], 0, accuracy: 0.001, "the tritone steps equal")
        XCTAssertEqual(offsets[2], fifth, accuracy: 0.001, "the fifth above it is pure")
    }

    /// Several As: the one nearest A4 anchors — the orchestra's A, not a
    /// bass's.
    func testTheAnchorIsTheANearestA4() {
        let offsets = Temperament.pure.offsets(for: [45, 57, 69])  // A2 A3 A4
        XCTAssertEqual(offsets[2], 0, "A4 anchors")
    }
}
