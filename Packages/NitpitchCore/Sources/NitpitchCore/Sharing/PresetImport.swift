import Foundation

/// What an arriving link should become, decided before anything is written.
///
/// The rule is the one the app already had for saving: presets are
/// identified for replacement by **template + case-insensitive name**, and
/// overwriting asks first. An import is a save that happens to come from
/// somewhere else, so it behaves the same way rather than inventing a second
/// identity rule.
///
/// The receiver takes **full ownership** of whatever they accept: an
/// imported preset is an ordinary preset, editable and deletable and synced
/// like any other. Nothing in the app can support the alternative — there is
/// no account, no channel to receive corrections through, and no way for a
/// sender to revoke — so "still owned by the sender" would be a promise the
/// architecture can't keep. It would also be fiction within one user's own
/// account, since iCloud sync rewrites presets under last-writer-wins.
public enum PresetImport {
    /// The options an arriving link offers, given what the receiver already
    /// has.
    public enum Resolution: Equatable, Sendable {
        /// Nothing of that name here: it saves as a new preset.
        case create(name: String)
        /// A preset of that name already exists for this template. The user
        /// chooses — the same confirm a local save shows — between taking
        /// the new payload over the old, or keeping both under a numbered
        /// name.
        case nameTaken(existingID: String, name: String, keepBothName: String)
    }

    /// Decide what `link` can become among `existing` presets.
    ///
    /// `existing` is the receiver's presets **for the link's template**;
    /// filtering elsewhere would let a guitar preset collide with a violin
    /// one of the same name, which the app has never treated as the same
    /// thing.
    public static func resolve(
        link: PresetLink,
        existing: [(id: String, name: String)]
    ) -> Resolution {
        let folded = link.name.lowercased()
        guard let match = existing.first(where: { $0.name.lowercased() == folded }) else {
            return .create(name: link.name)
        }
        return .nameTaken(
            existingID: match.id,
            name: link.name,
            keepBothName: nextName(after: link.name, taken: existing.map(\.name)))
    }

    /// "Gig 2", or "Gig 3" when that's taken — the same numbering the
    /// instrument list uses for duplicates, so "keep both" reads as the
    /// familiar move rather than a new concept.
    public static func nextName(after base: String, taken: [String]) -> String {
        let folded = Set(taken.map { $0.lowercased() })
        var number = 2
        while folded.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }
}
