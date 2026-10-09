import Foundation
import NitpitchCore

/// What a screenshot needs on screen that a pose can't say.
///
/// `-demo-pose` stages the SOUND — the readings every dial shows are the
/// real detector hearing known pitches. This stages the STATE around it:
/// which instruments are starred, which preset is pinned, what the
/// reference and temperament are, whether the app is in Dark, and which
/// sheet is open. Together they make a shot reproducible from launch
/// arguments alone, so capture needs no hands (see `Scripts/shoot.sh
/// --auto`).
///
/// Demo-only by construction: every setter below writes through
/// `LaunchStores.defaults`, which under `-uitest-clean` is a wiped
/// ephemeral suite. A staged run therefore cannot touch real settings,
/// and `apply` refuses outright unless `-demo` is on.
///
/// Syntax — `-demo-stage "key=value;key=value"`, values comma-separated:
///
///     favorites=violin,guitar     star these instrument ids, in this order
///     pin=guitar:drop-d           pin a preset to an instrument (id:preset-slug)
///     reference=442               the reference pitch, in hertz
///     temperament=pure            equal | pure
///     appearance=dark             system | light | dark
///     present=presets             which sheet to open (see `Presentation`)
///     share=drop-d                with present=presets: share this preset
///
/// Unknown keys and unresolvable ids are IGNORED rather than fatal: a
/// screenshot script that mistypes one key should still produce the other
/// six shots, and the miss shows in the image.
public enum DemoStage {
    /// A sheet a staged shot wants open at launch. The grid's tuning menu
    /// is deliberately absent: SwiftUI's `Menu` has no programmatic
    /// presentation, so that one shot stays hand-staged (see
    /// `SCREENSHOTS.md`).
    public enum Presentation: String, Sendable {
        /// The preset browser over the launch screen ("All presets…").
        case presets
        /// The app's settings sheet.
        case settings
    }

    /// The parsed stage, or nil when `-demo-stage` wasn't given.
    public static let current: DemoStage.Values? = {
        guard LaunchStores.isDemo, let raw = LaunchStores.stageArgument else { return nil }
        return Values(raw)
    }()

    public struct Values: Sendable {
        public var favorites: [String] = []
        public var pins: [(instrument: String, preset: String)] = []
        public var referenceHz: Double?
        public var temperament: Temperament?
        public var appearance: AppearancePreference?
        public var present: Presentation?
        public var share: String?

        init(_ raw: String) {
            for pair in raw.split(separator: ";") {
                let halves = pair.split(separator: "=", maxSplits: 1)
                guard halves.count == 2 else { continue }
                assign(
                    key: halves[0].trimmingCharacters(in: .whitespaces),
                    value: halves[1].trimmingCharacters(in: .whitespaces))
            }
        }

        /// One `key=value`. An unknown key is ignored rather than fatal: a
        /// mistyped one should still leave the other six shots capturable,
        /// and the miss shows in the image.
        private mutating func assign(key: String, value: String) {
            switch key {
            case "favorites":
                favorites = value.split(separator: ",").map(String.init)
            case "pin":
                pins += value.split(separator: ",").compactMap { pin in
                    let parts = pin.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    return (String(parts[0]), String(parts[1]))
                }
            case "reference":
                referenceHz = Double(value)
            case "temperament":
                temperament = Temperament(rawValue: value)
            case "appearance":
                appearance = AppearancePreference(rawValue: value)
            case "present":
                present = Presentation(rawValue: value)
            case "share":
                share = value
            default:
                break
            }
        }
    }

    /// Write the staged state into the stores, before the first frame.
    ///
    /// Called from `LaunchStores.make()` so every platform shell gets it
    /// without repeating itself. A no-op unless `-demo` AND `-demo-stage`
    /// are both present.
    /// The three stores a stage writes to.
    public struct Stores {
        let settings: Settings
        let instruments: InstrumentStore
        let presets: PresetStore

        public init(settings: Settings, instruments: InstrumentStore, presets: PresetStore) {
            self.settings = settings
            self.instruments = instruments
            self.presets = presets
        }
    }

    @MainActor
    public static func apply(to stores: Stores) {
        guard LaunchStores.isDemo, let stage = current else { return }
        applyTuning(stage, to: stores)
        applyRack(stage, to: stores)
        if let appearance = stage.appearance {
            stores.settings.appearance = appearance
        }
    }

    /// The reference and temperament — both of which live on the INSTRUMENT,
    /// not only in Settings.
    @MainActor
    private static func applyTuning(_ stage: Values, to stores: Stores) {
        if let hz = stage.referenceHz {
            // Clamps to the offered range, like every other way in.
            let reference = ReferencePitch(hz: hz)
            stores.settings.reference = reference
            // Settings' reference seeds NEW instruments; the factory ones
            // already exist and carry their own, so a staged reference has
            // to reach the instrument the shot is of.
            for instance in stores.instruments.instances {
                stores.instruments.setReference(id: instance.id, reference)
            }
        }
        // Same reason: the shot's instrument isn't necessarily a starred one.
        if let temperament = stage.temperament {
            for instance in stores.instruments.instances {
                stores.instruments.setTemperament(id: instance.id, temperament)
            }
        }
    }

    /// The launch screen's rack: stars, their order, and pins.
    @MainActor
    private static func applyRack(_ stage: Values, to stores: Stores) {
        // Stars and pins go through the toggles, like every other write to
        // them (see AGENTS.md: an unstamped flag is an install seed).
        for id in stage.favorites {
            guard let instanceID = resolve(id, in: stores.instruments),
                !stores.settings.favorites.contains(instanceID)
            else { continue }
            stores.settings.toggleFavorite(instanceID)
        }
        // Order the rack exactly as named, so the shot is deterministic.
        // Assigning the array is enough here and nowhere else: the stars
        // themselves were stamped by `toggleFavorite` above, and a staged
        // run writes to a wiped ephemeral suite that never syncs.
        let staged = stage.favorites.compactMap { resolve($0, in: stores.instruments) }
        if !staged.isEmpty {
            let rest = stores.settings.favorites.filter { !staged.contains($0) }
            stores.settings.favorites = staged + rest
        }

        for pin in stage.pins {
            guard let instanceID = resolve(pin.instrument, in: stores.instruments),
                let preset = preset(named: pin.preset, in: stores.presets)
            else { continue }
            if !stores.settings.isPinned(instrumentID: instanceID, presetID: preset.id) {
                stores.settings.togglePin(instrumentID: instanceID, presetID: preset.id)
            }
            // A pin's CHIP shows only while its row is expanded — pinning
            // without this leaves the rack row bare, which is not what the
            // shot is for.
            if !stores.settings.rackExpanded.contains(instanceID) {
                stores.settings.rackExpanded.append(instanceID)
            }
        }
    }

    /// An instrument by instance id, or by template id ("violin") — the
    /// script says "violin", not a UUID it can't know.
    @MainActor
    private static func resolve(_ id: String, in store: InstrumentStore) -> String? {
        if store.instance(id: id) != nil { return id }
        return store.instances.first { $0.templateID == id }?.id
    }

    /// A preset by id, or by a slug of its name ("drop-d" → "Drop D") —
    /// the script names what a human would, not a UUID it can't know.
    @MainActor
    public static func preset(named needle: String, in store: PresetStore) -> Preset? {
        if let exact = store.presets.first(where: { $0.id == needle }) { return exact }
        let wanted = needle.lowercased()
        return store.presets.first { preset in
            preset.name.lowercased().replacingOccurrences(of: " ", with: "-") == wanted
                || preset.id.hasSuffix(wanted)
        }
    }
}
