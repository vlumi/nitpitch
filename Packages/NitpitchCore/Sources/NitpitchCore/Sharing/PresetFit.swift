import Foundation

/// Which of the user's instruments a preset can actually be loaded onto —
/// and what it means when the answer is none.
///
/// A preset fits an instrument when it was saved from the same template AND
/// carries the same number of strings. The count is not a formality: a
/// preset IS its list of pitches, so applying an eight-string tuning to a
/// six-string guitar has no meaning — there are two pitches with nowhere to
/// go.
///
/// The consequence is **orphans**. Instruments have a fixed shape once
/// created, but a preset saved from an instrument that was later deleted —
/// or one that arrived by link for a shape nobody owns — fits nothing. It
/// isn't broken and isn't deleted; it simply has no home yet, and the way
/// back is to create an instrument of that shape. Left unsaid, an orphan
/// looks like a preset that mysteriously refuses to load.
public enum PresetFit {
    /// One instrument, as fitting needs to see it.
    public struct Candidate: Equatable, Sendable {
        public let id: String
        public let name: String
        public let templateID: String
        public let stringCount: Int
        /// When it was last opened — the tie-break when several fit, so
        /// "load it" means the guitar you actually play.
        public let lastUsedAt: Date?

        public init(
            id: String, name: String, templateID: String, stringCount: Int,
            lastUsedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.templateID = templateID
            self.stringCount = stringCount
            self.lastUsedAt = lastUsedAt
        }
    }

    /// The instruments this preset can load onto, most recently used first.
    ///
    /// Order matters where the UI loads without asking: with one candidate
    /// there's nothing to ask, and with several the first is the sensible
    /// default — the instrument the user last had open.
    public static func candidates(
        templateID: String, stringCount: Int, among instruments: [Candidate]
    ) -> [Candidate] {
        instruments
            .filter { $0.templateID == templateID && $0.stringCount == stringCount }
            .sorted { lhs, rhs in
                let left = lhs.lastUsedAt ?? .distantPast
                let right = rhs.lastUsedAt ?? .distantPast
                if left != right { return left > right }
                // Stable past the dates: never reshuffle between renders.
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.id < rhs.id
            }
    }

    /// Whether this preset has nowhere to go — the state worth telling the
    /// user about, since it's the difference between "tap to load" and
    /// "this needs an instrument first".
    public static func isOrphaned(
        templateID: String, stringCount: Int, among instruments: [Candidate]
    ) -> Bool {
        candidates(templateID: templateID, stringCount: stringCount, among: instruments).isEmpty
    }
}
