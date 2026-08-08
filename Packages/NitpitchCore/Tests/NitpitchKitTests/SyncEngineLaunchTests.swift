import Combine
import NitpitchCore
import XCTest

@testable import NitpitchKit

/// The launch path: what the engine is allowed to do while the first frame
/// is still being built, and what has to wait for `begin()`.
///
/// Its own file because the rule it protects is a performance contract, not
/// a sync rule — reaching the iCloud daemon during view construction made a
/// cold launch visibly slow, and nothing in the merge tests would notice it
/// coming back.
@MainActor
final class SyncEngineLaunchTests: XCTestCase {
    /// Constructing the engine must touch NOTHING: it runs while the first
    /// frame is being built, and both `synchronize()` and the availability
    /// check reach the iCloud daemon at whatever speed it feels like. This
    /// is the regression that made a cold launch visibly slow.
    func testConstructionTouchesNoCloud() {
        let name = "fi.misaki.nitpitch.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        suite.set(true, forKey: "sync.enabled.v1")  // as a relaunch finds it
        let cloud = FakeSyncStore()

        _ = SyncEngine(
            store: cloud,
            instruments: InstrumentStore(defaults: suite, seedReference: { .standard }),
            presets: PresetStore(defaults: suite),
            settings: Settings(defaults: suite),
            defaults: suite)

        XCTAssertEqual(cloud.synchronizeCount, 0, "no daemon round trip at construction")
        XCTAssertEqual(cloud.availabilityReads, 0, "no ubiquity token read either")
        XCTAssertTrue(cloud.allKeys.isEmpty, "and nothing pushed")
    }

    /// …and `begin()` is what actually starts it: a device relaunching with
    /// the switch already on must sync without anyone touching the toggle.
    func testBeginSyncsARelaunchedDevice() async {
        let cloud = FakeSyncStore()
        let phone = SyncTestDevice(sharing: cloud)
        defer { phone.destroy() }
        phone.instruments.rename(id: Instrument.violin.id, to: "From before")
        phone.engine.sync()

        // A second device that already had the switch on, relaunching.
        let name = "fi.misaki.nitpitch.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        suite.set(true, forKey: "sync.enabled.v1")
        let instruments = InstrumentStore(defaults: suite, seedReference: { .standard })
        let engine = SyncEngine(
            store: cloud, instruments: instruments,
            presets: PresetStore(defaults: suite),
            settings: Settings(defaults: suite), defaults: suite)

        await engine.begin()

        XCTAssertTrue(engine.isCloudAvailable)
        XCTAssertEqual(
            instruments.instance(id: Instrument.violin.id)?.name, "From before",
            "the relaunch caught up without any toggling")
    }

    /// `begin()` is idempotent — SwiftUI can run a `.task` again on a view
    /// that reappears, and a second full sync per appearance is waste.
    func testBeginIsIdempotent() async {
        let cloud = FakeSyncStore()
        let device = SyncTestDevice(sharing: cloud)
        defer { device.destroy() }

        await device.engine.begin()
        let after = cloud.synchronizeCount
        await device.engine.begin()

        XCTAssertEqual(cloud.synchronizeCount, after, "the second begin does nothing")
    }
}
