import Foundation
import NitpitchCore

/// First-join duplication: nothing anyone did vanishes at the moment sync
/// is first trusted.
///
/// Whole-record LWW silently discards one side when the SAME id — the
/// seeded records, whose ids are identical on every device by construction —
/// was edited on two devices before they ever synced. In steady state a true
/// concurrent edit is undetectable without per-record base-version
/// bookkeeping (differing stamps are what every routine sync looks like),
/// but at FIRST JOIN there is no shared history, so the rule is clean:
/// same id, both sides really stamped, contents differ → keep both. The
/// later edit keeps the id; the other survives as a copy with a fresh id —
/// and "Guitar 2" when the names collide, the keep-both vocabulary the
/// preset-import flow already taught the app. Pins follow the id-keeper;
/// the copy arrives unpinned. Merging "Guitar" and "Guitar 2" back into one
/// is the USER'S cleanup, with tools that already exist.
extension SyncEngine {
    /// Runs once, on the sync a device has never completed before
    /// (`lastSyncedAt` is only written after a full round). Devices that
    /// were already syncing before this feature shipped have a date and
    /// skip it — their history is shared, so the clean rule doesn't hold.
    func duplicateFirstJoinConflicts() {
        guard lastSyncedAt == nil else { return }
        duplicateInstrumentConflicts()
        duplicatePresetConflicts()
    }

    private func duplicateInstrumentConflicts() {
        let remote = records(of: .instrument, as: InstrumentInstance.self)
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }) { first, _ in first }
        var copies: [InstrumentInstance] = []
        for local in instruments.instances {
            guard let other = remoteByID[local.id],
                isRealEdit(local.modifiedAt), isRealEdit(other.modifiedAt),
                instrumentContentDiffers(local, other)
            else { continue }
            // The OLDER edit becomes the copy; the newer keeps the id
            // through the ordinary merge that follows.
            let localIsNewer = stamp(local.modifiedAt) > stamp(other.modifiedAt)
            let loser = localIsNewer ? other : local
            let winner = localIsNewer ? local : other
            // Names taken in the POST-merge world: everything except the
            // conflicting pair (the id will carry the winner's name), so a
            // loser whose name differs keeps it, and one whose name matches
            // the winner's steps aside as "… 2".
            let taken =
                (instruments.instances + remote)
                .filter { $0.id != local.id }
                .map(\.name) + [winner.name] + copies.map(\.name)
            copies.append(instrumentCopy(of: loser, takenNames: taken))
        }
        guard !copies.isEmpty else { return }
        instruments.adopt(
            instruments.instances + copies, tombstones: instruments.tombstones)
    }

    private func duplicatePresetConflicts() {
        let remote = records(of: .preset, as: Preset.self)
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }) { first, _ in first }
        var copies: [Preset] = []
        for local in presets.presets {
            guard let other = remoteByID[local.id],
                isRealEdit(local.modifiedAt), isRealEdit(other.modifiedAt),
                presetContentDiffers(local, other)
            else { continue }
            let localIsNewer = stamp(local.modifiedAt) > stamp(other.modifiedAt)
            let loser = localIsNewer ? other : local
            let winner = localIsNewer ? local : other
            // Preset names are unique per template BY RULE — but the taken
            // set describes the POST-merge world: the conflicting pair's id
            // carries the winner's name, so the loser's own name is free
            // unless it matches the winner's (the common conflict).
            let taken =
                (presets.presets + remote + copies)
                .filter { $0.templateID == loser.templateID && $0.id != local.id }
                .map(\.name) + [winner.name]
            copies.append(
                Preset(
                    id: UUID().uuidString,
                    name: copyName(loser.name, takenNames: taken),
                    templateID: loser.templateID,
                    strings: loser.strings,
                    referenceHz: loser.referenceHz,
                    temperament: loser.temperament,
                    modifiedAt: loser.modifiedAt))
        }
        guard !copies.isEmpty else { return }
        presets.adopt(presets.presets + copies, tombstones: presets.tombstones)
    }

    /// A stamp that means a USER did something: seeds carry `.distantPast`
    /// (instruments) or nil (presets), and neither is an edit.
    private func isRealEdit(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date > .distantPast
    }

    private func stamp(_ date: Date?) -> Date { date ?? .distantPast }

    /// Differing where a USER would see a difference — the stamps and the
    /// usage bookkeeping are noise here, not content.
    private func instrumentContentDiffers(
        _ lhs: InstrumentInstance, _ rhs: InstrumentInstance
    ) -> Bool {
        lhs.name != rhs.name || lhs.strings != rhs.strings
            || lhs.referenceHz != rhs.referenceHz || lhs.temperament != rhs.temperament
            || lhs.isLocked != rhs.isLocked
    }

    private func presetContentDiffers(_ lhs: Preset, _ rhs: Preset) -> Bool {
        lhs.name != rhs.name || lhs.strings != rhs.strings
            || lhs.referenceHz != rhs.referenceHz || lhs.temperament != rhs.temperament
    }

    private func instrumentCopy(
        of instance: InstrumentInstance, takenNames: [String]
    ) -> InstrumentInstance {
        InstrumentInstance(
            id: UUID().uuidString,
            templateID: instance.templateID,
            name: copyName(instance.name, takenNames: takenNames),
            strings: instance.strings,
            referenceHz: instance.referenceHz,
            isLocked: instance.isLocked,
            temperament: instance.temperament,
            loadedPresetID: nil,
            lastUsedAt: instance.lastUsedAt,
            // The copy carries the EDIT'S OWN date: it's the same act,
            // relocated to an id nobody contests.
            modifiedAt: instance.modifiedAt)
    }

    /// The original name when it's free, "Guitar 2" when it isn't — the
    /// same `nextName` the preset-import collision flow uses.
    private func copyName(_ base: String, takenNames: [String]) -> String {
        let folded = Set(takenNames.map { $0.lowercased() })
        guard folded.contains(base.lowercased()) else { return base }
        return PresetImport.nextName(after: base, taken: takenNames)
    }
}
