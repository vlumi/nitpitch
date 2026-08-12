import NitpitchCore
import XCTest

@testable import NitpitchKit

// MARK: - Favorites and fitting order

extension PresetStoreTests {
    /// Preset favorites float to the top of every fitting list, and the
    /// flag lives beside the presets — deleting one takes its flag along.
    @MainActor
    func testFavoritesFloatAndFollowDeletion() {
        let (store, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let first = store.save(guitar, named: "Alpha", includeReference: false)!
        let second = store.save(guitar, named: "Beta", includeReference: false)!

        XCTAssertEqual(store.presets(fitting: guitar).map(\.id), [first.id, second.id])
        store.toggleFavorite(second.id)
        XCTAssertTrue(store.isFavorite(second.id))
        XCTAssertEqual(
            store.presets(fitting: guitar).map(\.id), [second.id, first.id],
            "favorites lead")

        store.remove(id: second.id)
        XCTAssertFalse(store.isFavorite(second.id), "the flag dies with the preset")
    }
}

/// The preset design in tests: a frozen setup under the user's name, carrying
/// only the fields it was saved with, applied to instruments it fits.
@MainActor
final class PresetStoreTests: XCTestCase {
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
            PresetStore(defaults: defaults, seedingFactoryTunings: false),
            InstrumentStore(defaults: defaults) { .standard }
        )
    }

    /// The payload rule: a preset saved "tuning only" has no reference in it
    /// to apply — the invariant that unified tunings and presets.
    func testTuningOnlyPresetNeverTouchesTheReference() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let dropD = Instrument.guitar.factoryTunings.first { $0.name == "Drop D" }!
        instruments.setTuning(id: guitar.id, strings: dropD.strings)
        instruments.setReference(id: guitar.id, ReferencePitch(hz: 442))

        let saved = presets.save(
            instruments.instance(id: guitar.id)!, named: "Gig", includeReference: false)!
        XCTAssertNil(saved.referenceHz)

        // Back to standard at 440, then load: pitches move, reference doesn't.
        instruments.setTuning(id: guitar.id, strings: Instrument.guitar.strings)
        instruments.setReference(id: guitar.id, ReferencePitch(hz: 440))
        presets.load(saved, onto: instruments.instance(id: guitar.id)!, in: instruments)

        let after = instruments.instance(id: guitar.id)!
        XCTAssertEqual(after.strings, dropD.strings, "the pitches moved")
        XCTAssertEqual(after.reference.hz, 440, "tuning-only presets must not move the reference")
    }

    /// And one saved with its reference applies it, visibly by design.
    func testReferenceCarryingPresetAppliesIt() {
        let (presets, instruments) = makeStores()
        let violin = instruments.instance(id: Instrument.violin.id)!
        instruments.setReference(id: violin.id, ReferencePitch(hz: 442))
        let saved = presets.save(
            instruments.instance(id: violin.id)!, named: "Bach No. 1", includeReference: true)!
        XCTAssertEqual(saved.referenceHz, 442)

        instruments.setReference(id: violin.id, ReferencePitch(hz: 440))
        presets.load(saved, onto: instruments.instance(id: violin.id)!, in: instruments)
        XCTAssertEqual(instruments.instance(id: violin.id)?.reference.hz, 442)
    }

    /// Saving over an existing name replaces it — same id, new payload — and
    /// names differing only in case are one intent, not two presets.
    func testSavingOverAnExistingNameReplaces() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let first = presets.save(guitar, named: "Gig", includeReference: false)!

        instruments.setReference(id: guitar.id, ReferencePitch(hz: 443))
        let second = presets.save(
            instruments.instance(id: guitar.id)!, named: "gig", includeReference: true)!

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(presets.presets.count, 1)
        XCTAssertEqual(presets.presets.first?.referenceHz, 443)
        XCTAssertEqual(presets.presets.first?.name, "gig", "the latest spelling wins")
    }

    /// Presets offer themselves only where they fit: same template, same
    /// string count.
    func testFittingIsByTemplateAndCount() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let violin = instruments.instance(id: Instrument.violin.id)!
        presets.save(guitar, named: "Gig", includeReference: false)

        XCTAssertEqual(presets.presets(fitting: guitar).count, 1)
        XCTAssertTrue(presets.presets(fitting: violin).isEmpty)
    }

    func testEmptyNamesAreRefused() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        XCTAssertNil(presets.save(guitar, named: "   ", includeReference: false))
        XCTAssertTrue(presets.presets.isEmpty)
    }

    func testPresetsPersistAcrossStores() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        presets.save(guitar, named: "Gig", includeReference: true)

        let reloaded = PresetStore(defaults: defaults, seedingFactoryTunings: false)
        XCTAssertEqual(reloaded.presets.count, 1)
        XCTAssertEqual(reloaded.presets.first?.name, "Gig")
        XCTAssertEqual(reloaded.presets.first?.referenceHz, 440)
    }

    func testRemoveDeletes() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!
        presets.remove(id: saved.id)
        XCTAssertTrue(presets.presets.isEmpty)
    }

    /// The claim is provenance: granular edits (a string step, a reference
    /// step) keep it — the pill shows "(edited)" — and only an explicit pick
    /// (a tuning from the menu, another preset) replaces it. Clearing on
    /// edit made the pill announce a catalog tuning nobody picked.
    func testGranularEditsKeepTheClaimAndPicksReplaceIt() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!

        presets.load(saved, onto: guitar, in: instruments)
        XCTAssertEqual(instruments.instance(id: guitar.id)?.loadedPresetID, saved.id)

        // Drift, not a new pick: the claim survives a reference step and a
        // string edit.
        instruments.setReference(id: guitar.id, ReferencePitch(hz: 443))
        XCTAssertEqual(instruments.instance(id: guitar.id)?.loadedPresetID, saved.id)
        instruments.setString(id: guitar.id, index: 0, midi: 38)
        XCTAssertEqual(instruments.instance(id: guitar.id)?.loadedPresetID, saved.id)

        // A tuning picked from the menu IS a new claim.
        instruments.setTuning(id: guitar.id, strings: Instrument.guitar.strings)
        XCTAssertNil(instruments.instance(id: guitar.id)?.loadedPresetID)
    }

    /// The lock is not a setup change — locking must not un-claim the preset.
    func testLockingKeepsTheLoadedIdentity() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!
        presets.load(saved, onto: guitar, in: instruments)

        instruments.setLocked(id: guitar.id, true)
        XCTAssertEqual(instruments.instance(id: guitar.id)?.loadedPresetID, saved.id)
    }

    /// A preset never mutates by loading — frozen means frozen.
    func testLoadingDoesNotChangeThePreset() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!

        instruments.setString(id: guitar.id, index: 0, midi: 38)
        presets.load(saved, onto: instruments.instance(id: guitar.id)!, in: instruments)
        XCTAssertEqual(presets.presets.first, saved)
    }
}
