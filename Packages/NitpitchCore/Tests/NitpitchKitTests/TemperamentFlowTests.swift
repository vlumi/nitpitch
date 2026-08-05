import XCTest

@testable import NitpitchCore
@testable import NitpitchKit

/// Temperament through the app's seams: the instance holds it, presets
/// carry it as part of the situation, and every cents answer measures
/// against the shifted target.
@MainActor
final class TemperamentFlowTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "TemperamentFlowTests")
        defaults.removePersistentDomain(forName: "TemperamentFlowTests")
    }

    private func makeStore() -> InstrumentStore {
        InstrumentStore(defaults: defaults) { .standard }
    }

    func testSettingTemperamentPersistsAndStamps() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!
        XCTAssertEqual(violin.appliedTemperament, .equal, "equal is the default")

        store.setTemperament(id: violin.id, .pure)
        let reloaded = makeStore()
        let after = reloaded.instance(id: violin.id)!
        XCTAssertEqual(after.appliedTemperament, .pure)
        XCTAssertNotNil(after.modifiedAt, "the chokepoint stamps")
    }

    func testEqualStoresAsNilForOldJSONCompatibility() {
        let store = makeStore()
        let violin = store.instance(id: Instrument.violin.id)!
        store.setTemperament(id: violin.id, .pure)
        store.setTemperament(id: violin.id, .equal)
        XCTAssertNil(
            store.instance(id: violin.id)!.temperament,
            "equal is spelled as absence, like every pre-temperament instance")
    }

    /// A preset is a situation: it captures the temperament explicitly —
    /// even equal, which must RESTORE equal onto a pure instrument — and
    /// applies it on load.
    func testPresetsCarryAndApplyTemperament() {
        let store = makeStore()
        let presets = PresetStore(defaults: defaults)
        let violin = store.instance(id: Instrument.violin.id)!

        store.setTemperament(id: violin.id, .pure)
        let pure = presets.save(
            store.instance(id: violin.id)!, named: "Quartet", includeReference: false)!
        XCTAssertEqual(pure.temperament, .pure)

        store.setTemperament(id: violin.id, .equal)
        let equal = presets.save(
            store.instance(id: violin.id)!, named: "Studio", includeReference: false)!
        XCTAssertEqual(equal.temperament, .equal, "explicitly equal, not unspecified")

        presets.load(pure, onto: store.instance(id: violin.id)!, in: store)
        XCTAssertEqual(store.instance(id: violin.id)!.appliedTemperament, .pure)

        presets.load(equal, onto: store.instance(id: violin.id)!, in: store)
        XCTAssertEqual(
            store.instance(id: violin.id)!.appliedTemperament, .equal,
            "an equal preset restores equal")
    }

    /// A legacy preset (saved before temperaments existed) decodes with nil
    /// and leaves the instrument's temperament alone on load.
    func testLegacyPresetsLeaveTemperamentAlone() throws {
        let legacy = """
            [{"id":"legacy","name":"Old","templateID":"violin",
              "strings":[55,62,69,76],"referenceHz":null}]
            """
        let decoded = try JSONDecoder().decode(
            [Preset].self, from: Data(legacy.utf8))
        XCTAssertNil(decoded[0].temperament)

        let store = makeStore()
        let presets = PresetStore(defaults: defaults)
        let violin = store.instance(id: Instrument.violin.id)!
        store.setTemperament(id: violin.id, .pure)
        presets.load(decoded[0], onto: store.instance(id: violin.id)!, in: store)
        XCTAssertEqual(
            store.instance(id: violin.id)!.appliedTemperament, .pure,
            "nil payload means leave alone")
    }

    /// The display seam: a tone at the TEMPERED target reads as in tune, so
    /// a violin E under pure fifths calls 1.955¢ sharp of equal "0".
    func testTheDialMeasuresAgainstTheTemperedTarget() {
        let offset = Temperament.pureFifthCents - 700
        let tuner = StringTunerViewModel(
            audio: AudioSessionController(), target: Note(midi: 76), band: 100...2000,
            targetOffsetCents: offset)
        tuner.begin()
        let tempered = Note(midi: 76).frequency() * pow(2, offset / 1200)
        for _ in 0..<4 {
            tuner.ingest(
                DetectionResult(frequency: tempered, clarity: 0.95, rms: 0.1, level: 0.8))
        }
        guard case .reading(let cents, _) = tuner.state else {
            return XCTFail("the tempered pitch must read")
        }
        XCTAssertEqual(cents, 0, accuracy: 0.1, "the tempered target is the zero")
    }
}
