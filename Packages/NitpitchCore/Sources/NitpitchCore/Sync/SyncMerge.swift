import Foundation

/// One syncable thing, as the merge sees it: an id, when it last changed,
/// and whether the change was a deletion.
///
/// The store types (`InstrumentInstance`, `Preset`) conform rather than the
/// merge knowing them — this file has no idea what an instrument is, which
/// is what lets one set of rules serve both and be tested against neither.
public protocol SyncRecord: Equatable {
    var syncID: String { get }
    /// When any field last changed. Optional because every record stored
    /// before syncing existed decodes without one; `SyncMerge` reads a
    /// missing stamp as the beginning of time (see `mergedRecords`).
    var syncModifiedAt: Date? { get }
}

/// A deletion, remembered. Without one, deleting on this device and syncing
/// with a device that still has the record merges the record straight back
/// in: the other copy looks like news, because absence carries no date.
///
/// Tombstones are small (an id and a date) and are pruned once they're older
/// than any device could plausibly still be offline (`Tombstone.lifetime`).
public struct Tombstone: Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let deletedAt: Date

    public init(id: String, deletedAt: Date) {
        self.id = id
        self.deletedAt = deletedAt
    }

    /// How long a deletion is remembered. Six months is far past any
    /// realistic offline stretch for a device that still holds the record,
    /// and the whole set is a few hundred bytes even for a heavy user.
    public static let lifetime: TimeInterval = 60 * 60 * 24 * 182

    /// Whether this deletion has outlived its usefulness at `now`.
    public func isExpired(at now: Date) -> Bool {
        now.timeIntervalSince(deletedAt) > Self.lifetime
    }
}

/// The merge rules: last-writer-wins per record, deletion by tombstone.
///
/// Every function here is pure — two sides in, one merged side out — so the
/// whole of syncing's decision-making is testable with no iCloud, no
/// network, and no devices (see `SyncMergeTests`). What `NitpitchKit` adds
/// on top is transport only: which keys to write and when to read them.
///
/// **Why last-writer-wins, and not something cleverer.** The records are
/// small, self-contained value types edited by one person, usually one
/// device at a time. Field-level merging would let a device that changed
/// only the name resurrect a tuning the other device deliberately replaced
/// — a half-record nobody saved. Whole-record LWW can lose an edit when two
/// devices race, but it never invents a state that never existed.
public enum SyncMerge {
    /// Merge one collection of records.
    ///
    /// A record survives when it exists on either side and no tombstone
    /// postdates it; between two copies of the same id, the newer stamp
    /// wins. A record with no stamp at all loses to any stamped copy —
    /// pre-sync data yields to anything that knows when it happened — and
    /// order follows `local`, so the local list doesn't reshuffle under the
    /// user when a remote change arrives.
    public static func mergedRecords<Record: SyncRecord>(
        local: [Record],
        remote: [Record],
        tombstones: Set<Tombstone>
    ) -> [Record] {
        var byID: [String: Record] = [:]
        var order: [String] = []
        for record in local + remote {
            let id = record.syncID
            if let existing = byID[id] {
                byID[id] = newer(existing, record)
            } else {
                byID[id] = record
                order.append(id)
            }
        }

        // A deletion beats a record it postdates. An edit made *after* the
        // deletion wins instead: the user changed their mind on some device,
        // and the surviving edit is the later intent.
        var deathDates: [String: Date] = [:]
        for stone in tombstones {
            deathDates[stone.id] = max(deathDates[stone.id] ?? .distantPast, stone.deletedAt)
        }

        return order.compactMap { id in
            guard let record = byID[id] else { return nil }
            if let died = deathDates[id], stamp(record) <= died { return nil }
            return record
        }
    }

    /// The surviving deletions: both sides' tombstones, minus any whose
    /// record has since been edited on either side (a resurrection the
    /// merge just honored — keeping the stone would delete it again on the
    /// next round trip), minus the expired.
    public static func mergedTombstones<Record: SyncRecord>(
        local: Set<Tombstone>,
        remote: Set<Tombstone>,
        survivors: [Record],
        now: Date
    ) -> Set<Tombstone> {
        let alive = Set(survivors.map(\.syncID))
        var latest: [String: Tombstone] = [:]
        for stone in local.union(remote) where !alive.contains(stone.id) {
            if let existing = latest[stone.id], existing.deletedAt >= stone.deletedAt { continue }
            latest[stone.id] = stone
        }
        return Set(latest.values.filter { !$0.isExpired(at: now) })
    }

    /// A whole-value setting — an ORDER of favorites or pins: one value,
    /// one stamp, newer wins, and a side that has never been stamped
    /// yields. Reserved for values whose lost race costs cosmetics only;
    /// anything whose loss would be DATA syncs per flag (`mergedFlag`).
    public static func mergedValue<Value>(
        local: Value, localModifiedAt: Date?,
        remote: Value, remoteModifiedAt: Date?
    ) -> Value {
        guard let remoteDate = remoteModifiedAt else { return local }
        guard let localDate = localModifiedAt else { return remote }
        return remoteDate > localDate ? remote : local
    }

    /// One user-set flag — a star, a pin: merging is done BY SETTING, and
    /// a stamp exists only for a value the user actually set. The rules,
    /// each one a promise:
    ///
    /// - **Never-set can never wipe set**: a nil stamp yields to any stamp,
    ///   so a fresh install's unset (or seeded) state loses to months of
    ///   the other device's choices.
    /// - **A stamped OFF is a real act**: it beats an older ON — unstarring
    ///   on one device sticks — and loses to a newer ON.
    /// - **Ties break to ON, on both sides**: `Date()` is coarse enough for
    ///   two devices to collide, and local-wins would resolve the tie
    ///   differently on each device — the one outcome that never converges.
    ///   ON is the deterministic pick that keeps the star.
    public static func mergedFlag(
        localOn: Bool, localModifiedAt: Date?,
        remoteOn: Bool, remoteModifiedAt: Date?
    ) -> (on: Bool, modifiedAt: Date?) {
        guard let remoteDate = remoteModifiedAt else { return (localOn, localModifiedAt) }
        guard let localDate = localModifiedAt else { return (remoteOn, remoteDate) }
        guard localDate != remoteDate else { return (localOn || remoteOn, localDate) }
        return remoteDate > localDate ? (remoteOn, remoteDate) : (localOn, localDate)
    }

    private static func newer<Record: SyncRecord>(_ lhs: Record, _ rhs: Record) -> Record {
        let left = stamp(lhs)
        let right = stamp(rhs)
        guard left == right else { return right > left ? rhs : lhs }
        // A tie is not "the same save". Two devices seed their factory
        // instruments on first launch, and `Date()` is coarse enough that
        // both stamps land identically — so an EDITED record can tie with
        // a pristine one, and preferring the local copy would decide it
        // differently on each device. That is the one outcome the merge
        // must never produce, since neither side would ever converge.
        //
        // Break it on the content instead: a total order both devices
        // compute the same way. Which record wins is arbitrary; that they
        // agree is not.
        return tiebreak(rhs) > tiebreak(lhs) ? rhs : lhs
    }

    /// A stable, content-derived ordering for records whose stamps tie.
    /// Any total function of the value works — this one is cheap and
    /// deterministic across devices and launches (unlike `hashValue`,
    /// which Swift seeds randomly per process).
    private static func tiebreak<Record: SyncRecord>(_ record: Record) -> String {
        String(describing: record)
    }

    /// A record's stamp, with missing read as the beginning of time.
    private static func stamp<Record: SyncRecord>(_ record: Record) -> Date {
        record.syncModifiedAt ?? .distantPast
    }
}
