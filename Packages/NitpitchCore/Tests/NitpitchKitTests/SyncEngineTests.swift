import Combine
import NitpitchCore
import XCTest

@testable import NitpitchData
@testable import NitpitchKit

/// The transport half of syncing: what reaches the cloud, what comes back,
/// and what happens when two devices disagree. `SyncMergeTests` proves the
/// rules; these prove the engine applies them to the real stores.
@MainActor
final class SyncEngineTests: XCTestCase {
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

    // MARK: - Off by default

    /// "Nothing leaves the device" is a shipped promise. A user who never
    /// asks for syncing must stay in a state where nothing is written at
    /// all — not merely where nothing is read back.
    func testDisabledEngineWritesNothing() {
        let cloud = FakeSyncStore()
        let device = SyncTestDevice(sharing: cloud, enabled: false)
        defer { device.destroy() }

        XCTAssertFalse(device.engine.isEnabled, "off by default")
        device.instruments.rename(id: Instrument.violin.id, to: "Private")
        device.engine.sync()

        XCTAssertTrue(cloud.allKeys.isEmpty, "nothing leaves the device")
    }

    /// The toggle persists, so the promise isn't re-broken (or re-made) at
    /// every launch.
    func testEnabledStatePersists() {
        let cloud = FakeSyncStore()
        let device = SyncTestDevice(sharing: cloud)
        defer { device.destroy() }

        let relaunched = SyncEngine(
            store: cloud, instruments: device.instruments, presets: device.presets,
            settings: device.settings, defaults: device.defaults)

        XCTAssertTrue(relaunched.isEnabled)
    }

    // MARK: - Two devices

    /// The headline: rename an instrument on one device, see it on the
    /// other.
    func testEditOnOneDeviceReachesTheOther() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }

        phone.instruments.rename(id: Instrument.violin.id, to: "Konzertmeister")
        phone.engine.sync()
        mac.engine.sync()

        XCTAssertEqual(mac.instruments.instance(id: Instrument.violin.id)?.name, "Konzertmeister")
    }

    /// A preset saved on one device arrives whole on the other — payload
    /// included, since a preset that syncs its name but not its pitches
    /// would be worse than one that doesn't sync at all.
    func testPresetsSyncWithTheirPayload() throws {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }

        let guitar = phone.instruments.instance(id: Instrument.guitar.id)!
        phone.instruments.setTuning(id: guitar.id, strings: [38, 45, 50, 55, 59, 64])  // drop D
        let saved = phone.presets.save(
            phone.instruments.instance(id: guitar.id)!, named: "Drop D", includeReference: true)!
        phone.engine.sync()
        mac.engine.sync()

        let arrived = try XCTUnwrap(mac.presets.presets.first { $0.id == saved.id })
        XCTAssertEqual(arrived.name, "Drop D")
        XCTAssertEqual(arrived.strings, [38, 45, 50, 55, 59, 64])
        XCTAssertEqual(arrived.referenceHz, saved.referenceHz)
    }

    /// The factory seed's stable ids doing their job end to end: two
    /// devices that each seeded themselves must merge to one list of
    /// instruments, not two of everything.
    func testTwoSeededDevicesDoNotDoubleTheList() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }

        let before = phone.instruments.instances.count
        phone.engine.sync()
        mac.engine.sync()
        phone.engine.sync()

        XCTAssertEqual(phone.instruments.instances.count, before)
        XCTAssertEqual(mac.instruments.instances.count, before)
    }

    /// Delete on one device, and the other's copy goes — the tombstone
    /// crossing the wire is what makes this work.
    func testDeletionPropagates() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        phone.engine.sync()
        mac.engine.sync()

        phone.instruments.remove(id: Instrument.viola.id)
        phone.engine.sync()
        mac.engine.sync()

        XCTAssertNil(mac.instruments.instance(id: Instrument.viola.id))
        // ...and the payload key is gone too, so a third device never
        // downloads a record it would have to discard on arrival.
        XCTAssertFalse(cloud.allKeys.contains("i.\(Instrument.viola.id)"))
    }

    /// A deletion must not come back on the next round trip. This is the
    /// case that fails loudly in the field and silently in a naive
    /// implementation: the other device re-uploads its surviving copy.
    func testDeletionDoesNotResurrectOnTheNextRound() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        phone.engine.sync()
        mac.engine.sync()

        phone.instruments.remove(id: Instrument.viola.id)
        for _ in 0..<3 {
            phone.engine.sync()
            mac.engine.sync()
        }

        XCTAssertNil(phone.instruments.instance(id: Instrument.viola.id), "stays deleted here")
        XCTAssertNil(mac.instruments.instance(id: Instrument.viola.id), "and there")
    }

    /// Both devices edit the same instrument while apart; the later edit
    /// is what they converge on, and they agree about which that was.
    func testConflictingEditsConvergeOnTheLater() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        let violin = Instrument.violin.id

        phone.instruments.rename(id: violin, to: "From the phone")
        mac.instruments.rename(id: violin, to: "From the Mac")  // later
        phone.engine.sync()
        mac.engine.sync()
        phone.engine.sync()

        XCTAssertEqual(phone.instruments.instance(id: violin)?.name, "From the Mac")
        XCTAssertEqual(mac.instruments.instance(id: violin)?.name, "From the Mac")
    }

    /// Editing *different* instruments at the same time is not a conflict
    /// — which is the whole reason for one key per record rather than one
    /// blob per store. Both edits must survive.
    func testIndependentEditsBothSurvive() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        phone.engine.sync()
        mac.engine.sync()

        phone.instruments.rename(id: Instrument.violin.id, to: "Phone's violin")
        mac.instruments.rename(id: Instrument.guitar.id, to: "Mac's guitar")
        phone.engine.sync()
        mac.engine.sync()
        phone.engine.sync()

        XCTAssertEqual(phone.instruments.instance(id: Instrument.violin.id)?.name, "Phone's violin")
        XCTAssertEqual(phone.instruments.instance(id: Instrument.guitar.id)?.name, "Mac's guitar")
    }

    // MARK: - Settings

    /// Pins are part of the user's setup and travel; the rack's expansion
    /// state describes one screen and stays home.
    func testPinsSyncButDeviceStateDoesNot() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }
        phone.engine.sync()
        mac.engine.sync()

        phone.settings.favorites = [Instrument.cello.id]
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

    // MARK: - Inbound notification

    /// A change arriving from another device merges without anyone asking
    /// — that notification is the only thing that makes sync feel live
    /// rather than manual.
    func testExternalChangeTriggersAMerge() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        let mac = SyncTestDevice(sharing: cloud)
        defer { phone.destroy(); mac.destroy() }

        phone.instruments.rename(id: Instrument.violin.id, to: "Arrived by itself")
        phone.engine.sync()

        cloud.deliverExternalChange()
        // The engine hops to the main queue before merging.
        let merged = expectation(description: "merged")
        DispatchQueue.main.async { merged.fulfill() }
        wait(for: [merged], timeout: 1)

        XCTAssertEqual(
            mac.instruments.instance(id: Instrument.violin.id)?.name, "Arrived by itself")
    }

    /// Enabling merges at once. Waiting for an unprompted notification
    /// would make the toggle look broken for however long iCloud took.
    func testEnablingMergesImmediately() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        defer { phone.destroy() }
        phone.instruments.rename(id: Instrument.violin.id, to: "Already here")
        phone.engine.sync()

        let mac = SyncTestDevice(sharing: cloud, enabled: false)
        defer { mac.destroy() }
        XCTAssertNotEqual(mac.instruments.instance(id: Instrument.violin.id)?.name, "Already here")

        mac.engine.setEnabled(true)

        XCTAssertEqual(mac.instruments.instance(id: Instrument.violin.id)?.name, "Already here")
    }

    /// No iCloud account is a hard stop, not a degraded mode: KVS accepts
    /// writes locally and never moves them, so an engine that kept going
    /// would tell the UI "synced" while syncing nothing.
    func testNoAccountMeansNothingIsWrittenOrClaimed() {
        let cloud = FakeSyncStore()
        cloud.availability = false
        let device = SyncTestDevice(sharing: cloud)
        defer { device.destroy() }

        XCTAssertFalse(device.engine.isCloudAvailable)
        device.instruments.rename(id: Instrument.violin.id, to: "Nowhere to go")
        device.engine.sync()

        XCTAssertTrue(cloud.allKeys.isEmpty, "nothing written")
        XCTAssertNil(device.engine.lastSyncedAt, "and nothing claimed")
    }

    /// Signing in arrives as an identity change; the engine notices and
    /// the first real sync happens without anyone toggling anything.
    func testSigningInCatchesUp() {
        let cloud = FakeSyncStore()
        cloud.availability = false
        let device = SyncTestDevice(sharing: cloud)
        defer { device.destroy() }
        device.engine.sync()
        XCTAssertTrue(cloud.allKeys.isEmpty)

        cloud.availability = true
        cloud.deliverExternalChange()
        let caught = expectation(description: "caught up")
        DispatchQueue.main.async { caught.fulfill() }
        wait(for: [caught], timeout: 1)

        XCTAssertTrue(device.engine.isCloudAvailable)
        XCTAssertFalse(cloud.allKeys.isEmpty, "the catch-up sync ran")
    }

    /// Turning sync off leaves what's already in iCloud alone: another
    /// device may hold its only copy of those records, and "stop syncing
    /// this device" is not "delete my things everywhere".
    func testDisablingLeavesTheCloudIntact() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        defer { phone.destroy() }
        phone.engine.sync()
        let keysWhileOn = Set(cloud.allKeys)
        XCTAssertFalse(keysWhileOn.isEmpty)

        phone.engine.setEnabled(false)
        phone.instruments.rename(id: Instrument.violin.id, to: "Local only")
        phone.engine.sync()

        XCTAssertEqual(Set(cloud.allKeys), keysWhileOn, "nothing added, nothing removed")
    }
}

extension SyncEngineTests {
    /// A factory instrument must lose to a real edit, whichever device
    /// made it and whenever. Setting up a NEW device is the sharp case:
    /// its pristine seed is by definition the most recently written thing
    /// on it, and stamping the seed with `Date()` would let it overwrite
    /// the name a user gave that instrument on their other device.
    @MainActor
    func testAFreshInstallDoesNotOverwriteRealEdits() {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        defer { phone.destroy() }
        phone.instruments.rename(id: Instrument.violin.id, to: "Konzertmeister")
        phone.engine.sync()

        // A device set up afterwards — its seed is newer than the rename.
        let mac = SyncTestDevice(sharing: cloud)
        defer { mac.destroy() }
        mac.engine.sync()
        phone.engine.sync()

        XCTAssertEqual(mac.instruments.instance(id: Instrument.violin.id)?.name, "Konzertmeister")
        XCTAssertEqual(phone.instruments.instance(id: Instrument.violin.id)?.name, "Konzertmeister")
    }
}
