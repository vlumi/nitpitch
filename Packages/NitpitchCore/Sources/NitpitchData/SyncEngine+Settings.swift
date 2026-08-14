import Foundation
import NitpitchCore

/// The settings half of the engine: stars, pins and preset favorites merged
/// BY SETTING (AGENTS rule 8) — split from SyncEngine.swift purely for size,
/// the records half stays there.
extension SyncEngine {
    /// The synced slice of Settings — the stars, the pins, the preset
    /// favorites — merged BY SETTING: each flag is its own stamped value
    /// (`SyncMerge.mergedFlag`), so a device's never-set state can never
    /// wipe another's choices, and two devices editing different flags
    /// apart both keep their edits. The ORDERS are the one whole value
    /// each, where a lost race costs cosmetics. Device-shaped state (rack
    /// expansion, strips on the Mac) deliberately stays local.
    func applySettings() {
        migrateSettingsBlobIfNeeded()

        let favorites = mergedFlags(
            kind: .instrumentFavorite,
            localOn: Set(settings.favorites),
            localStamps: settings.favoriteStamps)
        let favoritesOrder = mergedOrder(
            key: Key.favoritesOrder,
            local: settings.favorites,
            localStamp: settings.favoritesOrderStamp)
        settings.adoptFavorites(
            ordered(members: favorites.on, by: favoritesOrder.order),
            stamps: favorites.stamps,
            orderStamp: favoritesOrder.modifiedAt)

        let pins = mergedFlags(
            kind: .presetPin,
            localOn: Set(settings.presetPins.map(\.id)),
            localStamps: settings.pinStamps)
        let pinsOrder = mergedOrder(
            key: Key.pinsOrder,
            local: settings.presetPins.map(\.id),
            localStamp: settings.pinsOrderStamp)
        settings.adoptPins(
            ordered(members: pins.on, by: pinsOrder.order).compactMap(PresetPin.init(flagID:)),
            stamps: pins.stamps,
            orderStamp: pinsOrder.modifiedAt)

        let presetFavorites = mergedFlags(
            kind: .presetFavorite,
            localOn: presets.favoriteIDs,
            localStamps: presets.favoriteStamps)
        presets.adoptFavorites(presetFavorites.on, stamps: presetFavorites.stamps)

        applyNaming()
    }

    /// Notation is a USER preference (how note names are spelled), not
    /// device-shaped state, so it travels — one stamped scalar, same rules
    /// as every flag: never-set yields, newer wins, and a stamp tie with
    /// differing values breaks on the greater raw value, identically on
    /// both sides (local-wins ties never converge).
    private func applyNaming() {
        var remote: SettingScalar?
        if let data = store.data(forKey: Key.naming) {
            remote = try? JSONDecoder().decode(SettingScalar.self, from: data)
        }
        guard let remote else { return }
        let local = SettingScalar(
            value: settings.naming.rawValue, modifiedAt: settings.namingStamp)
        let winner: SettingScalar
        if local.modifiedAt == remote.modifiedAt, local.value != remote.value {
            winner = local.value > remote.value ? local : remote
        } else {
            winner = SyncMerge.mergedValue(
                local: local, localModifiedAt: local.modifiedAt,
                remote: remote, remoteModifiedAt: remote.modifiedAt)
        }
        guard let naming = NoteNaming(rawValue: winner.value) else { return }
        settings.adoptNaming(naming, stamp: winner.modifiedAt)
    }

    /// Merge every flag either side knows about. Absent everywhere = never
    /// set; the union keeps stamped OFFs alive as values, because "the user
    /// unstarred this" is information the other devices need.
    func mergedFlags(
        kind: FlagKind, localOn: Set<String>, localStamps: [String: Date]
    ) -> (on: Set<String>, stamps: [String: Date]) {
        var remote: [String: SettingFlag] = [:]
        for key in store.allKeys where key.hasPrefix(kind.rawValue) {
            guard let data = store.data(forKey: key),
                let flag = try? JSONDecoder().decode(SettingFlag.self, from: data)
            else { continue }
            remote[String(key.dropFirst(kind.rawValue.count))] = flag
        }
        var on = Set<String>()
        var stamps: [String: Date] = [:]
        for id in localOn.union(localStamps.keys).union(remote.keys) {
            let merged = SyncMerge.mergedFlag(
                localOn: localOn.contains(id), localModifiedAt: localStamps[id],
                remoteOn: remote[id]?.on ?? false, remoteModifiedAt: remote[id]?.modifiedAt)
            if merged.on { on.insert(id) }
            if let stamp = merged.modifiedAt { stamps[id] = stamp }
        }
        return (on, stamps)
    }

    func mergedOrder(
        key: String, local: [String], localStamp: Date?
    ) -> (order: [String], modifiedAt: Date?) {
        var remote: SettingsOrder?
        if let data = store.data(forKey: key) {
            remote = try? JSONDecoder().decode(SettingsOrder.self, from: data)
        }
        let winner = SyncMerge.mergedValue(
            local: SettingsOrder(order: local, modifiedAt: localStamp),
            localModifiedAt: localStamp,
            remote: remote ?? SettingsOrder(order: local, modifiedAt: localStamp),
            remoteModifiedAt: remote?.modifiedAt)
        return (winner.order, winner.modifiedAt)
    }

    /// The order's word applied to the merged membership: listed members in
    /// the order's sequence, unlisted ones appended sorted — deterministic
    /// on every device, so a member the order never met can't scramble it.
    func ordered(members: Set<String>, by order: [String]) -> [String] {
        order.filter(members.contains) + members.subtracting(order).sorted()
    }

    /// The v1 settings blob decomposes into per-setting flags exactly once.
    ///
    /// Local half: a device that stamped the v1 blob had made real choices —
    /// that one date becomes every held membership's flag stamp, once.
    /// Remote half: a stamped v1 blob still in the cloud becomes stamped
    /// flags, but only if no v2 flags exist yet (a v2 fleet has spoken and
    /// the blob is history). The blob key is deleted either way; builds
    /// this old and devices this new don't overlap in a one-user fleet.
    func migrateSettingsBlobIfNeeded() {
        migrateLocalV1Stamps()
        migrateRemoteV1Blob()
    }

    private func migrateLocalV1Stamps() {
        guard !defaults.bool(forKey: Key.localStampsMigrated) else { return }
        defaults.set(true, forKey: Key.localStampsMigrated)
        guard let stamp = defaults.object(forKey: Key.settingsStamp) as? Date else { return }
        migrateLocalMemberships(stamp: stamp)
    }

    private func migrateLocalMemberships(stamp: Date) {
        // Same absent-seed rule as the remote half below: a stamped v1
        // list was "exactly these", so a universal seed it lacks was
        // unstarred — that act survives as a stamped OFF (a stamp for a
        // non-member IS the off flag).
        var favoriteStamps = uniformStamps(settings.favorites, stamp)
        for id in Settings.seededFavorites where !settings.favorites.contains(id) {
            favoriteStamps[id] = stamp
        }
        settings.adoptFavorites(
            settings.favorites,
            stamps: favoriteStamps,
            orderStamp: stamp)
        settings.adoptPins(
            settings.presetPins,
            stamps: uniformStamps(settings.presetPins.map(\.id), stamp),
            orderStamp: stamp)
        presets.adoptFavorites(
            presets.favoriteIDs,
            stamps: uniformStamps(Array(presets.favoriteIDs), stamp))
    }

    private func migrateRemoteV1Blob() {
        guard let data = store.data(forKey: Key.remoteSettings) else { return }
        defer { store.set(nil, forKey: Key.remoteSettings) }
        let hasV2 = store.allKeys.contains { key in
            FlagKind.allCases.contains { key.hasPrefix($0.rawValue) }
        }
        guard !hasV2,
            let blob = try? JSONDecoder().decode(SyncedSettings.self, from: data),
            let stamp = blob.modifiedAt
        else { return }
        for id in blob.favorites {
            write(
                SettingFlag(on: true, modifiedAt: stamp),
                key: FlagKind.instrumentFavorite.rawValue + id)
        }
        // A stamped blob's word was "EXACTLY these": a universal seed
        // absent from it was unstarred by the user, and that act must
        // survive as a stamped OFF or every fresh device re-stars it.
        for id in Settings.seededFavorites where !blob.favorites.contains(id) {
            write(
                SettingFlag(on: false, modifiedAt: stamp),
                key: FlagKind.instrumentFavorite.rawValue + id)
        }
        for pin in blob.presetPins {
            write(
                SettingFlag(on: true, modifiedAt: stamp),
                key: FlagKind.presetPin.rawValue + pin.id)
        }
        for id in blob.presetFavorites {
            write(
                SettingFlag(on: true, modifiedAt: stamp),
                key: FlagKind.presetFavorite.rawValue + id)
        }
        write(SettingsOrder(order: blob.favorites, modifiedAt: stamp), key: Key.favoritesOrder)
        write(
            SettingsOrder(order: blob.presetPins.map(\.id), modifiedAt: stamp),
            key: Key.pinsOrder)
    }

    func uniformStamps(_ ids: [String], _ stamp: Date) -> [String: Date] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, stamp) })
    }

    func pushFlags(kind: FlagKind, on: Set<String>, stamps: [String: Date]) {
        for (id, stamp) in stamps {
            write(
                SettingFlag(on: on.contains(id), modifiedAt: stamp),
                key: kind.rawValue + id)
        }
    }
}
