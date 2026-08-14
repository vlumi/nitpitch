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
        static let rackExpanded = "rackExpandedInstruments"
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

    /// Which launch-rack rows show their pin chips — the accordion's
    /// state, persisted: the rack waits as you left it, expanded rows
    /// included.
    @Published public var rackExpanded: [String] {
        didSet { defaults.set(rackExpanded, forKey: Key.rackExpanded) }
    }

    public func toggleRackExpanded(_ id: String) {
        if let index = rackExpanded.firstIndex(of: id) {
            rackExpanded.remove(at: index)
        } else {
            rackExpanded.append(id)
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
        self.rackExpanded = defaults.stringArray(forKey: Key.rackExpanded) ?? []
        if let data = defaults.data(forKey: Key.presetPins),
            let stored = try? JSONDecoder().decode([PresetPin].self, from: data)
        {
            self.presetPins = stored
        } else {
            self.presetPins = []
        }
        migrateCatalogPins()
    }

    private static let catalogPinsMigratedKey = "pins.catalogMigrated.v1"

    /// Catalog tunings past Standard became seeded PRESETS, so pins that
    /// pointed at them ("catalog:guitar:Drop D") re-point at the seeded
    /// preset's id — same launch chip, same tap, new plumbing. One-time;
    /// Standard pins stay catalog pins, since Standard stayed catalog. The
    /// seed id is derivable from the pin's own name by construction, so the
    /// migration needs no store in hand.
    private func migrateCatalogPins() {
        guard !defaults.bool(forKey: Self.catalogPinsMigratedKey) else { return }
        defaults.set(true, forKey: Self.catalogPinsMigratedKey)
        let migrated = presetPins.map { pin -> PresetPin in
            let parts = pin.presetID.split(separator: ":", maxSplits: 2)
            guard parts.count == 3, parts[0] == "catalog", parts[2] != "Standard" else {
                return pin
            }
            return PresetPin(
                instrumentID: pin.instrumentID,
                presetID: PresetStore.seedID(
                    templateID: String(parts[1]), name: String(parts[2])))
        }
        if migrated != presetPins { presetPins = migrated }
    }
}

/// One launch-screen shortcut: an instrument opened INTO a preset. The pin
/// is the pair — presets stay instrument-agnostic stamps.
/// Catalog tunings are pinnable too — "a catalog tuning is exactly a
/// built-in preset that carries pitches and nothing else" — via a synthetic
/// preset id, so a pin stores one string whatever it points at.
public enum CatalogPinID {
    public static func make(templateID: String, tuningName: String) -> String {
        "catalog:\(templateID):\(tuningName)"
    }

    /// The tuning name, when the id is a catalog pin for this template.
    public static func tuningName(in presetID: String, templateID: String) -> String? {
        let prefix = "catalog:\(templateID):"
        guard presetID.hasPrefix(prefix) else { return nil }
        return String(presetID.dropFirst(prefix.count))
    }
}

public struct PresetPin: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let instrumentID: String
    public let presetID: String

    public var id: String { "\(instrumentID)→\(presetID)" }

    public init(instrumentID: String, presetID: String) {
        self.instrumentID = instrumentID
        self.presetID = presetID
    }
}
