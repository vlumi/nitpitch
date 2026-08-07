import Combine
import Foundation
import NitpitchCore

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

    public init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [subject] _ in
            subject.send()
        }
        store.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
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
public final class EphemeralSyncStore: KeyValueSyncStore {
    private var storage: [String: Data] = [:]

    public init() {}

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
@MainActor
public final class SyncEngine: ObservableObject {
    /// Where a record lives, and what it is. The prefix keeps instruments
    /// and presets from colliding in one flat namespace.
    private enum Kind: String, CaseIterable {
        case instrument = "i."
        case preset = "p."

        var tombstonesKey: String { "\(rawValue)tombstones" }
    }

    /// Whether syncing is on. Off by default — "nothing leaves the device"
    /// is a shipped promise, and turning it off must be the state a user
    /// who never asked for sync stays in.
    @Published public private(set) var isEnabled: Bool

    /// When this device last completed a merge, for the settings screen's
    /// reassurance line. Nil until the first one.
    @Published public private(set) var lastSyncedAt: Date?

    private let store: KeyValueSyncStore
    private let instruments: InstrumentStore
    private let presets: PresetStore
    private let settings: Settings
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    /// True while `apply` is writing into the stores, so the store's own
    /// change notification doesn't bounce straight back out as a push.
    private var isApplying = false

    private enum Key {
        static let enabled = "sync.enabled.v1"
        static let lastSyncedAt = "sync.lastSyncedAt.v1"
        static let settingsStamp = "sync.settingsModifiedAt.v1"
        static let remoteSettings = "s.settings"
        static let lastStampedSettings = "sync.lastStampedSettings.v1"
    }

    public init(
        store: KeyValueSyncStore,
        instruments: InstrumentStore,
        presets: PresetStore,
        settings: Settings,
        defaults: UserDefaults
    ) {
        self.store = store
        self.instruments = instruments
        self.presets = presets
        self.settings = settings
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Key.enabled)
        self.lastSyncedAt = defaults.object(forKey: Key.lastSyncedAt) as? Date
        if isEnabled { start() }
    }

    /// Turn syncing on or off. Enabling merges immediately — the point of
    /// the toggle is the other device's instruments appearing, and waiting
    /// for an unprompted KVS notification would make that look broken.
    /// Disabling stops listening and pushes nothing further; what's
    /// already in iCloud stays there, because deleting another device's
    /// only copy is not what "stop syncing this device" means.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
        if enabled {
            start()
            sync()
        } else {
            cancellables.removeAll()
        }
    }

    /// Listen in both directions: remote changes come in, local changes go
    /// out.
    private func start() {
        store.externalChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sync() }
            .store(in: &cancellables)

        // The stores announce themselves through `objectWillChange`, which
        // fires *before* the value settles — hence the hop to the next
        // runloop turn before reading it.
        for publisher in [
            instruments.objectWillChange.eraseToAnyPublisher(),
            presets.objectWillChange.eraseToAnyPublisher(),
            settings.objectWillChange.eraseToAnyPublisher(),
        ] {
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    guard let self, !self.isApplying else { return }
                    self.push()
                }
                .store(in: &cancellables)
        }
    }

    /// A full round: take what's out there, merge it with what's here,
    /// keep the result locally and publish it back.
    public func sync() {
        guard isEnabled else { return }
        // Stamp FIRST. A local edit made since the last sync is not yet
        // dated, and `apply` is about to weigh it against the cloud's
        // copy — undated, it loses, and the merge overwrites the very
        // change the user just made.
        stampSettingsIfChanged()
        apply()
        push()
        store.synchronize()
        lastSyncedAt = Date()
        defaults.set(lastSyncedAt, forKey: Key.lastSyncedAt)
    }

    // MARK: - Inbound

    /// Merge everything the key-value store holds into the local stores.
    private func apply() {
        isApplying = true
        defer { isApplying = false }

        let now = Date()

        // Order matters, and it is not the obvious one. The stones must be
        // applied to the records BEFORE being pruned against them:
        // pruning first asks "does this record still exist?" of a list
        // that hasn't heard about the deletion yet, so the device holding
        // the doomed record drops the very stone that was meant to kill it
        // — and re-uploads the record forever.
        let instrumentStones = instruments.tombstones.union(tombstones(for: .instrument))
        let mergedInstruments = SyncMerge.mergedRecords(
            local: instruments.instances,
            remote: records(of: .instrument, as: InstrumentInstance.self),
            tombstones: instrumentStones)
        instruments.adopt(
            mergedInstruments,
            tombstones: SyncMerge.mergedTombstones(
                local: instrumentStones, remote: [],
                survivors: mergedInstruments, now: now))

        let presetStones = presets.tombstones.union(tombstones(for: .preset))
        let mergedPresets = SyncMerge.mergedRecords(
            local: presets.presets,
            remote: records(of: .preset, as: Preset.self),
            tombstones: presetStones)
        presets.adopt(
            mergedPresets,
            tombstones: SyncMerge.mergedTombstones(
                local: presetStones, remote: [],
                survivors: mergedPresets, now: now))

        applySettings()
    }

    /// The synced slice of Settings — pins and their order, and the preset
    /// favorites. Device-shaped state (which rack rows are expanded, strips
    /// on the Mac) deliberately stays local: it describes this screen, not
    /// this user's setup.
    private func applySettings() {
        guard let data = store.data(forKey: Key.remoteSettings),
            let remote = try? JSONDecoder().decode(SyncedSettings.self, from: data)
        else { return }
        let local = SyncedSettings(
            favorites: settings.favorites,
            presetPins: settings.presetPins,
            presetFavorites: presets.favoriteIDs,
            modifiedAt: settingsStamp)
        let winner = SyncMerge.mergedValue(
            local: local, localModifiedAt: local.modifiedAt,
            remote: remote, remoteModifiedAt: remote.modifiedAt)
        guard winner != local else { return }
        settings.favorites = winner.favorites
        settings.presetPins = winner.presetPins
        presets.adoptFavorites(winner.presetFavorites)
        // Adopt the winner's stamp too, or this device claims the merged
        // value as its own newer edit and pushes it back forever.
        defaults.set(winner.modifiedAt, forKey: Key.settingsStamp)
        lastStampedSettings = winner
    }

    private func records<Record: Decodable>(of kind: Kind, as: Record.Type) -> [Record] {
        store.allKeys
            .filter { $0.hasPrefix(kind.rawValue) && $0 != kind.tombstonesKey }
            .compactMap { store.data(forKey: $0) }
            .compactMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    private func tombstones(for kind: Kind) -> Set<Tombstone> {
        guard let data = store.data(forKey: kind.tombstonesKey),
            let stored = try? JSONDecoder().decode(Set<Tombstone>.self, from: data)
        else { return [] }
        return stored
    }

    // MARK: - Outbound

    /// Publish the local state: one key per record, plus the tombstones
    /// and the synced settings.
    private func push() {
        guard isEnabled else { return }
        // Every outbound path lands here, so this is where the settings
        // stamp has to be brought up to date: a value pushed without one
        // is a value that loses every merge it takes part in.
        stampSettingsIfChanged()
        for instance in instruments.instances {
            write(instance, key: Kind.instrument.rawValue + instance.id)
        }
        for preset in presets.presets {
            write(preset, key: Kind.preset.rawValue + preset.id)
        }
        write(instruments.tombstones, key: Kind.instrument.tombstonesKey)
        write(presets.tombstones, key: Kind.preset.tombstonesKey)

        // A deleted record's key goes too — the tombstone is what carries
        // the deletion, and leaving the payload behind would have every
        // future device download a record it must immediately discard.
        let live =
            Set(instruments.instances.map { Kind.instrument.rawValue + $0.id })
            .union(presets.presets.map { Kind.preset.rawValue + $0.id })
        for key in store.allKeys
        where Kind.allCases.contains(where: { key.hasPrefix($0.rawValue) })
            && !Kind.allCases.map(\.tombstonesKey).contains(key)
            && !live.contains(key)
        {
            store.set(nil, forKey: key)
        }

        write(
            SyncedSettings(
                favorites: settings.favorites,
                presetPins: settings.presetPins,
                presetFavorites: presets.favoriteIDs,
                modifiedAt: settingsStamp),
            key: Key.remoteSettings)
    }

    private func write<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        // KVS coalesces identical writes anyway, but skipping them keeps
        // the change notification from ping-ponging between devices.
        guard store.data(forKey: key) != data else { return }
        store.set(data, forKey: key)
    }

    /// Settings carry one stamp for the whole synced slice — they're a
    /// value, not a collection of records, so one date is the currency.
    private var settingsStamp: Date? {
        defaults.object(forKey: Key.settingsStamp) as? Date
    }

    /// Stamp the synced settings only when they actually moved.
    ///
    /// Stamping on every store change looks harmless and is not: renaming
    /// an instrument would mark this device's untouched pins as freshly
    /// edited, and they would then beat the other device's real ones. A
    /// stamp has to mean "this value changed here", nothing looser.
    private func stampSettingsIfChanged() {
        let current = localSettings
        guard current != lastStampedSettings else { return }
        lastStampedSettings = current
        defaults.set(Date(), forKey: Key.settingsStamp)
    }

    /// The synced slice as it stands locally.
    private var localSettings: SyncedSettings {
        SyncedSettings(
            favorites: settings.favorites,
            presetPins: settings.presetPins,
            presetFavorites: presets.favoriteIDs,
            modifiedAt: settingsStamp)
    }

    /// The last synced-settings value this device stamped, compared field
    /// by field — the stamp itself is excluded, since it's the answer and
    /// not part of the question.
    private var lastStampedSettings: SyncedSettings? {
        get {
            guard let data = defaults.data(forKey: Key.lastStampedSettings) else { return nil }
            return try? JSONDecoder().decode(SyncedSettings.self, from: data)
        }
        set {
            guard let value = newValue, let data = try? JSONEncoder().encode(value) else { return }
            defaults.set(data, forKey: Key.lastStampedSettings)
        }
    }
}

/// The slice of `Settings` that describes the user's setup rather than this
/// device's screen, as one synced value.
struct SyncedSettings: Codable, Equatable {
    var favorites: [String]
    var presetPins: [PresetPin]
    var presetFavorites: Set<String>
    var modifiedAt: Date?

    /// Equality over the CONTENT, ignoring the stamp: "did this value
    /// change?" must not be answered by the date that records the answer.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.favorites == rhs.favorites && lhs.presetPins == rhs.presetPins
            && lhs.presetFavorites == rhs.presetFavorites
    }
}
