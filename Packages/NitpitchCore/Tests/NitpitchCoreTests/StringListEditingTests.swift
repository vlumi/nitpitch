import XCTest

@testable import NitpitchCore

/// The shared string-list editing rules — one place decides what "add a
/// string" proposes, whether the live editor or the creation draft asks.
final class StringListEditingTests: XCTestCase {
    /// Growing continues the outermost interval: a violin grows a viola's
    /// C3 below or a B5 above; a guitar's low end grows a 7-string's B1.
    func testExtendedContinuesTheOutermostInterval() {
        let violin = Instrument.violin.strings  // G3 D4 A4 E5
        XCTAssertEqual(StringListEditing.extended(violin, lowEnd: true), [48, 55, 62, 69, 76])
        XCTAssertEqual(StringListEditing.extended(violin, lowEnd: false), [55, 62, 69, 76, 83])
        XCTAssertEqual(
            StringListEditing.extended(Instrument.guitar.strings, lowEnd: true).first, 35)
    }

    /// No room past the outermost pitch means no growth — a duplicated
    /// outermost target would give two dials one zero-width band.
    func testExtendedRefusesAtTheRangeEdge() {
        let fiveString = Instrument.bassGuitar5.strings  // low B0, the floor
        XCTAssertFalse(StringListEditing.canExtend(fiveString, lowEnd: true))
        XCTAssertEqual(StringListEditing.extended(fiveString, lowEnd: true), fiveString)
        XCTAssertTrue(StringListEditing.canExtend(fiveString, lowEnd: false))
        XCTAssertFalse(StringListEditing.canExtend([], lowEnd: true))
    }

    /// A single string has no interval to continue; growth guesses a fifth.
    func testExtendedGuessesAFifthFromOneString() {
        XCTAssertEqual(StringListEditing.extended([76], lowEnd: true), [69, 76])
        XCTAssertEqual(StringListEditing.extended([69], lowEnd: false), [69, 76])
    }

    /// Growth clamps to the detectable range rather than proposing a pitch
    /// no dial could ever light.
    func testExtendedClampsToTheDetectableRange() {
        let nearFloor = [Detection.targetMIDIRange.lowerBound + 2, 40]
        let grown = StringListEditing.extended(nearFloor, lowEnd: true)
        XCTAssertEqual(grown.first, Detection.targetMIDIRange.lowerBound)
    }

    /// Removal works anywhere but never empties the list.
    func testRemovedKeepsAtLeastOne() {
        XCTAssertEqual(StringListEditing.removed([55, 62, 69], at: 1), [55, 69])
        XCTAssertEqual(StringListEditing.removed([55], at: 0), [55])
        XCTAssertEqual(StringListEditing.removed([55, 62], at: 9), [55, 62])
    }

    /// Nudging steps one target by semitones, clamped like every stepper.
    func testSteppedNudgesWithinTheRange() {
        XCTAssertEqual(StringListEditing.stepped([40, 45], at: 0, by: -2), [38, 45])
        let floor = Detection.targetMIDIRange.lowerBound
        XCTAssertEqual(StringListEditing.stepped([floor], at: 0, by: -1), [floor])
        XCTAssertEqual(StringListEditing.stepped([40], at: 5, by: 1), [40])
    }

    /// The + menu offers one entry per KIND: the N-string variants stay off
    /// it (the count is the sheet's business), while remaining choosable in
    /// the instrument list.
    func testAddableExcludesVariantsButKeepsKinds() {
        let addable = Instrument.addable.flatMap(\.instruments).map(\.id)
        XCTAssertTrue(addable.contains("guitar"))
        XCTAssertTrue(addable.contains("bass-guitar"))
        XCTAssertTrue(addable.contains("violin"))
        XCTAssertFalse(addable.contains("guitar-7"))
        XCTAssertFalse(addable.contains("guitar-8"))
        XCTAssertFalse(addable.contains("bass-guitar-5"))
        let choosable = Instrument.choosable.flatMap(\.instruments).map(\.id)
        XCTAssertTrue(choosable.contains("guitar-7"), "variants stay in the list")
    }

    /// Every choosable template carries a kind tag — "which is which" must
    /// never fall back to blank — and the orchestra abbreviations hold.
    func testKindTagsCoverTheCatalog() {
        for template in Instrument.choosable.flatMap(\.instruments) {
            XCTAssertFalse(template.kindTag.isEmpty, template.name)
        }
        XCTAssertEqual(Instrument.violin.kindTag, "Vln")
        XCTAssertEqual(Instrument.doubleBass.kindTag, "Db")
        XCTAssertEqual(Instrument.guitar7.kindTag, "Gtr")
        XCTAssertEqual(Instrument.bassGuitar5.kindTag, "Bass")
        XCTAssertTrue(Instrument.chromatic.kindTag.isEmpty)
    }

    /// Every common count must be reachable by the extension rule, include
    /// the standard, and the always-four bowed kinds offer no choice.
    func testCommonStringCountsAreHonest() {
        for template in Instrument.all where !template.strings.isEmpty {
            let counts = template.commonStringCounts
            XCTAssertTrue(
                counts.contains(template.strings.count),
                "\(template.name): the standard count is always common")
            for count in counts {
                XCTAssertEqual(
                    template.strings(count: count).count, count,
                    "\(template.name): common count \(count) must be constructible")
            }
        }
        XCTAssertEqual(Instrument.violin.commonStringCounts, [4])
        XCTAssertEqual(Instrument.doubleBass.commonStringCounts, [4, 5])
    }
}
