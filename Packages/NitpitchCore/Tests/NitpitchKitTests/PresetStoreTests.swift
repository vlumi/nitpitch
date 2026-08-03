import NitpitchCore
import XCTest

@testable import NitpitchKit

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
            PresetStore(defaults: defaults),
            InstrumentStore(defaults: defaults) { .standard }
        )
    }

    /// The payload rule: a preset saved "tuning only" has no reference in it
    /// to apply — the invariant that unified tunings and presets.
    func testTuningOnlyPresetNeverTouchesTheReference() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.defaultInstance(for: .guitar)
        let dropD = Instrument.guitar.knownTunings.first { $0.name == "Drop D" }!
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
        XCTAssertEqual(after.tuningName, "Drop D")
        XCTAssertEqual(after.reference.hz, 440, "tuning-only presets must not move the reference")
    }

    /// And one saved with its reference applies it, visibly by design.
    func testReferenceCarryingPresetAppliesIt() {
        let (presets, instruments) = makeStores()
        let violin = instruments.defaultInstance(for: .violin)
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
        let guitar = instruments.defaultInstance(for: .guitar)
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
        let guitar = instruments.defaultInstance(for: .guitar)
        let violin = instruments.defaultInstance(for: .violin)
        presets.save(guitar, named: "Gig", includeReference: false)

        XCTAssertEqual(presets.presets(fitting: guitar).count, 1)
        XCTAssertTrue(presets.presets(fitting: violin).isEmpty)
    }

    func testEmptyNamesAreRefused() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.defaultInstance(for: .guitar)
        XCTAssertNil(presets.save(guitar, named: "   ", includeReference: false))
        XCTAssertTrue(presets.presets.isEmpty)
    }

    func testPresetsPersistAcrossStores() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.defaultInstance(for: .guitar)
        presets.save(guitar, named: "Gig", includeReference: true)

        let reloaded = PresetStore(defaults: defaults)
        XCTAssertEqual(reloaded.presets.count, 1)
        XCTAssertEqual(reloaded.presets.first?.name, "Gig")
        XCTAssertEqual(reloaded.presets.first?.referenceHz, 440)
    }

    func testRemoveDeletes() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.defaultInstance(for: .guitar)
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!
        presets.remove(id: saved.id)
        XCTAssertTrue(presets.presets.isEmpty)
    }

    /// The menu's checkmark is identity, not value: loading records WHICH
    /// preset the instance is on, and any manual change ends that claim.
    func testLoadingRecordsIdentityAndEditsClearIt() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.defaultInstance(for: .guitar)
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!

        presets.load(saved, onto: guitar, in: instruments)
        XCTAssertEqual(instruments.instance(id: guitar.id)?.loadedPresetID, saved.id)

        // A reference step is a manual change — the setup is no longer
        // "Gig, untouched".
        instruments.setReference(id: guitar.id, ReferencePitch(hz: 443))
        XCTAssertNil(instruments.instance(id: guitar.id)?.loadedPresetID)

        presets.load(saved, onto: instruments.instance(id: guitar.id)!, in: instruments)
        XCTAssertEqual(instruments.instance(id: guitar.id)?.loadedPresetID, saved.id)
        instruments.setString(id: guitar.id, index: 0, midi: 38)
        XCTAssertNil(instruments.instance(id: guitar.id)?.loadedPresetID)

        presets.load(saved, onto: instruments.instance(id: guitar.id)!, in: instruments)
        instruments.setTuning(id: guitar.id, strings: Instrument.guitar.strings)
        XCTAssertNil(instruments.instance(id: guitar.id)?.loadedPresetID)
    }

    /// The lock is not a setup change — locking must not un-claim the preset.
    func testLockingKeepsTheLoadedIdentity() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.defaultInstance(for: .guitar)
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!
        presets.load(saved, onto: guitar, in: instruments)

        instruments.setLocked(id: guitar.id, true)
        XCTAssertEqual(instruments.instance(id: guitar.id)?.loadedPresetID, saved.id)
    }

    /// A preset never mutates by loading — frozen means frozen.
    func testLoadingDoesNotChangeThePreset() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.defaultInstance(for: .guitar)
        let saved = presets.save(guitar, named: "Gig", includeReference: false)!

        instruments.setString(id: guitar.id, index: 0, midi: 38)
        presets.load(saved, onto: instruments.instance(id: guitar.id)!, in: instruments)
        XCTAssertEqual(presets.presets.first, saved)
    }
}
