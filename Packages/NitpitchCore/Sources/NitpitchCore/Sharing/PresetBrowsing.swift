import Foundation

/// How the preset browser orders and narrows a collection.
///
/// Pure rules over values, so "recently changed puts undated last" is a
/// test rather than a claim about a screen. The browser passes its presets
/// through as `Item`s — the browser's own vocabulary, not the store's, so
/// this file needs to know nothing about `Preset` or `PresetStore`.
public enum PresetBrowsing {
    /// One row's worth of what ordering needs.
    public struct Item: Equatable, Sendable {
        public let id: String
        public let name: String
        public let templateID: String
        /// Nil for presets saved before stamping existed. Not a date to
        /// invent: "recently changed" sorts them last rather than pretending
        /// they're from 1970 or from now.
        public let modifiedAt: Date?

        public init(id: String, name: String, templateID: String, modifiedAt: Date?) {
            self.id = id
            self.name = name
            self.templateID = templateID
            self.modifiedAt = modifiedAt
        }
    }

    /// The orders offered. Each is a total order — ties break by name, then
    /// id — so the list never reshuffles between identical renders.
    public enum Order: String, CaseIterable, Sendable {
        /// What you just made, received, or edited — the default, because
        /// the reason to open the browser is usually recent.
        case recent
        case name
        /// Grouped by the instrument they fit, alphabetical within.
        case instrument
    }

    /// Order `items`, and narrow to one template when `templateID` is given.
    ///
    /// `displayName` maps a template id to what the user reads, so ordering
    /// by instrument sorts by the visible word ("Bass" before "Guitar")
    /// rather than by an id that happens to spell it differently.
    public static func arrange(
        _ items: [Item],
        order: Order,
        templateID: String? = nil,
        displayName: (String) -> String = { $0 }
    ) -> [Item] {
        let filtered =
            templateID.map { wanted in items.filter { $0.templateID == wanted } }
            ?? items
        switch order {
        case .recent:
            return filtered.sorted { lhs, rhs in
                switch (lhs.modifiedAt, rhs.modifiedAt) {
                case (let left?, let right?):
                    if left != right { return left > right }
                case (nil, .some):
                    // Undated last: an unknown date is not a claim of age.
                    return false
                case (.some, nil):
                    return true
                case (nil, nil):
                    break
                }
                return tiebreak(lhs, rhs)
            }
        case .name:
            return filtered.sorted { lhs, rhs in
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return tiebreak(lhs, rhs)
            }
        case .instrument:
            return filtered.sorted { lhs, rhs in
                let left = displayName(lhs.templateID)
                let right = displayName(rhs.templateID)
                let comparison = left.localizedStandardCompare(right)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return tiebreak(lhs, rhs)
            }
        }
    }

    /// The templates worth offering as filters: the ones that actually have
    /// presets, in display order. A filter that can only produce an empty
    /// list is a promise the collection can't keep.
    public static func filterableTemplates(
        _ items: [Item], displayName: (String) -> String = { $0 }
    ) -> [String] {
        Array(Set(items.map(\.templateID)))
            .sorted {
                displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending
            }
    }

    /// Name, then id — so every order is total and stable. Two presets can
    /// share a name across templates ("Gig" on a guitar and a violin), and
    /// a list that swaps them between renders looks broken.
    private static func tiebreak(_ lhs: Item, _ rhs: Item) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id < rhs.id
    }
}
