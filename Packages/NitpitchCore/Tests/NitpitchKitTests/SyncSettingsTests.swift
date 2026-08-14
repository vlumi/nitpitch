import Combine
import NitpitchCore
import XCTest

@testable import NitpitchData
@testable import NitpitchKit

/// The settings half of the sync suite: stars, pins and preset favorites
/// merge BY SETTING (AGENTS rule 8) — split from SyncEngineTests purely for
/// size; the record-merge tests stay there.
@MainActor
final class SyncSettingsTests: XCTestCase {
    /// Pins are part of the user's setup and travel; the rack's expansion
    /// state describes one screen and stays home.
    func testPinsSyncButDeviceStateDoesNot() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        phone.engine.sync()
        mac.engine.sync()

        // User ACTS, not raw assignment: only acts stamp, and only stamped
        // flags travel — the per-setting model's whole point.
        phone.settings.toggleFavorite(Instrument.violin.id)  // seed off
        phone.settings.toggleFavorite(Instrument.cello.id)
        phone.settings.togglePin(instrumentID: Instrument.cello.id, presetID: "catalog:cello:Solo")
        phone.settings.toggleRackExpanded(Instrument.cello.id)
        phone.engine.sync()
        mac.engine.sync()

        XCTAssertEqual(mac.settings.favorites, [Instrument.cello.id])
        XCTAssertTrue(
            mac.settings.isPinned(instrumentID: Instrument.cello.id, presetID: "catalog:cello:Solo")
        )
        XCTAssertTrue(mac.settings.rackExpanded.isEmpty, "device-shaped state stays local")
    }

    /// A FRESH JOINER adopts the cloud's settings — never announces its
    /// own. A device that has never stamped is carrying install seeds, and
    /// a seed must lose its first merge (the instrument seeds'
    /// `.distantPast` rule, in whole-value terms). Field-found the hard
    /// way: the first watch to join stamped its factory favorites as
    /// "freshly changed" and wiped months of the phone's stars and pins
    /// off iCloud.
    func testAFreshJoinerAdoptsTheCloudsSettings() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        defer { phone.destroy() }
        phone.settings.toggleFavorite(Instrument.violin.id)  // seed off
        phone.settings.toggleFavorite(Instrument.cello.id)
        phone.settings.togglePin(instrumentID: Instrument.cello.id, presetID: "seed:cello:solo")
        phone.engine.sync()

        // Months later, a brand-new device joins — carrying exactly what a
        // fresh install carries (Settings seeds violin as the first star),
        // never synced, about to enable the switch for the first time.
        let watch = SyncTestDevice(sharing: cloud, enabled: false)
        defer { watch.destroy() }
        XCTAssertEqual(
            watch.settings.favorites, [Instrument.violin.id],
            "the install seed this test exists to keep humble")
        watch.engine.setEnabled(true)
        watch.engine.sync()
        phone.engine.sync()

        XCTAssertEqual(
            watch.settings.favorites, [Instrument.cello.id],
            "the joiner adopts the cloud")
        XCTAssertEqual(
            phone.settings.favorites, [Instrument.cello.id],
            "and the cloud keeps the user's months of setup")
        XCTAssertTrue(
            phone.settings.isPinned(
                instrumentID: Instrument.cello.id, presetID: "seed:cello:solo"),
            "pins survive the join too")

        // The joiner's FIRST REAL CHANGE still syncs — adopting the cloud
        // must not make the device mute.
        watch.settings.toggleFavorite(Instrument.violin.id)
        watch.engine.sync()
        phone.engine.sync()
        XCTAssertEqual(
            phone.settings.favorites, [Instrument.cello.id, Instrument.violin.id],
            "a change made after joining speaks with a real stamp")
    }

    /// THE case whole-value LWW could never merge: two devices editing
    /// DIFFERENT settings while apart. Per-setting stamps keep both.
    func testEditsOnDifferentFlagsBothSurvive() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        phone.engine.sync()
        mac.engine.sync()

        // Apart: the phone stars the cello, the mac pins a preset and
        // favorites one — different flags, same window.
        phone.settings.toggleFavorite(Instrument.cello.id)
        mac.settings.togglePin(instrumentID: Instrument.guitar.id, presetID: "seed:guitar:drop-d")
        mac.presets.toggleFavorite("seed:guitar:open-g")
        phone.engine.sync()
        mac.engine.sync()
        phone.engine.sync()

        for device in [phone, mac] {
            XCTAssertTrue(
                device.settings.favorites.contains(Instrument.cello.id),
                "the phone's star survived")
            XCTAssertTrue(
                device.settings.isPinned(
                    instrumentID: Instrument.guitar.id, presetID: "seed:guitar:drop-d"),
                "the mac's pin survived")
            XCTAssertTrue(
                device.presets.isFavorite("seed:guitar:open-g"),
                "the mac's preset favorite survived")
        }
    }

    /// Unstarring is a real act: a stamped OFF beats the other device's
    /// older ON — and does not resurrect.
    func testUnstarringOnOneDeviceSticks() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        phone.settings.toggleFavorite(Instrument.cello.id)
        phone.engine.sync()
        mac.engine.sync()
        XCTAssertTrue(mac.settings.favorites.contains(Instrument.cello.id))

        mac.settings.toggleFavorite(Instrument.cello.id)  // unstar
        mac.engine.sync()
        phone.engine.sync()
        mac.engine.sync()

        XCTAssertFalse(phone.settings.favorites.contains(Instrument.cello.id))
        XCTAssertFalse(
            mac.settings.favorites.contains(Instrument.cello.id),
            "and the phone's older ON does not resurrect it")
    }

    /// The v1 blob in the cloud decomposes into flags exactly once: a
    /// device still holding the old whole-value settings meets a v2 build
    /// and nothing the user chose is lost.
    func testTheV1BlobMigratesIntoFlags() throws {
        let cloud = FakeSyncStore()
        // A v1-era cloud: the blob as the old engine wrote it, stamped.
        let blob = SyncedSettings(
            favorites: [Instrument.cello.id, Instrument.guitar.id],
            presetPins: [
                PresetPin(instrumentID: Instrument.guitar.id, presetID: "seed:guitar:drop-d")
            ],
            presetFavorites: ["seed:guitar:open-g"],
            modifiedAt: Date())
        cloud.set(try JSONEncoder().encode(blob), forKey: "s.settings")

        let device = SyncTestDevice(sharing: cloud)
        defer { device.destroy() }
        device.engine.sync()

        XCTAssertEqual(
            device.settings.favorites, [Instrument.cello.id, Instrument.guitar.id],
            "membership AND order survive the decomposition")
        XCTAssertTrue(
            device.settings.isPinned(
                instrumentID: Instrument.guitar.id, presetID: "seed:guitar:drop-d"))
        XCTAssertTrue(device.presets.isFavorite("seed:guitar:open-g"))
        XCTAssertNil(cloud.data(forKey: "s.settings"), "the blob is history")
    }
}
