import Combine
import Foundation
import NitpitchCore

/// User-visible preferences, persisted to the injected defaults.
///
/// The `defaults` are injected rather than reaching for `.standard` so UI tests
/// get the wiped suite (see `LaunchStores`) and unit tests can pass a throwaway.
public final class Settings: ObservableObject {
    private enum Key {
        static let referenceHz = "referenceHz"
        static let noteNaming = "noteNaming"
        static let appearance = "appearance"
        static let favorites = "favoriteInstruments"
        static let stripsOnMac = "stripsOnMac"
        static let stripsLowOnTop = "stripsLowOnTop"
        static let presetPins = "presetPins.v1"
    }

    private let defaults: UserDefaults

    @Published public var reference: ReferencePitch {
        didSet { defaults.set(reference.hz, forKey: Key.referenceHz) }
    }

    @Published public var naming: NoteNaming {
        didSet { defaults.set(naming.rawValue, forKey: Key.noteNaming) }
    }

    @Published public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Instruments pinned to the launch screen, in pin order. Stored as ids so
    /// the list survives instruments gaining state of their own later
    /// (favorites are pinned instrument *instances* — AGENTS.md).
    @Published public var favorites: [String] {
        didSet { defaults.set(favorites, forKey: Key.favorites) }
    }

    /// Mac only: strips are a deliberate toggle there, because a window edge
    /// being dragged is not a request to change metaphors — on iOS the
    /// device's shape decides, since rotation is a gesture.
    @Published public var stripsOnMac: Bool {
        didSet { defaults.set(stripsOnMac, forKey: Key.stripsOnMac) }
    }

    /// Vertical string order, shared by the strips and the dial grid's rows:
    /// false (default) = low string at the bottom — pitch intuition, and how
    /// tabs are written; true = low on top, the looking-down-at-the-neck
    /// view. Low-at-bottom is the default because it's the only order with
    /// a universal referent: bowed instruments have no view in which their
    /// strings stack vertically at all, and fretted players read tab, which
    /// puts the thickest string at the bottom. Handedness never enters it:
    /// a lefty's mirrored stringing and mirrored hold cancel, so the
    /// looking-down order is the same.
    @Published public var stripsLowOnTop: Bool {
        didSet { defaults.set(stripsLowOnTop, forKey: Key.stripsLowOnTop) }
    }

    /// Launch-screen shortcuts to a setup: THIS instrument, THAT preset.
    /// Deliberately a pair — a preset alone is a template-wide stamp, so a
    /// bare preset favorite would surface on every same-shaped instrument;
    /// the pin is what binds it to one (AGENTS.md, "The tuning flow").
    @Published public var presetPins: [PresetPin] {
        didSet {
            guard let data = try? JSONEncoder().encode(presetPins) else { return }
            defaults.set(data, forKey: Key.presetPins)
        }
    }

    public func togglePin(instrumentID: String, presetID: String) {
        let pin = PresetPin(instrumentID: instrumentID, presetID: presetID)
        if let index = presetPins.firstIndex(of: pin) {
            presetPins.remove(at: index)
        } else {
            presetPins.append(pin)
        }
    }

    public func isPinned(instrumentID: String, presetID: String) -> Bool {
        presetPins.contains(PresetPin(instrumentID: instrumentID, presetID: presetID))
    }

    public func toggleFavorite(_ id: String) {
        if let index = favorites.firstIndex(of: id) {
            favorites.remove(at: index)
        } else {
            favorites.append(id)
        }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        // `double(forKey:)` returns 0 for a missing key, which ReferencePitch
        // would clamp to the low bound — check presence explicitly.
        let storedHz = defaults.object(forKey: Key.referenceHz) as? Double
        self.reference = storedHz.map(ReferencePitch.init(hz:)) ?? .standard
        self.naming =
            (defaults.string(forKey: Key.noteNaming).flatMap(NoteNaming.init(rawValue:)))
            ?? .english
        self.appearance =
            (defaults.string(forKey: Key.appearance).flatMap(AppearancePreference.init(rawValue:)))
            ?? .system
        // Violin starts pinned: it's the app's reason for existing, and the
        // one-tap chip is the whole point of the row. An empty default would
        // hide the feature exactly from the person it was built for.
        self.favorites = defaults.stringArray(forKey: Key.favorites) ?? [Instrument.violin.id]
        self.stripsOnMac = defaults.bool(forKey: Key.stripsOnMac)
        self.stripsLowOnTop = defaults.bool(forKey: Key.stripsLowOnTop)
        if let data = defaults.data(forKey: Key.presetPins),
            let stored = try? JSONDecoder().decode([PresetPin].self, from: data)
        {
            self.presetPins = stored
        } else {
            self.presetPins = []
        }
    }
}

/// One launch-screen shortcut: an instrument opened INTO a preset. The pin
/// is the pair — presets stay instrument-agnostic stamps.
public struct PresetPin: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let instrumentID: String
    public let presetID: String

    public var id: String { "\(instrumentID)→\(presetID)" }

    public init(instrumentID: String, presetID: String) {
        self.instrumentID = instrumentID
        self.presetID = presetID
    }
}
