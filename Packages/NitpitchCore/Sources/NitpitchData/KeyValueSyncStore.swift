@preconcurrency import Combine
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
public protocol KeyValueSyncStore: AnyObject, Sendable {
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

/// Sendable because the engine hands a store to a detached task (the
/// cold-daemon availability read); every conformer is responsible for its
/// own internal synchronization, as `UbiquitousSyncStore` documents.

/// `NSUbiquitousKeyValueStore`, as the engine sees it. Deliberately thin:
/// everything worth testing lives above this line.
/// `@unchecked Sendable`, and the check is the lock below: `isAvailable` is
/// read from a detached task (`SyncEngine.begin` moves the cold-daemon call
/// off the main thread) and its cache is cleared from a main-queue
/// notification, so the two genuinely race. Everything else here is either
/// immutable or `NSUbiquitousKeyValueStore`'s own thread-safe API.
public final class UbiquitousSyncStore: KeyValueSyncStore, @unchecked Sendable {
    private let store = NSUbiquitousKeyValueStore.default
    private let subject = PassthroughSubject<Void, Never>()
    private var observer: NSObjectProtocol?

    private var identityObserver: NSObjectProtocol?
    /// Guards `cachedAvailability` alone — the one piece of mutable state
    /// two threads touch.
    private let availabilityLock = NSLock()

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
            self?.clearAvailabilityCache()
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
        #if os(watchOS)
        // watchOS DEFINES `ubiquityIdentityToken` as always nil — signed in
        // or not — while KVS itself works there (watchOS 9+), and there is
        // no public account signal without a CloudKit container this app
        // doesn't have. So the wrist reports available and lets the OS do
        // what it does when genuinely signed out: keep writes local until
        // an account appears. Less honest than the phone's gate, but the
        // alternative was a sync switch that could never be turned on
        // (field-found on the first wrist sync attempt).
        return true
        #else
        availabilityLock.lock()
        if let cachedAvailability {
            availabilityLock.unlock()
            return cachedAvailability
        }
        availabilityLock.unlock()
        // The daemon call stays OUTSIDE the lock: it can block for real
        // time on a cold start, and a second caller racing to the same
        // answer is cheaper than holding a lock across it.
        let available = FileManager.default.ubiquityIdentityToken != nil
        availabilityLock.lock()
        cachedAvailability = available
        availabilityLock.unlock()
        return available
        #endif
    }

    private var cachedAvailability: Bool?

    private func clearAvailabilityCache() {
        availabilityLock.lock()
        cachedAvailability = nil
        availabilityLock.unlock()
    }

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
public final class EphemeralSyncStore: KeyValueSyncStore, @unchecked Sendable {
    /// Locked for the same reason the real store is: `SyncEngine.begin`
    /// reads through a detached task while the app writes from main.
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    /// Always available: UI tests run on simulators with no iCloud
    /// account, and the switch must stay exercisable there.
    public var isAvailable: Bool { true }

    public func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: Data?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }

    public var allKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.keys)
    }

    public func synchronize() {}

    public var externalChanges: AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }
}
