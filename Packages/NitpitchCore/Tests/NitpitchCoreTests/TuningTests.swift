import XCTest

@testable import NitpitchCore

/// Tunings and the string-count extension rule: catalog invariants, identity
/// by values, and the derivations that make uncommon counts real tunings.
final class TuningTests: XCTestCase {
    /// Every catalog tuning must fit its own instrument — a wrong string
    /// count in the catalog would be unloadable by construction.
    func testKnownTuningsFitTheirInstrument() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            for tuning in instrument.knownTunings {
                XCTAssertEqual(
                    tuning.strings.count, instrument.strings.count,
                    "\(instrument.name): \(tuning.name ?? "?") has the wrong string count")
                XCTAssertNotNil(tuning.name, "catalog tunings are all named")
            }
            XCTAssertEqual(
                instrument.knownTunings.first?.strings, instrument.strings,
                "\(instrument.name): Standard must come first and match the template")
        }
    }

    /// Identity follows the values: pitches matching a catalog entry ARE that
    /// tuning, anything else is custom (nil).
    func testTuningIdentityFollowsTheValues() {
        let dropD = [38, 45, 50, 55, 59, 64]
        XCTAssertEqual(Instrument.guitar.knownTuning(matching: dropD)?.name, "Drop D")
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
            for tuning in instrument.knownTunings {
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
        let halfStep = Instrument.guitar.knownTunings.first { $0.name == "Half-step down" }!
        XCTAssertEqual(halfStep.strings, Instrument.guitar.strings.map { $0 - 1 })
    }
}
