import XCTest

@testable import NitpitchCore

/// What an arriving link becomes — the decision the receiver makes, as
/// rules, before anything is written.
final class PresetImportTests: XCTestCase {
    private func link(named name: String) -> PresetLink {
        PresetLink(name: name, templateID: "guitar", strings: [38, 45, 50, 55, 59, 64])
    }

    /// Nothing of that name here: an ordinary new preset.
    func testAnUnknownNameCreates() {
        let resolution = PresetImport.resolve(
            link: link(named: "Drop D"), existing: [(id: "a", name: "Gig")])

        XCTAssertEqual(resolution, .create(name: "Drop D"))
    }

    /// A name already in use is the interesting case, and it's the SAME
    /// case a local save has: identify by name, then ask. The user picks
    /// between "here's the corrected version" (replace) and "here's a
    /// variant" (keep both) — an intent the app can't infer and shouldn't
    /// guess.
    func testATakenNameOffersBoth() {
        let resolution = PresetImport.resolve(
            link: link(named: "Gig"),
            existing: [(id: "a", name: "Gig"), (id: "b", name: "Drop D")])

        XCTAssertEqual(
            resolution,
            .nameTaken(existingID: "a", name: "Gig", keepBothName: "Gig 2"))
    }

    /// Names fold case, exactly as saving does — "gig" and "Gig" are one
    /// intent, not two presets.
    func testNameMatchingFoldsCase() {
        let resolution = PresetImport.resolve(
            link: link(named: "GIG"), existing: [(id: "a", name: "gig")])

        guard case .nameTaken(let existingID, _, _) = resolution else {
            return XCTFail("a case-different name is still the same name")
        }
        XCTAssertEqual(existingID, "a")
    }

    /// "Keep both" numbers past whatever is already taken, so accepting the
    /// same link repeatedly never collides.
    func testKeepBothNumbersPastTheTaken() {
        let resolution = PresetImport.resolve(
            link: link(named: "Gig"),
            existing: [(id: "a", name: "Gig"), (id: "b", name: "Gig 2"), (id: "c", name: "gig 3")])

        guard case .nameTaken(_, _, let keepBoth) = resolution else {
            return XCTFail("expected a collision")
        }
        XCTAssertEqual(keepBoth, "Gig 4", "and the numbering folds case too")
    }

    /// The receiver owns what they accept. Re-importing an edited version
    /// of something they already took is a name collision like any other —
    /// there is no link identity quietly overwriting their copy, which is
    /// exactly what keeps a friend's re-share from erasing local edits.
    func testAReshareIsJustANameCollision() {
        let first = PresetLink(
            name: "Gig", templateID: "guitar", strings: [40, 45, 50, 55, 59, 64])
        let edited = PresetLink(
            name: "Gig", templateID: "guitar", strings: [38, 45, 50, 55, 59, 64],
            referenceHz: 442)

        // Accepted once as a new preset...
        XCTAssertEqual(PresetImport.resolve(link: first, existing: []), .create(name: "Gig"))
        // ...and the sender's second attempt asks, rather than deciding.
        XCTAssertEqual(
            PresetImport.resolve(link: edited, existing: [(id: "mine", name: "Gig")]),
            .nameTaken(existingID: "mine", name: "Gig", keepBothName: "Gig 2"))
    }
}
