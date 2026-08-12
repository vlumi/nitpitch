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
    /// The catalog of known tunings for this instrument — which is now just
    /// Standard, deliberately.
    ///
    /// Standard is the only tuning that is a fact about the TEMPLATE rather
    /// than a thing a user owns: it's what the instrument's name means.
    /// Everything else that used to live here (Drop D, DADGAD, the opens)
    /// ships as factory-SEEDED PRESETS instead (`factoryTunings`, seeded by
    /// `PresetStore`): present by default, but ordinary — deletable,
    /// renameable, shareable, synced. The long tail (scordatura, historical
    /// setups) lives on nitpitch.app as links, and the seeded ones are
    /// mirrored there too, so deleting one is never final.
    public var knownTunings: [Tuning] {
        [Tuning(name: "Standard", strings: strings)]
    }

    /// The tunings every fresh install starts with, per template — the
    /// SEED LIST, not a catalog: `PresetStore` turns these into ordinary
    /// presets exactly once, and from then on they're the user's.
    ///
    /// Deliberately short: common enough to belong in every copy of the
    /// app. Trimming this list only affects fresh installs — existing users
    /// keep (or have already deleted) their copies, and nitpitch.app
    /// carries every entry regardless.
    public var factoryTunings: [Tuning] {
        switch id {
        case "guitar":
            return [
                Tuning(name: "Drop D", strings: [38, 45, 50, 55, 59, 64]),
                Tuning(name: "DADGAD", strings: [38, 45, 50, 55, 57, 62]),
                Tuning(name: "Open G", strings: [38, 43, 50, 55, 59, 62]),
                Tuning(name: "Half-step down", strings: strings.map { $0 - 1 }),
            ]
        case "bass-guitar":
            return [
                Tuning(name: "Drop D", strings: [26, 33, 38, 43]),
                Tuning(name: "Half-step down", strings: strings.map { $0 - 1 }),
            ]
        default:
            return []
        }
    }

    /// The catalog entry matching `strings` exactly — now only ever
    /// Standard, or nil. Named-tuning identity beyond Standard follows the
    /// user's presets by value (`PresetStore.tuningDisplayName`), because
    /// those names are theirs now.
    public func knownTuning(matching strings: [Int]) -> Tuning? {
        knownTunings.first { $0.strings == strings }
    }
}
