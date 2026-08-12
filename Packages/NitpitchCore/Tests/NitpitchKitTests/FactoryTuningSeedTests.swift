import NitpitchCore
import XCTest

@testable import NitpitchKit

/// The factory tunings as seeded presets: included by default, special in
/// no other way. Deletable, renameable, synced — and gone means gone.
@MainActor
final class FactoryTuningSeedTests: XCTestCase {
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

    /// A fresh install owns the guitar's four and the bass's two, as real
    /// presets with stable ids and NO stamp — a seed is what was there
    /// before the user did anything, so it must lose every merge against a
    /// real edit (the instrument seed's `.distantPast` lesson, spelled nil
    /// here so the browser shows no invented date).
    func testAFreshInstallSeedsTheFactoryTunings() {
        let presets = PresetStore(defaults: defaults)

        let guitar = presets.presets.filter { $0.templateID == "guitar" }
        XCTAssertEqual(
            guitar.map(\.name), ["Drop D", "DADGAD", "Open G", "Half-step down"])
        let bass = presets.presets.filter { $0.templateID == "bass-guitar" }
        XCTAssertEqual(bass.map(\.name), ["Drop D", "Half-step down"])
        XCTAssertEqual(presets.presets.count, 6, "and nothing else")

        for seed in presets.presets {
            XCTAssertNil(seed.modifiedAt, "\(seed.name): seeds are unstamped")
            XCTAssertNil(seed.referenceHz, "\(seed.name): a tuning is pitches only")
            XCTAssertNil(seed.temperament, "\(seed.name): and carries no temperament")
            XCTAssertTrue(seed.id.hasPrefix("seed:"), seed.id)
        }
        XCTAssertEqual(
            presets.presets.first?.id, "seed:guitar:drop-d",
            "ids derive from template + catalog name, identically on every device")
    }

    /// Deleting one sticks: the seed runs once, so a deleted Drop D does
    /// not respawn at the next launch — included by default, not enforced.
    func testADeletedSeedStaysDeleted() {
        let first = PresetStore(defaults: defaults)
        first.remove(id: "seed:guitar:drop-d")

        let relaunched = PresetStore(defaults: defaults)

        XCTAssertNil(
            relaunched.presets.first { $0.id == "seed:guitar:drop-d" },
            "gone means gone")
        XCTAssertEqual(
            relaunched.tombstones.map(\.id), ["seed:guitar:drop-d"],
            "and the deletion is remembered for sync")
    }

    /// A name the user already took is theirs: seeding must not plant a
    /// twin beside it — two same-named presets on one template is the
    /// collision every other path refuses.
    func testSeedingSkipsANameTheUserTook() throws {
        // A pre-seed store state: user data exists, flag doesn't. Simulate
        // by planting a preset under the store's own key first.
        let existing = Preset(
            id: "mine", name: "drop d", templateID: "guitar",
            strings: [38, 45, 50, 55, 59, 62], referenceHz: nil, temperament: nil,
            modifiedAt: Date())
        let data = try JSONEncoder().encode([existing])
        defaults.set(data, forKey: "presets.v1")

        let presets = PresetStore(defaults: defaults)

        let dropDs = presets.presets.filter {
            $0.templateID == "guitar" && $0.name.lowercased() == "drop d"
        }
        XCTAssertEqual(dropDs.map(\.id), ["mine"], "the user's preset stands alone")
    }

    /// The deletion crosses devices, and a FRESH INSTALL cannot resurrect
    /// it: the new device seeds the same id unstamped, and the tombstone
    /// wins. This is the whole point of stable ids plus nil stamps.
    func testAFreshInstallDoesNotResurrectADeletedSeed() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        defer { phone.destroy() }
        phone.presets.remove(id: "seed:guitar:drop-d")
        phone.engine.sync()

        // A brand-new device: seeds all six, then meets the cloud.
        let mac = SyncTestDevice(sharing: cloud)
        defer { mac.destroy() }
        mac.engine.sync()
        phone.engine.sync()

        XCTAssertNil(
            mac.presets.presets.first { $0.id == "seed:guitar:drop-d" },
            "the tombstone beats the fresh seed")
        XCTAssertNil(
            phone.presets.presets.first { $0.id == "seed:guitar:drop-d" },
            "and it stays gone at home")
        XCTAssertNotNil(
            mac.presets.presets.first { $0.id == "seed:guitar:dadgad" },
            "undeleted seeds merge to one copy, not two")
    }

    /// A shared link named like a seed is an ordinary name collision — the
    /// seed is the user's preset now, so the import asks instead of
    /// planting a twin. (Also exactly how a deleted seed comes back from
    /// the site: the link creates it fresh.)
    func testAnImportedLinkCollidesWithTheSeedHonestly() {
        let presets = PresetStore(defaults: defaults)
        let link = PresetLink(
            name: "Drop D", templateID: "guitar", strings: [38, 45, 50, 55, 59, 64])

        let resolution = PresetImport.resolve(
            link: link, existing: presets.existingNames(templateID: "guitar"))

        guard case .nameTaken(let existingID, _, _) = resolution else {
            return XCTFail("the seed's name is taken, like anyone's")
        }
        XCTAssertEqual(existingID, "seed:guitar:drop-d")

        // And after deleting the seed, the same link recreates it clean.
        presets.remove(id: "seed:guitar:drop-d")
        XCTAssertEqual(
            PresetImport.resolve(
                link: link, existing: presets.existingNames(templateID: "guitar")),
            .create(name: "Drop D"))
    }

    /// Renaming a seed makes it fully the user's: the rename stamps it, so
    /// it now WINS merges — including against another device's unrenamed
    /// copy.
    func testARenamedSeedBecomesTheUsersAndSyncs() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer {
            phone.destroy()
            mac.destroy()
        }

        XCTAssertTrue(phone.presets.rename(id: "seed:guitar:open-g", to: "Slide"))
        phone.engine.sync()
        mac.engine.sync()

        XCTAssertEqual(
            mac.presets.presets.first { $0.id == "seed:guitar:open-g" }?.name, "Slide")
    }
}

/// The display name follows the user's presets now that the catalog only
/// knows Standard.
@MainActor
final class TuningDisplayNameTests: XCTestCase {
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

    /// Standard is the template's own definition — named without consulting
    /// any preset.
    func testStandardIsStandard() {
        let (presets, instruments) = makeStores()
        let guitar = instruments.instance(id: Instrument.guitar.id)!

        XCTAssertEqual(presets.tuningDisplayName(for: guitar), "Standard")
    }

    /// Hand-tune to a seeded preset's pitches and the pill says its name —
    /// identity still follows the values, through the presets now.
    func testPitchesMatchingAPresetTakeItsName() {
        let (presets, instruments) = makeStores()
        let guitar = Instrument.guitar.id
        instruments.setTuning(id: guitar, strings: [38, 45, 50, 55, 59, 64])

        XCTAssertEqual(
            presets.tuningDisplayName(for: instruments.instance(id: guitar)!), "Drop D")
    }

    /// Renamed, the pitches carry the USER'S word — their name is never
    /// overridden by what the catalog used to call it.
    func testARenamedPresetNamesThePitchesItsWay() {
        let (presets, instruments) = makeStores()
        let guitar = Instrument.guitar.id
        presets.rename(id: "seed:guitar:drop-d", to: "T-bird")
        instruments.setTuning(id: guitar, strings: [38, 45, 50, 55, 59, 64])

        XCTAssertEqual(
            presets.tuningDisplayName(for: instruments.instance(id: guitar)!), "T-bird")
    }

    /// Deleted, the honest answer is Custom: nothing the user owns has a
    /// name for those pitches.
    func testDeletedPresetsPitchesAreCustom() {
        let (presets, instruments) = makeStores()
        let guitar = Instrument.guitar.id
        presets.remove(id: "seed:guitar:drop-d")
        instruments.setTuning(id: guitar, strings: [38, 45, 50, 55, 59, 64])

        XCTAssertEqual(
            presets.tuningDisplayName(for: instruments.instance(id: guitar)!), "Custom")
    }
}

/// Old catalog pins survive the model change.
@MainActor
final class CatalogPinMigrationTests: XCTestCase {
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

    /// A pin at "catalog:guitar:Drop D" — minted when Drop D was catalog —
    /// re-points at the seeded preset, so the launch chip keeps working.
    /// Standard pins stay catalog pins, since Standard stayed catalog.
    func testCatalogPinsMigrateToSeedIDs() throws {
        let pins = [
            PresetPin(instrumentID: "guitar", presetID: "catalog:guitar:Drop D"),
            PresetPin(instrumentID: "guitar", presetID: "catalog:guitar:Standard"),
            PresetPin(instrumentID: "violin", presetID: "some-user-preset-id"),
        ]
        defaults.set(try JSONEncoder().encode(pins), forKey: "presetPins.v1")

        let settings = Settings(defaults: defaults)

        XCTAssertEqual(
            settings.presetPins.map(\.presetID),
            [
                "seed:guitar:drop-d",
                "catalog:guitar:Standard",
                "some-user-preset-id",
            ])
    }

    /// The migration runs once: pins made AFTER it (even ones that look
    /// catalog-shaped) are left alone.
    func testMigrationRunsOnce() throws {
        _ = Settings(defaults: defaults)  // first launch migrates (nothing)
        let pins = [PresetPin(instrumentID: "guitar", presetID: "catalog:guitar:Drop D")]
        defaults.set(try JSONEncoder().encode(pins), forKey: "presetPins.v1")

        let settings = Settings(defaults: defaults)

        XCTAssertEqual(settings.presetPins.map(\.presetID), ["catalog:guitar:Drop D"])
    }
}
