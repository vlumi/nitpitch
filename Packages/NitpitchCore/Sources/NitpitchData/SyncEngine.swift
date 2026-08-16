import Combine
import Foundation
import NitpitchCore

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
    enum Kind: String, CaseIterable {
        case instrument = "i."
        case preset = "p."

        var tombstonesKey: String { "\(rawValue)tombstones" }

        /// Whether a store key holds one record's payload (not a
        /// tombstones list, not a settings key).
        static func isRecordKey(_ key: String) -> Bool {
            allCases.contains { key.hasPrefix($0.rawValue) }
                && !allCases.map(\.tombstonesKey).contains(key)
        }
    }

    /// Whether syncing is on. Off by default — "nothing leaves the device"
    /// is a shipped promise, and turning it off must be the state a user
    /// who never asked for sync stays in.
    @Published public private(set) var isEnabled: Bool

    /// When this device last completed a merge, for the settings screen's
    /// reassurance line. Nil until the first one.
    @Published public private(set) var lastSyncedAt: Date?

    /// Whether the cloud can be reached at all (signed in to iCloud). The
    /// switch disables against this rather than letting the user turn on
    /// a sync that would silently move nothing.
    @Published public private(set) var isCloudAvailable: Bool

    let store: KeyValueSyncStore
    let instruments: InstrumentStore
    let presets: PresetStore
    let settings: Settings
    let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    /// True while `apply` is writing into the stores, so the store's own
    /// change notification doesn't bounce straight back out as a push.
    private var isApplying = false

    enum Key {
        static let enabled = "sync.enabled.v1"
        static let lastSyncedAt = "sync.lastSyncedAt.v1"
        /// The v1 blob's stamp and key, read only by the one-shot migration.
        static let settingsStamp = "sync.settingsModifiedAt.v1"
        static let remoteSettings = "s.settings"
        static let localStampsMigrated = "sync.perSetting.localMigrated.v1"
        static let favoritesOrder = "s.favoritesOrder"
        static let pinsOrder = "s.pinsOrder"
        static let naming = "s.naming"
    }

    /// One KVS key per user-set flag: the id rides after the prefix.
    enum FlagKind: String, CaseIterable {
        case instrumentFavorite = "sf.i."
        case presetPin = "sf.pin."
        case presetFavorite = "sf.pf."
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
        // Deliberately NOT `store.isAvailable` and NOT `start()`: this
        // initializer runs while the first frame is being built, and both
        // reach the iCloud daemon — `ubiquityIdentityToken` and
        // `synchronize()` are variable-latency calls that made a cold
        // launch visibly slow. Assume unavailable until `begin()` says
        // otherwise; the switch reads disabled for that instant, which is
        // the honest answer while nothing is known.
        self.isCloudAvailable = false
    }

    /// Start syncing, off the launch path. The view calls this from a
    /// `.task`, so the first daemon round trip happens after the app is on
    /// screen rather than before it.
    public func begin() async {
        guard !hasBegun else { return }
        hasBegun = true
        // The slow part, moved off the main thread: both of these can block
        // on a cold ubiquity daemon.
        let available = await Task.detached { [store] in store.isAvailable }.value
        if available != isCloudAvailable { isCloudAvailable = available }
        guard isEnabled else { return }
        start()
        sync()
    }

    private var hasBegun = false

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
            // The switch is only reachable once the UI is up, so `begin()`
            // has run and availability is known.
            hasBegun = true
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
            .sink { [weak self] in
                guard let self else { return }
                // Signing in/out arrives on this same signal.
                let available = self.store.isAvailable
                if available != self.isCloudAvailable { self.isCloudAvailable = available }
                self.sync()
            }
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
        // Unavailable is a hard stop, not a degraded mode: KVS accepts
        // writes with no account and never moves them, so "synced" here
        // would be a lie the UI then repeats.
        guard isEnabled, store.isAvailable else { return }
        // No pre-merge settings stamping anymore: every flag is stamped AT
        // THE ACT by its store (merging is done BY SETTING), so there is
        // nothing here to bring up to date — and nothing here to get wrong.
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

        // Before any merge, on this device's very first join only: same-id
        // records edited on BOTH sides keep both versions (the older edit
        // moves to a fresh id) — see SyncEngine+FirstJoin.
        duplicateFirstJoinConflicts()

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

    func records<Record: Decodable>(of kind: Kind, as: Record.Type) -> [Record] {
        store.allKeys
            .filter { $0.hasPrefix(kind.rawValue) && $0 != kind.tombstonesKey }
            .compactMap { read(Record.self, key: $0) }
    }

    private func tombstones(for kind: Kind) -> Set<Tombstone> {
        read(Set<Tombstone>.self, key: kind.tombstonesKey) ?? []
    }

    // MARK: - Outbound

    /// Publish the local state: one key per record, plus the tombstones
    /// and the synced settings (whose half lives in SyncEngine+Settings,
    /// beside its inbound twin).
    private func push() {
        guard isEnabled, store.isAvailable else { return }
        pushRecords()
        pruneDeletedRecordKeys()
        pushSettings()
    }

    private func pushRecords() {
        for instance in instruments.instances {
            write(instance, key: Kind.instrument.rawValue + instance.id)
        }
        for preset in presets.presets {
            write(preset, key: Kind.preset.rawValue + preset.id)
        }
        write(instruments.tombstones, key: Kind.instrument.tombstonesKey)
        write(presets.tombstones, key: Kind.preset.tombstonesKey)
    }

    /// A deleted record's key goes too — the tombstone is what carries
    /// the deletion, and leaving the payload behind would have every
    /// future device download a record it must immediately discard.
    private func pruneDeletedRecordKeys() {
        let live =
            Set(instruments.instances.map { Kind.instrument.rawValue + $0.id })
            .union(presets.presets.map { Kind.preset.rawValue + $0.id })
        for key in store.allKeys where Kind.isRecordKey(key) && !live.contains(key) {
            store.set(nil, forKey: key)
        }
    }

    func write<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        // KVS coalesces identical writes anyway, but skipping them keeps
        // the change notification from ping-ponging between devices.
        guard store.data(forKey: key) != data else { return }
        store.set(data, forKey: key)
    }

    /// `write`'s inbound twin: one decoded value per key, or nil for
    /// absent-or-undecodable — the same answer, because a payload this
    /// device can't read must never beat what it has.
    func read<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

}

/// One user-set flag on the wire — a star, a pin — stamped with the moment
/// the user set it. Unstamped flags never travel: they're install seeds,
/// and every device grows its own.
struct SettingFlag: Codable, Equatable {
    var on: Bool
    var modifiedAt: Date?
}

/// A whole-value order (favorites, pins) — one stamp, cosmetic stakes.
struct SettingsOrder: Codable, Equatable {
    var order: [String]
    var modifiedAt: Date?
}

/// One stamped scalar preference on the wire (notation today).
struct SettingScalar: Codable, Equatable {
    var value: String
    var modifiedAt: Date?
}

/// The v1 settings blob, kept decode-only for the one-shot migration into
/// per-setting flags. Whole-value LWW on this is what a wrong stamp once
/// used to wipe months of stars with — see `migrateSettingsBlobIfNeeded`.
struct SyncedSettings: Codable, Equatable {
    var favorites: [String]
    var presetPins: [PresetPin]
    var presetFavorites: Set<String>
    var modifiedAt: Date?
}

extension PresetPin {
    /// The flag id ("instrumentID→presetID") read back into a pin — the
    /// separator can't occur in either half (template ids, UUIDs, seed ids).
    init?(flagID: String) {
        let parts = flagID.split(separator: "→", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        self.init(instrumentID: String(parts[0]), presetID: String(parts[1]))
    }
}
