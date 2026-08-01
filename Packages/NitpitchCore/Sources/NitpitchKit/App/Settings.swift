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
    }
}
