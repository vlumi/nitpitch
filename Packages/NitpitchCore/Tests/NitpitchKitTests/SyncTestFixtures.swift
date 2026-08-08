import Combine
import NitpitchCore
import XCTest

@testable import NitpitchKit

/// A key-value store that behaves like iCloud's without being it: a
/// dictionary, plus the change notification, plus the ability to stand in
/// for a *second device* by having two engines share one instance.
///
/// This is why `KeyValueSyncStore` is a protocol. Real KVS ignores writes
/// on the simulator and propagates on its own schedule, so none of the
/// behaviour below could be asserted against it.
final class FakeSyncStore: KeyValueSyncStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let subject = PassthroughSubject<Void, Never>()
    private(set) var synchronizeCount = 0

    /// The signed-in state, script-controlled: flip it and deliver an
    /// external change, the way `NSUbiquityIdentityDidChange` arrives.
    var availability = true

    var isAvailable: Bool {
        availabilityReads += 1
        return availability
    }

    func data(forKey key: String) -> Data? { storage[key] }

    func set(_ data: Data?, forKey key: String) {
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }

    var allKeys: [String] { Array(storage.keys) }

    func synchronize() { synchronizeCount += 1 }

    /// Every read of `isAvailable`, so a test can prove the launch path
    /// didn't ask (the real call reaches the ubiquity daemon).
    private(set) var availabilityReads = 0

    func recordAvailabilityRead() { availabilityReads += 1 }

    var externalChanges: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    /// What another device would see arriving.
    func deliverExternalChange() { subject.send() }
}

/// One device, as the sync tests model it: its own defaults suite, its own
/// stores, and a cloud shared with whatever other devices a test makes.
/// Shared by the engine tests and the launch-path tests — one definition,
/// so the two can't drift apart.
@MainActor
struct SyncTestDevice {
    let instruments: InstrumentStore
    let presets: PresetStore
    let settings: Settings
    let engine: SyncEngine
    let defaults: UserDefaults
    let suiteName: String

    /// A device sharing `store`. `enabled` mirrors a user who has already
    /// turned the switch on.
    init(sharing store: FakeSyncStore, enabled: Bool = true) {
        let name = "fi.misaki.nitpitch.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        let instruments = InstrumentStore(defaults: suite, seedReference: { .standard })
        let presets = PresetStore(defaults: suite)
        let settings = Settings(defaults: suite)
        let engine = SyncEngine(
            store: store, instruments: instruments, presets: presets,
            settings: settings, defaults: suite)
        if enabled { engine.setEnabled(true) }
        self.instruments = instruments
        self.presets = presets
        self.settings = settings
        self.engine = engine
        self.defaults = suite
        self.suiteName = name
    }

    func destroy() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
