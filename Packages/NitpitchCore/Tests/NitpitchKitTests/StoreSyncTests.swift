import NitpitchCore
import XCTest

@testable import NitpitchKit

/// What the stores owe the merge: a stamp on everything that changes, and a
/// tombstone for everything that goes away. `SyncMergeTests` proves the rules
/// are right; these prove the stores actually feed them.
@MainActor
final class StoreSyncTests: XCTestCase {
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

    private func makeInstruments() -> InstrumentStore {
        InstrumentStore(defaults: defaults, seedReference: { .standard })
    }

    private func makePresets() -> (PresetStore, InstrumentStore) {
        (PresetStore(defaults: defaults), makeInstruments())
    }

    // MARK: - Stamping

    /// Every instrument arrives stamped, the seeded factory ones included.
    /// An unstamped record loses every merge against a stamped one, so an
    /// unstamped *new* instrument would be a creation that syncing quietly
    /// discards.
    func testEveryCreationPathStamps() {
        let store = makeInstruments()

        let seeded = store.instance(id: Instrument.violin.id)
        XCTAssertNotNil(seeded?.modifiedAt, "the factory seed stamps")

        let added = store.add(of: Instrument.guitar)
        XCTAssertNotNil(added.modifiedAt, "add stamps")

        let created = store.add(of: Instrument.guitar, named: "Strat", strings: [40, 45, 50, 55])
        XCTAssertNotNil(created.modifiedAt, "the creation sheet's add stamps")

        let copy = store.duplicate(id: created.id)
        XCTAssertNotNil(copy?.modifiedAt, "duplicate stamps")
    }

    /// An edit moves the stamp forward — that movement is the whole
    /// currency of last-writer-wins.
    func testEditAdvancesTheStamp() {
        let store = makeInstruments()
        let violin = Instrument.violin.id
        let before = store.instance(id: violin)!.modifiedAt!

        store.rename(id: violin, to: "Konzertmeister")

        let after = store.instance(id: violin)!.modifiedAt!
        XCTAssertGreaterThan(after, before)
    }

    /// A saved preset carries its own stamp, so two devices editing the
    /// same-named preset resolve the same way instruments do.
    func testPresetSaveStamps() {
        let (presets, instruments) = makePresets()
        let guitar = instruments.instance(id: Instrument.guitar.id)!

        let saved = presets.save(guitar, named: "Gig", includeReference: true)!

        XCTAssertNotNil(saved.modifiedAt)
        XCTAssertEqual(saved.syncID, saved.id)
        XCTAssertEqual(saved.syncModifiedAt, saved.modifiedAt)
    }

    /// Saving over a name replaces the preset and re-stamps it: same id,
    /// later date, so the overwrite is what propagates.
    func testResavingAdvancesTheStamp() throws {
        let (presets, instruments) = makePresets()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let first = presets.save(guitar, named: "Gig", includeReference: false)!

        let second = try XCTUnwrap(presets.save(guitar, named: "Gig", includeReference: true))

        XCTAssertEqual(second.id, first.id, "same name, same preset")
        XCTAssertGreaterThan(
            try XCTUnwrap(second.modifiedAt), try XCTUnwrap(first.modifiedAt))
    }

    // MARK: - Tombstones

    /// Deleting an instrument leaves a record of the deletion. Without it,
    /// a device that still holds the instrument merges it back — and the
    /// factory seed's stable ids make that certain rather than likely.
    func testDeletingAnInstrumentLeavesATombstone() {
        let store = makeInstruments()
        let violin = Instrument.violin.id

        store.remove(id: violin)

        XCTAssertEqual(store.tombstones.map(\.id), [violin])
        // ...and it does what it's for: a remote copy of the deleted
        // instrument doesn't come back through the merge.
        let remote = [
            InstrumentInstance(
                id: violin, templateID: violin, name: "Violin", strings: Instrument.violin.strings,
                referenceHz: 440, isLocked: false, modifiedAt: Date().addingTimeInterval(-60))
        ]
        let merged = SyncMerge.mergedRecords(
            local: store.instances, remote: remote, tombstones: store.tombstones)
        XCTAssertFalse(merged.contains { $0.id == violin })
    }

    /// Same for presets, whose ids are UUIDs — the tombstone matters here
    /// because the other device's copy is otherwise indistinguishable from
    /// news.
    func testDeletingAPresetLeavesATombstone() {
        let (presets, instruments) = makePresets()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!

        presets.remove(id: saved.id)

        XCTAssertEqual(presets.tombstones.map(\.id), [saved.id])
    }

    /// Tombstones persist: the deletion has to survive the launch that
    /// follows it, or the next sync resurrects everything deleted while
    /// the other device was away.
    func testTombstonesSurviveRelaunch() {
        let store = makeInstruments()
        store.remove(id: Instrument.viola.id)

        let relaunched = makeInstruments()

        XCTAssertEqual(relaunched.tombstones.map(\.id), [Instrument.viola.id])
    }

    /// Removing something that isn't there is not a deletion, and must not
    /// mint a tombstone — a stone for an id that never existed would be
    /// dead weight in every future merge.
    func testRemovingNothingLeavesNoTombstone() {
        let store = makeInstruments()
        let presets = PresetStore(defaults: defaults)

        store.remove(id: "no-such-instrument")
        presets.remove(id: "no-such-preset")

        XCTAssertTrue(store.tombstones.isEmpty)
        XCTAssertTrue(presets.tombstones.isEmpty)
    }
}
