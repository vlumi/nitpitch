import Combine
import Foundation
import NitpitchCore

/// A frozen setup under the user's own name — "Bach No. 1", "Tomorrow's gig"
/// — carrying **only the fields it was saved with** (AGENTS.md, "The tuning
/// flow").
///
/// The payload rule is the whole design: a preset that carries pitches and
/// nothing else is exactly what a catalog tuning is, so "a tuning must never
/// change the reference" holds by construction — there is no reference in it
/// to apply. A preset saved with its reference says so, and applies it.
///
/// Never edited in place: loading copies values out, and the only way values
/// flow back is a save — over the same name, deliberately.
public struct Preset: Equatable, Hashable, Codable, Identifiable, Sendable, SyncRecord {
    public let id: String
    /// The user's name for it — why they saved it, not what the tuning is
    /// called. Verbatim in the UI, never localized.
    public var name: String
    /// Which template's instruments this was saved from ("guitar"). Offered
    /// only to instruments of the same template whose string count fits.
    public let templateID: String
    /// The tuning payload: open strings, low to high.
    public let strings: [Int]
    /// The reference payload, or nil when the preset deliberately doesn't
    /// carry one.
    public let referenceHz: Double?
    /// The temperament payload. New saves always carry it — a preset is a
    /// situation, and "quartet, pure fifths" is as much the situation as
    /// A=442 — while nil (every preset saved before temperaments existed)
    /// means "leave the instrument's alone".
    public let temperament: Temperament?
    /// When this preset was last saved — the currency of last-writer-wins
    /// syncing, stamped by `save`. Optional for presets stored before
    /// syncing existed, which `SyncMerge` reads as the beginning of time.
    public var modifiedAt: Date?

    public var syncID: String { id }
    public var syncModifiedAt: Date? { modifiedAt }

    public var reference: ReferencePitch? { referenceHz.map(ReferencePitch.init(hz:)) }

    /// Whether this preset can be loaded onto `instance` at all: same
    /// template, same string count. A mismatch is a type error, not a runtime
    /// surprise — unloadable presets are never offered.
    public func fits(_ instance: InstrumentInstance) -> Bool {
        templateID == instance.templateID && strings.count == instance.strings.count
    }
}

/// Owns the saved presets, persisted like everything else through
/// `LaunchStores.defaults`.
@MainActor
public final class PresetStore: ObservableObject {
    private static let key = "presets.v1"

    @Published public private(set) var presets: [Preset] {
        didSet { save() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
            let stored = try? JSONDecoder().decode([Preset].self, from: data)
        {
            presets = stored
        } else {
            presets = []
        }
    }

    /// The presets loadable onto this instance — favorites first, then the
    /// rest, each block in the order they were saved.
    public func presets(fitting instance: InstrumentInstance) -> [Preset] {
        let fitting = presets.filter { $0.fits(instance) }
        return fitting.filter { isFavorite($0.id) } + fitting.filter { !isFavorite($0.id) }
    }

    /// Preset favorites — "float to the top of every preset list",
    /// template-wide like presets themselves. Stored beside the presets
    /// rather than on them, so old stored payloads need no migration.
    public func isFavorite(_ id: String) -> Bool {
        favoriteIDs.contains(id)
    }

    public func toggleFavorite(_ id: String) {
        objectWillChange.send()
        var ids = favoriteIDs
        if !ids.insert(id).inserted { ids.remove(id) }
        favoriteIDs = ids
    }

    private static let favoritesKey = "presets.favorites.v1"

    /// An existing preset that a save under `name` would replace: same
    /// template, same name (case-insensitively — "gig" and "Gig" are one
    /// intent, not two presets).
    public func existing(named name: String, templateID: String) -> Preset? {
        let folded = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return presets.first {
            $0.templateID == templateID && $0.name.lowercased() == folded
        }
    }

    /// Save the instance's current setup under `name`, carrying its reference
    /// only when asked to. Saving over an existing name replaces that preset
    /// — the caller confirms that intent first (`existing(named:templateID:)`).
    @discardableResult
    public func save(
        _ instance: InstrumentInstance, named name: String, includeReference: Bool,
        includeTemperament: Bool = true
    ) -> Preset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let preset = Preset(
            id: existing(named: trimmed, templateID: instance.templateID)?.id
                ?? UUID().uuidString,
            name: trimmed,
            templateID: instance.templateID,
            strings: instance.strings,
            referenceHz: includeReference ? instance.referenceHz : nil,
            // When carried, carried explicitly — an equal-temperament preset
            // must RESTORE equal when loaded onto a pure instrument, so
            // "equal" and "unspecified" cannot share a spelling. Left out,
            // loading leaves the instrument's temperament alone.
            temperament: includeTemperament ? instance.appliedTemperament : nil,
            modifiedAt: Date())
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        return preset
    }

    public func remove(id: String) {
        guard presets.contains(where: { $0.id == id }) else { return }
        presets.removeAll { $0.id == id }
        // A deletion has to be remembered, not merely performed: absence
        // carries no date, so a device that still holds the preset would
        // merge it straight back (see `SyncMerge`).
        tombstones = SyncMerge.mergedTombstones(
            local: tombstones.union([Tombstone(id: id, deletedAt: Date())]),
            remote: [], survivors: presets, now: Date())
        // The favorite flag dies with the preset; launch pins resolve by
        // lookup, so a dangling pin simply stops rendering.
        if isFavorite(id) { toggleFavorite(id) }
    }

    /// Deletions this device has performed, for the merge. Persisted like
    /// everything else, pruned by age (`Tombstone.lifetime`) whenever one
    /// is added.
    public private(set) var tombstones: Set<Tombstone> {
        get {
            guard let data = defaults.data(forKey: Self.tombstonesKey),
                let stored = try? JSONDecoder().decode(Set<Tombstone>.self, from: data)
            else { return [] }
            return stored
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.tombstonesKey)
        }
    }

    private static let tombstonesKey = "presets.tombstones.v1"

    /// Apply a preset to an instance: the fields it carries, nothing else.
    public func load(_ preset: Preset, onto instance: InstrumentInstance, in store: InstrumentStore)
    {
        guard preset.fits(instance) else { return }
        store.setTuning(id: instance.id, strings: preset.strings)
        if let reference = preset.reference {
            store.setReference(id: instance.id, reference)
        }
        if let temperament = preset.temperament {
            store.setTemperament(id: instance.id, temperament)
        }
        store.presetApplied(id: instance.id, presetID: preset.id)
    }

    /// Install merged state from `SyncEngine` — like `InstrumentStore.adopt`,
    /// no re-stamping: the stamps are what the merge just judged.
    func adopt(_ merged: [Preset], tombstones stones: Set<Tombstone>) {
        if merged != presets { presets = merged }
        if stones != tombstones { tombstones = stones }
    }

    /// The favorite flags as one value, for the synced settings slice.
    var favoriteIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.favoritesKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Self.favoritesKey) }
    }

    func adoptFavorites(_ ids: Set<String>) {
        guard ids != favoriteIDs else { return }
        objectWillChange.send()
        favoriteIDs = ids
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
