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
        static let instrumentID = "instrumentID"
        static let noteNaming = "noteNaming"
        static let appearance = "appearance"
        static let favorites = "favoriteInstruments"
    }

    private let defaults: UserDefaults

    @Published public var reference: ReferencePitch {
        didSet { defaults.set(reference.hz, forKey: Key.referenceHz) }
    }

    @Published public var instrument: Instrument {
        didSet { defaults.set(instrument.id, forKey: Key.instrumentID) }
    }

    @Published public var naming: NoteNaming {
        didSet { defaults.set(naming.rawValue, forKey: Key.noteNaming) }
    }

    @Published public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Instruments pinned to the launch screen, in pin order. Stored as ids so
    /// the list survives instruments gaining state of their own later
    /// (ROADMAP § 1: favourites become pinned instrument *instances*).
    @Published public var favorites: [String] {
        didSet { defaults.set(favorites, forKey: Key.favorites) }
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
        self.instrument =
            (defaults.string(forKey: Key.instrumentID).flatMap(Instrument.named)) ?? .violin
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
    }
}
