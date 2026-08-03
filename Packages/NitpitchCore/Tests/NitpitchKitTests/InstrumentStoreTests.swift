import NitpitchCore
import XCTest

@testable import NitpitchKit

/// The store carries the design's central promise: an instrument you own
/// remembers its state — tuning, reference, lock — exactly as you left it.
@MainActor
final class InstrumentStoreTests: XCTestCase {
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

    private func makeStore(reference: Double = 440) -> InstrumentStore {
        InstrumentStore(defaults: defaults) { ReferencePitch(hz: reference) }
    }

    /// The default instance shares the template's id — which is what lets a
    /// favourite pinned before instances existed keep working unchanged, and
    /// keeps accessibility identifiers readable.
    func testDefaultInstanceSharesTheTemplateID() {
        let store = makeStore()
        let violin = store.defaultInstance(for: .violin)
        XCTAssertEqual(violin.id, "violin")
        XCTAssertEqual(violin.name, "Violin")
        XCTAssertEqual(violin.strings, Instrument.violin.strings)
        XCTAssertFalse(violin.isLocked)
    }

    /// Asking twice yields the same instance, not a second violin.
    func testDefaultInstanceIsCreatedOnce() {
        let store = makeStore()
        _ = store.defaultInstance(for: .violin)
        _ = store.defaultInstance(for: .violin)
        XCTAssertEqual(store.instances(of: .violin).count, 1)
    }

    /// "Waiting as you left it": state survives a relaunch.
    func testStatePersistsAcrossStores() {
        let first = makeStore()
        let guitar = first.defaultInstance(for: .guitar)
        let dropD = Instrument.guitar.knownTunings.first { $0.name == "Drop D" }!
        first.setTuning(id: guitar.id, strings: dropD.strings)
        first.setReference(id: guitar.id, ReferencePitch(hz: 442))
        first.setLocked(id: guitar.id, true)
        first.rename(id: guitar.id, to: "Strat")

        let second = makeStore()
        let restored = second.instance(id: guitar.id)
        XCTAssertEqual(restored?.strings, dropD.strings)
        XCTAssertEqual(restored?.tuningName, "Drop D")
        XCTAssertEqual(restored?.reference.hz, 442)
        XCTAssertEqual(restored?.isLocked, true)
        XCTAssertEqual(restored?.name, "Strat")
    }

    /// A second guitar is its own instrument with its own state.
    func testAddedInstanceIsIndependent() {
        let store = makeStore()
        let first = store.defaultInstance(for: .guitar)
        let second = store.add(of: .guitar)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.name, "Guitar 2")

        let dadgad = Instrument.guitar.knownTunings.first { $0.name == "DADGAD" }!
        store.setTuning(id: second.id, strings: dadgad.strings)
        XCTAssertEqual(store.instance(id: first.id)?.tuningName, "Standard")
        XCTAssertEqual(store.instance(id: second.id)?.tuningName, "DADGAD")
    }

    /// A new instrument's reference seeds from where you came from.
    func testNewInstanceSeedsTheCurrentReference() {
        let store = makeStore(reference: 443)
        XCTAssertEqual(store.defaultInstance(for: .cello).reference.hz, 443)
    }

    /// The string count is a physical fact: a tuning with a different count
    /// never applies, however it arrives.
    func testTuningWithWrongStringCountIsRefused() {
        let store = makeStore()
        let violin = store.defaultInstance(for: .violin)
        store.setTuning(id: violin.id, strings: [40, 45, 50, 55, 59, 64])
        XCTAssertEqual(store.instance(id: violin.id)?.strings, Instrument.violin.strings)
    }

    /// The tuning's name follows the pitches: matching Drop D IS Drop D,
    /// matching nothing is Custom.
    func testTuningNameFollowsTheValues() {
        let store = makeStore()
        let guitar = store.defaultInstance(for: .guitar)
        XCTAssertEqual(store.instance(id: guitar.id)?.tuningName, "Standard")

        store.setTuning(id: guitar.id, strings: [38, 45, 50, 55, 59, 64])
        XCTAssertEqual(store.instance(id: guitar.id)?.tuningName, "Drop D")

        store.setTuning(id: guitar.id, strings: [39, 45, 50, 55, 59, 64])
        XCTAssertEqual(store.instance(id: guitar.id)?.tuningName, "Custom")
    }

    /// The string view's stepper: one string moves, the rest stand still, and
    /// the tuning relabels itself by the values.
    func testSetStringEditsOneTargetAndRelabels() {
        let store = makeStore()
        let guitar = store.defaultInstance(for: .guitar)
        store.setString(id: guitar.id, index: 0, midi: 38)  // E2 -> D2
        let edited = store.instance(id: guitar.id)!
        XCTAssertEqual(edited.strings, [38, 45, 50, 55, 59, 64])
        // One string edited to match Drop D exactly IS Drop D.
        XCTAssertEqual(edited.tuningName, "Drop D")

        store.setString(id: guitar.id, index: 0, midi: 37)
        XCTAssertEqual(store.instance(id: guitar.id)?.tuningName, "Custom")
    }

    /// A target the detector can never hear would be a dial that can never
    /// light — edits clamp to the searchable range.
    func testSetStringClampsToTheDetectableRange() {
        let store = makeStore()
        let violin = store.defaultInstance(for: .violin)
        store.setString(id: violin.id, index: 0, midi: 5)
        XCTAssertEqual(
            store.instance(id: violin.id)?.strings[0],
            InstrumentStore.editableMIDIRange.lowerBound)
        store.setString(id: violin.id, index: 3, midi: 120)
        XCTAssertEqual(
            store.instance(id: violin.id)?.strings[3],
            InstrumentStore.editableMIDIRange.upperBound)
    }

    func testSetStringIgnoresBadIndices() {
        let store = makeStore()
        let violin = store.defaultInstance(for: .violin)
        store.setString(id: violin.id, index: 9, midi: 60)
        XCTAssertEqual(store.instance(id: violin.id)?.strings, Instrument.violin.strings)
    }

    func testRenameRejectsEmptyNames() {
        let store = makeStore()
        let violin = store.defaultInstance(for: .violin)
        store.rename(id: violin.id, to: "   ")
        XCTAssertEqual(store.instance(id: violin.id)?.name, "Violin")
    }

    func testRemoveDeletesAnAddedInstance() {
        let store = makeStore()
        let second = store.add(of: .guitar)
        store.remove(id: second.id)
        XCTAssertNil(store.instance(id: second.id))
    }

    /// The effective instrument the detection stack sees carries the
    /// instance's strings and the template's family.
    func testEffectiveInstrumentReflectsTheInstance() {
        let store = makeStore()
        let guitar = store.defaultInstance(for: .guitar)
        let dropD = Instrument.guitar.knownTunings.first { $0.name == "Drop D" }!
        store.setTuning(id: guitar.id, strings: dropD.strings)

        let effective = store.instance(id: guitar.id)!.instrument
        XCTAssertEqual(effective.strings, dropD.strings)
        XCTAssertEqual(effective.family, .fretted)
        // The bands machinery works off it unchanged — Drop D's low D gets
        // its own band like any string.
        XCTAssertEqual(effective.stringBands().count, 6)
    }
}
