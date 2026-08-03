import Foundation

/// A named way to tune an instrument: the pitches, and what the tuning is
/// called when it's called anything.
///
/// Purely about *pitches* — the string count belongs to the instrument that
/// owns the strings (a physical fact), which is why a tuning can only ever be
/// applied to an instrument with the same number of them.
public struct Tuning: Equatable, Hashable, Sendable {
    /// Canonical name ("Standard", "Drop D"), or nil for an unnamed custom
    /// tuning. Untranslated; the UI localizes via the string catalog.
    public let name: String?
    /// Open strings, low to high, as MIDI note numbers.
    public let strings: [Int]

    public init(name: String?, strings: [Int]) {
        self.name = name
        self.strings = strings
    }

    public var isCustom: Bool { name == nil }
}

extension Instrument {
    /// The catalog of known tunings for this instrument, standard first.
    ///
    /// Deliberately short: only the ones common enough to belong in every
    /// copy of the app. The long tail (scordatura, historical setups) is the
    /// preset library's job — hosted on the site, imported as links — so the
    /// picker stays uncluttered (ROADMAP § 1).
    public var knownTunings: [Tuning] {
        var tunings = [Tuning(name: "Standard", strings: strings)]
        switch id {
        case "guitar":
            tunings += [
                Tuning(name: "Drop D", strings: [38, 45, 50, 55, 59, 64]),
                Tuning(name: "DADGAD", strings: [38, 45, 50, 55, 57, 62]),
                Tuning(name: "Open G", strings: [38, 43, 50, 55, 59, 62]),
                Tuning(name: "Half-step down", strings: strings.map { $0 - 1 }),
            ]
        case "bass-guitar":
            tunings += [
                Tuning(name: "Drop D", strings: [26, 33, 38, 43]),
                Tuning(name: "Half-step down", strings: strings.map { $0 - 1 }),
            ]
        default:
            break
        }
        return tunings
    }

    /// The catalog entry matching `strings` exactly, or nil for a custom
    /// tuning. Matching by pitches rather than storing a name means a custom
    /// tuning that happens to equal Drop D *is* Drop D — identity follows the
    /// values, the way a musician would call it.
    public func knownTuning(matching strings: [Int]) -> Tuning? {
        knownTunings.first { $0.strings == strings }
    }
}
