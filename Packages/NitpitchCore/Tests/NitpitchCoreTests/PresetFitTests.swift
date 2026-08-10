import XCTest

@testable import NitpitchCore

/// Which instruments a preset can load onto, and when the answer is none.
final class PresetFitTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func candidate(
        _ id: String, _ template: String, _ count: Int, used: TimeInterval? = nil
    ) -> PresetFit.Candidate {
        PresetFit.Candidate(
            id: id, name: id.capitalized, templateID: template, stringCount: count,
            lastUsedAt: used.map(epoch.addingTimeInterval))
    }

    /// Same template, same string count — both, not either.
    func testFittingNeedsTemplateAndCount() {
        let owned = [
            candidate("strat", "guitar", 6),
            candidate("seven", "guitar", 7),
            candidate("fiddle", "violin", 4),
        ]

        let fits = PresetFit.candidates(templateID: "guitar", stringCount: 6, among: owned)

        XCTAssertEqual(fits.map(\.id), ["strat"])
    }

    /// Several guitars fit a guitar preset, and the one you last played
    /// leads — that's what makes "load it" mean something without asking.
    func testTheMostRecentlyUsedLeads() {
        let owned = [
            candidate("acoustic", "guitar", 6, used: 10),
            candidate("strat", "guitar", 6, used: 90),
            candidate("spare", "guitar", 6),
        ]

        let fits = PresetFit.candidates(templateID: "guitar", stringCount: 6, among: owned)

        XCTAssertEqual(fits.map(\.id), ["strat", "acoustic", "spare"], "never-used last")
    }

    /// Order is total, so a list of candidates can't reshuffle between
    /// renders — the picker would jump under the user's finger.
    func testOrderIsStable() {
        let owned = [candidate("b", "guitar", 6), candidate("a", "guitar", 6)]

        let once = PresetFit.candidates(templateID: "guitar", stringCount: 6, among: owned)
        let twice = PresetFit.candidates(
            templateID: "guitar", stringCount: 6, among: owned.reversed())

        XCTAssertEqual(once.map(\.id), twice.map(\.id))
        XCTAssertEqual(once.map(\.id), ["a", "b"], "undated: by name")
    }

    /// The orphan: a preset whose shape nobody owns. Saved from an
    /// instrument since deleted, or arrived by link for a shape the
    /// receiver doesn't have. Not broken, not deleted — homeless, and the
    /// way back is to create an instrument that fits.
    func testAPresetWithNoMatchingInstrumentIsOrphaned() {
        let owned = [candidate("strat", "guitar", 6)]

        XCTAssertTrue(
            PresetFit.isOrphaned(templateID: "guitar", stringCount: 8, among: owned),
            "an eight-string preset with no eight-string guitar")
        XCTAssertTrue(
            PresetFit.isOrphaned(templateID: "bass-guitar", stringCount: 4, among: owned),
            "a bass preset with no bass")
        XCTAssertFalse(
            PresetFit.isOrphaned(templateID: "guitar", stringCount: 6, among: owned))
    }

    /// Owning nothing at all orphans everything, rather than tripping over
    /// an empty collection.
    func testAnEmptyCollectionOrphansEverything() {
        XCTAssertTrue(PresetFit.isOrphaned(templateID: "guitar", stringCount: 6, among: []))
        XCTAssertTrue(PresetFit.candidates(templateID: "guitar", stringCount: 6, among: []).isEmpty)
    }
}
