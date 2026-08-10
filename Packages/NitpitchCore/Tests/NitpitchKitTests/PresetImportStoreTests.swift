import NitpitchCore
import XCTest

@testable import NitpitchKit

/// What accepting a shared preset actually writes.
///
/// The rules live in `PresetImportTests`; these prove the store obeys them —
/// and, above all, that the receiver ends up **owning** what they accepted.
@MainActor
final class PresetImportStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "fi.misaki.nitpitch.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStores() -> (PresetStore, InstrumentStore) {
        (
            PresetStore(defaults: defaults),
            InstrumentStore(defaults: defaults, seedReference: { .standard })
        )
    }

    private var dropD: PresetLink {
        PresetLink(
            name: "Drop D", templateID: "guitar", strings: [38, 45, 50, 55, 59, 64],
            referenceHz: 442)
    }

    /// An accepted link becomes an ordinary preset, payload intact.
    func testAcceptingCreatesAnOrdinaryPreset() throws {
        let (presets, _) = makeStores()

        let saved = try XCTUnwrap(presets.importing(dropD, as: .create(name: "Drop D")))

        XCTAssertEqual(saved.name, "Drop D")
        XCTAssertEqual(saved.strings, [38, 45, 50, 55, 59, 64])
        XCTAssertEqual(saved.referenceHz, 442)
        XCTAssertNotNil(saved.modifiedAt, "an import is an edit to this collection")
        XCTAssertEqual(presets.presets.count, 1)
    }

    /// **The ownership rule.** What you accepted is yours: editable, and a
    /// later re-share from the sender cannot silently overwrite the edit —
    /// it comes back as a name collision the user answers.
    func testTheReceiverOwnsWhatTheyAccepted() throws {
        let (presets, instruments) = makeStores()
        let mine = try XCTUnwrap(presets.importing(dropD, as: .create(name: "Drop D")))

        // Edited locally, the way any preset can be.
        let guitar = try XCTUnwrap(instruments.instance(id: Instrument.guitar.id))
        instruments.setTuning(id: guitar.id, strings: [38, 45, 50, 55, 59, 63])
        let edited = try XCTUnwrap(
            presets.save(
                try XCTUnwrap(instruments.instance(id: guitar.id)),
                named: "Drop D", includeReference: false))
        XCTAssertEqual(edited.id, mine.id, "editing kept the same preset")

        // The sender shares a revision. It does NOT quietly land.
        let revised = PresetLink(
            name: "Drop D", templateID: "guitar", strings: [38, 45, 50, 55, 59, 62])
        let resolution = PresetImport.resolve(
            link: revised, existing: presets.existingNames(templateID: "guitar"))

        guard case .nameTaken(let existingID, _, let keepBothName) = resolution else {
            return XCTFail("a re-share must ask, not overwrite")
        }
        XCTAssertEqual(existingID, mine.id)
        XCTAssertEqual(
            presets.presets.first { $0.id == mine.id }?.strings, [38, 45, 50, 55, 59, 63],
            "the local edit still stands until the user answers")
        XCTAssertEqual(keepBothName, "Drop D 2")
    }

    /// Replacing takes the new payload over the old, under one id — "here's
    /// the corrected version".
    func testReplacingOverwritesInPlace() throws {
        let (presets, _) = makeStores()
        let first = try XCTUnwrap(presets.importing(dropD, as: .create(name: "Drop D")))
        let revised = PresetLink(
            name: "Drop D", templateID: "guitar", strings: [38, 45, 50, 55, 59, 62])

        let replaced = try XCTUnwrap(
            presets.importing(
                revised,
                as: .nameTaken(
                    existingID: first.id, name: "Drop D", keepBothName: "Drop D 2")))

        XCTAssertEqual(replaced.id, first.id)
        XCTAssertEqual(presets.presets.count, 1, "one preset, not two")
        XCTAssertEqual(presets.presets.first?.strings, [38, 45, 50, 55, 59, 62])
        XCTAssertNil(
            presets.presets.first?.referenceHz,
            "the new payload replaces the old wholesale, absences included")
    }

    /// Keeping both leaves the original untouched beside a numbered copy —
    /// "here's a variant".
    func testKeepingBothLeavesTheOriginalAlone() throws {
        let (presets, _) = makeStores()
        let first = try XCTUnwrap(presets.importing(dropD, as: .create(name: "Drop D")))
        let revised = PresetLink(
            name: "Drop D", templateID: "guitar", strings: [38, 45, 50, 55, 59, 62])

        // "Keep both" is spelled as a create under the numbered name.
        let second = try XCTUnwrap(presets.importing(revised, as: .create(name: "Drop D 2")))

        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(presets.presets.count, 2)
        XCTAssertEqual(
            presets.presets.first { $0.id == first.id }?.strings, [38, 45, 50, 55, 59, 64],
            "the original is untouched")
    }

    /// An imported preset syncs like any other — it's an ordinary record,
    /// so nothing about its origin exempts it.
    func testImportedPresetsSync() throws {
        let (presets, _) = makeStores()
        let saved = try XCTUnwrap(presets.importing(dropD, as: .create(name: "Drop D")))

        XCTAssertEqual(saved.syncID, saved.id)
        XCTAssertEqual(saved.syncModifiedAt, saved.modifiedAt)
    }

    /// …and is deletable like any other, tombstone included.
    func testImportedPresetsDelete() throws {
        let (presets, _) = makeStores()
        let saved = try XCTUnwrap(presets.importing(dropD, as: .create(name: "Drop D")))

        presets.remove(id: saved.id)

        XCTAssertTrue(presets.presets.isEmpty)
        XCTAssertEqual(presets.tombstones.map(\.id), [saved.id])
    }

    /// The collision check is per template: a guitar "Gig" and a violin
    /// "Gig" have never been the same thing, and importing one must not
    /// offer to replace the other.
    func testCollisionsAreScopedToTheTemplate() throws {
        let (presets, _) = makeStores()
        _ = try XCTUnwrap(
            presets.importing(
                PresetLink(name: "Gig", templateID: "violin", strings: [55, 62, 69, 76]),
                as: .create(name: "Gig")))

        let resolution = PresetImport.resolve(
            link: PresetLink(
                name: "Gig", templateID: "guitar", strings: [40, 45, 50, 55, 59, 64]),
            existing: presets.existingNames(templateID: "guitar"))

        XCTAssertEqual(resolution, .create(name: "Gig"), "a different instrument entirely")
    }
}
