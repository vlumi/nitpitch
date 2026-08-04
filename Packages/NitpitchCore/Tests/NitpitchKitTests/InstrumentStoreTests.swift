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

    /// First launch seeds the whole factory list as REAL instruments —
    /// browsable and tunable with nothing to add — with ids equal to the
    /// template ids: stable across devices (a future sync's first merge
    /// stays clean) and across time (old favorites keep resolving).
    func testSeedsTheFactoryListOnce() {
        let store = makeStore()
        for template in Instrument.choosable.flatMap(\.instruments) {
            let seeded = store.instance(id: template.id)
            XCTAssertEqual(seeded?.id, template.id, template.name)
            XCTAssertEqual(seeded?.strings, template.strings, template.name)
            XCTAssertEqual(seeded?.isLocked, false, template.name)
        }
        XCTAssertEqual(store.instances(of: .violin).count, 1)
    }

    /// Deletions stick: the seed never reruns, and an empty store is a
    /// legitimate state — the factory instruments are ordinary.
    func testDeletionsStickAcrossRelaunch() {
        let first = makeStore()
        for instance in first.instances {
            first.remove(id: instance.id)
        }
        XCTAssertTrue(first.instances.isEmpty)
        XCTAssertTrue(makeStore().instances.isEmpty, "the seed must not rerun")
    }

    /// Every change stamps modifiedAt — the currency a future
    /// last-writer-wins sync will trade in.
    func testUpdatesStampModifiedAt() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!
        XCTAssertNil(violin.lastUsedAt)
        store.rename(id: violin.id, to: "Guarneri")
        XCTAssertNotNil(store.instance(id: violin.id)?.modifiedAt)
    }

    /// "Waiting as you left it": state survives a relaunch.
    func testStatePersistsAcrossStores() {
        let first = makeStore()
        let guitar = first.instance(id: Instrument.guitar.id)!
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
        let first = store.instance(id: Instrument.guitar.id)!
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
        XCTAssertEqual(store.instance(id: Instrument.cello.id)!.reference.hz, 443)
    }

    /// The string count is a physical fact: a tuning with a different count
    /// never applies, however it arrives.
    func testTuningWithWrongStringCountIsRefused() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!
        store.setTuning(id: violin.id, strings: [40, 45, 50, 55, 59, 64])
        XCTAssertEqual(store.instance(id: violin.id)?.strings, Instrument.violin.strings)
    }

    /// The tuning's name follows the pitches: matching Drop D IS Drop D,
    /// matching nothing is Custom.
    func testTuningNameFollowsTheValues() {
        let store = makeStore()
        let guitar = store.instance(id: Instrument.guitar.id)!
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
        let guitar = store.instance(id: Instrument.guitar.id)!
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
        let violin = store.instance(id: Instrument.violin.id)!
        store.setString(id: violin.id, index: 0, midi: 5)
        XCTAssertEqual(
            store.instance(id: violin.id)?.strings[0],
            InstrumentStore.editableMIDIRange.lowerBound)
        store.setString(id: violin.id, index: 3, midi: 120)
        XCTAssertEqual(
            store.instance(id: violin.id)?.strings[3],
            InstrumentStore.editableMIDIRange.upperBound)
    }

    /// The reported bug: stepping a bass's E1 down twice must land on D1 —
    /// drop D — not stall a semitone short at the clamp.
    func testBassStepsDownToDropD() {
        let store = makeStore()
        let bass = store.instance(id: Instrument.bassGuitar.id)!
        store.setString(id: bass.id, index: 0, midi: 27)  // E1 -> D#1
        store.setString(id: bass.id, index: 0, midi: 26)  // D#1 -> D1
        let edited = store.instance(id: bass.id)!
        XCTAssertEqual(edited.strings[0], 26)
        XCTAssertEqual(edited.tuningName, "Drop D")
    }

    /// The stepper's clamp and the catalog must agree: every catalog tuning
    /// is reachable one semitone at a time.
    func testCatalogTuningsAreWithinTheEditableRange() {
        for template in Instrument.all where !template.strings.isEmpty {
            for tuning in template.knownTunings {
                for midi in tuning.strings {
                    XCTAssertTrue(
                        InstrumentStore.editableMIDIRange.contains(midi),
                        "\(template.name) \(tuning.name ?? "?"): MIDI \(midi) is outside the stepper's range"
                    )
                }
            }
        }
    }

    func testSetStringIgnoresBadIndices() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!
        store.setString(id: violin.id, index: 9, midi: 60)
        XCTAssertEqual(store.instance(id: violin.id)?.strings, Instrument.violin.strings)
    }

    func testRenameRejectsEmptyNames() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!
        store.rename(id: violin.id, to: "   ")
        XCTAssertEqual(store.instance(id: violin.id)?.name, "Violin")
    }

    /// The rack-of-guitars flow: set one up, clone it per instrument —
    /// copied setup, fresh unlocked, numbered name awaiting a rename.
    func testDuplicateCopiesTheSetup() {
        let store = makeStore()
        let guitar = store.instance(id: Instrument.guitar.id)!
        let dropD = Instrument.guitar.knownTunings.first { $0.name == "Drop D" }!
        store.setTuning(id: guitar.id, strings: dropD.strings)
        store.setReference(id: guitar.id, ReferencePitch(hz: 442))
        store.setLocked(id: guitar.id, true)
        store.rename(id: guitar.id, to: "Strat")

        let clone = store.duplicate(id: guitar.id)!
        XCTAssertEqual(clone.strings, dropD.strings)
        XCTAssertEqual(clone.reference.hz, 442)
        XCTAssertFalse(clone.isLocked, "clones start unlocked")
        XCTAssertEqual(clone.name, "Strat 2")

        // Numbering steps over taken names.
        let third = store.duplicate(id: guitar.id)!
        XCTAssertEqual(third.name, "Strat 3")

        // And the clone is its own instrument.
        store.setString(id: clone.id, index: 0, midi: 40)
        XCTAssertEqual(store.instance(id: guitar.id)?.strings, dropD.strings)
    }

    /// A custom count at creation: the 6-string bass exists the moment it's
    /// asked for, bands and all.
    func testAddWithCustomStringCount() {
        let store = makeStore()
        let six = store.add(of: .bassGuitar, stringCount: 6)
        XCTAssertEqual(six.strings, [23, 28, 33, 38, 43, 48])
        XCTAssertEqual(six.instrument.stringBands().count, 6)
        XCTAssertEqual(six.tuningName, "Custom")
    }

    func testRemoveDeletesAnAddedInstance() {
        let store = makeStore()
        let second = store.add(of: .guitar)
        store.remove(id: second.id)
        XCTAssertNil(store.instance(id: second.id))
    }

    /// The stamp survives a relaunch, like everything else.
    func testLastUsedPersists() {
        let first = makeStore()
        let guitar = first.instance(id: Instrument.guitar.id)!
        first.markUsed(id: guitar.id)
        XCTAssertNotNil(makeStore().instance(id: guitar.id)?.lastUsedAt)
    }

    /// The creation sheet's confirm: name and strings arrive together, and
    /// blanks fall back to the suggestion and the template.
    func testAddNamedWithStrings() {
        let store = makeStore()
        let added = store.add(
            of: .guitar, named: "  Strat  ", strings: [35, 40, 45, 50, 55, 59, 64])
        XCTAssertEqual(added.name, "Strat")
        XCTAssertEqual(added.strings.count, 7)
        let blank = store.add(of: .guitar, named: "   ", strings: [])
        XCTAssertEqual(blank.name, "Guitar 3")
        XCTAssertEqual(blank.strings, Instrument.guitar.strings)
    }

    /// The editor's single write path reads the claim rule off the shape:
    /// the same count is a nudge and keeps it, a different count clears it.
    func testSetEditedStringsClaimFollowsShape() {
        let store = makeStore()
        let guitar = store.instance(id: Instrument.guitar.id)!
        store.presetApplied(id: guitar.id, presetID: "p1")
        store.setEditedStrings(id: guitar.id, [38, 45, 50, 55, 59, 64])
        XCTAssertEqual(store.instance(id: guitar.id)?.loadedPresetID, "p1")
        store.setEditedStrings(id: guitar.id, [35, 38, 45, 50, 55, 59, 64])
        XCTAssertNil(store.instance(id: guitar.id)?.loadedPresetID)
        // Empty writes are refused.
        store.setEditedStrings(id: guitar.id, [])
        XCTAssertEqual(store.instance(id: guitar.id)?.strings.count, 7)
    }

    /// The creation prompt's suggested name must be the name `add` would
    /// give — counting the default the add would materialize.
    func testNextAddedNameMatchesWhatAddProduces() {
        let store = makeStore()
        // Before anything exists: the default counts as 1, so the next is 2.
        XCTAssertEqual(store.nextAddedName(for: .guitar), "Guitar 2")
        XCTAssertEqual(store.add(of: .guitar).name, "Guitar 2")
        // And again, now with real instances in the way.
        XCTAssertEqual(store.nextAddedName(for: .guitar), "Guitar 3")
        XCTAssertEqual(store.add(of: .guitar).name, "Guitar 3")
    }

    /// The editor's grow verb continues the outermost interval: a violin
    /// grows a viola's C3 below, or a B5 above.
    func testAddStringContinuesTheOutermostInterval() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!  // G3 D4 A4 E5
        store.addString(id: violin.id, lowEnd: true)
        XCTAssertEqual(store.instance(id: violin.id)?.strings, [48, 55, 62, 69, 76])
        store.addString(id: violin.id, lowEnd: false)
        XCTAssertEqual(store.instance(id: violin.id)?.strings, [48, 55, 62, 69, 76, 83])
        // Guitar's low end continues in fourths: E2 grows a 7-string's B1.
        let guitar = store.instance(id: Instrument.guitar.id)!
        store.addString(id: guitar.id, lowEnd: true)
        XCTAssertEqual(store.instance(id: guitar.id)?.strings.first, 35)
    }

    /// No room past the outermost pitch means no string: a duplicated
    /// outermost target would give two dials one zero-width band.
    func testAddStringRefusesAtTheRangeEdge() {
        let store = makeStore()
        let bass = store.add(of: .bassGuitar5)  // low B0 — the range floor
        XCTAssertFalse(store.canAddString(id: bass.id, lowEnd: true))
        store.addString(id: bass.id, lowEnd: true)
        XCTAssertEqual(store.instance(id: bass.id)?.strings.count, 5)
        // And a long way from the ceiling, adding clamps rather than refuses.
        XCTAssertTrue(store.canAddString(id: bass.id, lowEnd: false))
    }

    /// Removing works anywhere but never below one string.
    func testRemoveStringKeepsAtLeastOne() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!
        store.removeString(id: violin.id, index: 0)
        XCTAssertEqual(store.instance(id: violin.id)?.strings, [62, 69, 76])
        store.removeString(id: violin.id, index: 1)
        store.removeString(id: violin.id, index: 0)
        XCTAssertEqual(store.instance(id: violin.id)?.strings, [76])
        store.removeString(id: violin.id, index: 0)
        XCTAssertEqual(
            store.instance(id: violin.id)?.strings, [76],
            "the last string never goes")
    }

    /// Structural edits are a new shape: the loaded preset's claim clears,
    /// where a pitch nudge (setString) keeps it.
    func testStructuralEditsClearThePresetClaim() {
        let store = makeStore()
        let guitar = store.instance(id: Instrument.guitar.id)!
        store.presetApplied(id: guitar.id, presetID: "p1")
        store.setString(id: guitar.id, index: 0, midi: 38)
        XCTAssertEqual(
            store.instance(id: guitar.id)?.loadedPresetID, "p1",
            "a pitch nudge is drift, not a new pick")
        store.addString(id: guitar.id, lowEnd: true)
        XCTAssertNil(store.instance(id: guitar.id)?.loadedPresetID)

        store.presetApplied(id: guitar.id, presetID: "p2")
        store.removeString(id: guitar.id, index: 0)
        XCTAssertNil(store.instance(id: guitar.id)?.loadedPresetID)
    }

    /// A one-string instrument has no interval to continue; growing it
    /// guesses a fifth rather than freezing.
    func testAddStringToASingleStringGuessesAFifth() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!
        for _ in 0..<3 { store.removeString(id: violin.id, index: 0) }
        XCTAssertEqual(store.instance(id: violin.id)?.strings, [76])
        store.addString(id: violin.id, lowEnd: true)
        XCTAssertEqual(store.instance(id: violin.id)?.strings, [69, 76])
    }

    /// The effective instrument the detection stack sees carries the
    /// instance's strings and the template's family.
    func testEffectiveInstrumentReflectsTheInstance() {
        let store = makeStore()
        let guitar = store.instance(id: Instrument.guitar.id)!
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
