import XCTest

@testable import NitpitchCore

/// Tunings and the string-count extension rule: catalog invariants, identity
/// by values, and the derivations that make uncommon counts real tunings.
final class TuningTests: XCTestCase {
    /// The catalog is Standard, and only Standard — everything else ships
    /// as seeded presets. A wrong string count in either list would be
    /// unloadable by construction.
    func testTheCatalogIsExactlyStandard() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            XCTAssertEqual(
                instrument.knownTunings.map(\.name), ["Standard"],
                "\(instrument.name): the catalog holds Standard alone")
            XCTAssertEqual(
                instrument.knownTunings.first?.strings, instrument.strings,
                "\(instrument.name): Standard IS the template's own strings")
            for tuning in instrument.factoryTunings {
                XCTAssertEqual(
                    tuning.strings.count, instrument.strings.count,
                    "\(instrument.name): \(tuning.name ?? "?") has the wrong string count")
                XCTAssertNotNil(tuning.name, "seed tunings are all named")
                XCTAssertNotEqual(
                    tuning.strings, instrument.strings,
                    "a seed that equals Standard would shadow it")
            }
        }
    }

    /// The seed list is what it has always been: the guitar's four and the
    /// bass's two. Pinned so a trim is a deliberate edit here, not a slip —
    /// trimming only affects fresh installs, and nitpitch.app carries every
    /// entry regardless.
    func testTheSeedListsAreDeliberate() {
        XCTAssertEqual(
            Instrument.guitar.factoryTunings.compactMap(\.name),
            ["Drop D", "DADGAD", "Open G", "Half-step down"])
        XCTAssertEqual(
            Instrument.bassGuitar.factoryTunings.compactMap(\.name),
            ["Drop D", "Half-step down"])
        for instrument in Instrument.all
        where !["guitar", "bass-guitar"].contains(instrument.id) {
            XCTAssertTrue(
                instrument.factoryTunings.isEmpty,
                "\(instrument.name) seeds nothing")
        }
    }

    /// Identity follows the values — but the catalog now only knows
    /// Standard. Drop D is a preset, so the catalog says nil for it;
    /// naming past Standard is `PresetStore.tuningDisplayName`'s job.
    func testTuningIdentityFollowsTheValues() {
        let dropD = [38, 45, 50, 55, 59, 64]
        XCTAssertNil(Instrument.guitar.knownTuning(matching: dropD))
        XCTAssertNil(Instrument.guitar.knownTuning(matching: [39, 45, 50, 55, 59, 64]))
        XCTAssertEqual(
            Instrument.guitar.knownTuning(matching: Instrument.guitar.strings)?.name,
            "Standard")
    }

    /// A tuning the catalog offers but the app couldn't hear or the stepper
    /// couldn't reach would be a standing contradiction — the bass drop D
    /// was exactly that until the floors were unified.
    func testEveryCatalogTuningIsDetectableEverywhere() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            for tuning in instrument.knownTunings + instrument.factoryTunings {
                for midi in tuning.strings {
                    XCTAssertTrue(
                        Detection.fullBand.contains(Note(midi: midi).frequency()),
                        "\(instrument.name) \(tuning.name ?? "?"): MIDI \(midi) is outside the chromatic band"
                    )
                }
            }
        }
    }

    /// Half-step down is exactly that, string for string.
    func testHalfStepDownIsAUniformShift() {
        let halfStep = Instrument.guitar.factoryTunings.first { $0.name == "Half-step down" }!
        XCTAssertEqual(halfStep.strings, Instrument.guitar.strings.map { $0 - 1 })
    }
}
