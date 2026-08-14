import Combine
import Foundation

/// The transport syncing needs, reduced to what it actually uses: read a
/// key, write a key, list what's there, and say when someone else changed
/// something.
///
/// A protocol rather than `NSUbiquitousKeyValueStore` directly, for one
/// reason: iCloud can't be tested. KVS ignores writes on the simulator,
/// propagates on its own schedule, and needs two signed-in devices to show
/// its interesting behaviour at all. Behind this seam `SyncEngine` runs
/// against `FakeSyncStore` in unit tests — a dictionary that delivers
/// changes when told to — so the pushing, applying and conflict handling
/// are all exercised deterministically. What remains untested is the six
/// lines of `UbiquitousSyncStore`, which are a straight forwarding.
public protocol KeyValueSyncStore: AnyObject {
    /// Whether the cloud is reachable at all — no iCloud account means KVS
    /// accepts writes locally and never moves them, which is worse than
    /// failing: the toggle would claim to sync while syncing nothing.
    var isAvailable: Bool { get }
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    /// Every key currently stored, for finding records this device has
    /// never seen.
    var allKeys: [String] { get }
    /// Push pending writes. KVS also syncs on its own; this asks it to
    /// hurry.
    func synchronize()
    /// Fires when the store changed underneath us — another device wrote.
    var externalChanges: AnyPublisher<Void, Never> { get }
}

/// `NSUbiquitousKeyValueStore`, as the engine sees it. Deliberately thin:
/// everything worth testing lives above this line.
public final class UbiquitousSyncStore: KeyValueSyncStore {
    private let store = NSUbiquitousKeyValueStore.default
    private let subject = PassthroughSubject<Void, Never>()
    private var observer: NSObjectProtocol?

    private var identityObserver: NSObjectProtocol?

    public init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [subject] _ in
            subject.send()
        }
        // Signing in or out of iCloud is a change of world: the engine
        // re-reads availability and re-syncs off the same signal.
        identityObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil, queue: .main
        ) { [weak self, subject] _ in
            self?.cachedAvailability = nil
            subject.send()
        }
        // NOT synchronize() here. Registering observers is free; talking to
        // the iCloud daemon is not, and this type is constructed on the
        // launch path. The first `synchronize()` rides the engine's first
        // sync, which the view schedules off the main thread.
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let identityObserver { NotificationCenter.default.removeObserver(identityObserver) }
    }

    /// Whether this device is signed in to iCloud — the same check donpa
    /// ships (`ubiquityIdentityToken`), proven in production there.
    ///
    /// Cached, because the underlying call reaches the ubiquity daemon and
    /// can take real time on a cold start — the engine asks on every sync,
    /// and the answer only changes when the account does (which arrives as
    /// `NSUbiquityIdentityDidChange`, where the cache is dropped).
    public var isAvailable: Bool {
        if let cachedAvailability { return cachedAvailability }
        let available = FileManager.default.ubiquityIdentityToken != nil
        cachedAvailability = available
        return available
    }

    private var cachedAvailability: Bool?

    public func data(forKey key: String) -> Data? { store.data(forKey: key) }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            store.set(data, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    public var allKeys: [String] { Array(store.dictionaryRepresentation.keys) }

    public func synchronize() { store.synchronize() }

    public var externalChanges: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
}

/// A key-value store that goes nowhere — the UI-test stand-in for iCloud.
/// `LaunchStores` hands this out under `-uitest-clean` so a test run can
/// neither read nor write the developer's real account.
public final class EphemeralSyncStore: KeyValueSyncStore {
    private var storage: [String: Data] = [:]

    public init() {}

    /// Always available: UI tests run on simulators with no iCloud
    /// account, and the switch must stay exercisable there.
    public var isAvailable: Bool { true }

    public func data(forKey key: String) -> Data? { storage[key] }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }

    public var allKeys: [String] { Array(storage.keys) }

    public func synchronize() {}

    public var externalChanges: AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }
}

/// Moves records between the local stores and a key-value store, applying
/// `SyncMerge`'s rules in both directions.
///
/// **One key per record, not one blob per store.** A blob makes every edit
/// a whole-collection write, so two devices editing different instruments
/// at the same time is a conflict rather than two independent facts — and
/// KVS resolves whole-key conflicts by discarding one side entirely. Per
/// record, that same pair of edits merges cleanly because they never touch
/// the same key.
