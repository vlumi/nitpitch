import Combine
import Foundation
import NitpitchCore

/// An instrument you own: "Strat", "Acoustic", "Violin" — a named instance of
/// a template, holding its own mutable state, autosaved, waiting as you left
/// it (AGENTS.md, "The tuning flow").
///
/// The string array is the *current tuning*; its count is a physical fact of
/// this instrument, set when it's added and changed only by editing the
/// instrument, never by a tuning. The tuning's display name is derived by
/// matching the pitches against the template's catalog — identity follows the
/// values, so nothing here can drift out of sync with what's actually strung.
public struct InstrumentInstance: Equatable, Hashable, Codable, Identifiable, Sendable {
    /// For the default instance of each template this IS the template id
    /// ("violin"), which keeps accessibility identifiers readable and lets
    /// pinned favourites from before instances existed keep working unchanged.
    /// Added instruments get UUIDs.
    public let id: String
    public let templateID: String
    public var name: String
    /// Open strings, low to high — the current tuning.
    public var strings: [Int]
    public var referenceHz: Double
    /// The padlock: a locked instrument's setup is frozen behind the toolbar
    /// toggle.
    public var isLocked: Bool
    /// How the open-string targets divide their intervals — pure fifths for
    /// a violin tuned the orchestra's way. Optional storage: nil means "the
    /// family's default" (pure on bowed instruments, where beatless fifths
    /// by ear ARE pure — equal was a keyboard convention imposed on them;
    /// equal everywhere else) and is what old stored JSON decodes to. An
    /// explicit choice is stored verbatim, so picking Equal on a violin
    /// sticks. Read through `appliedTemperament`; the UI offers a choice on
    /// bowed instruments only — frets are equal temperament cast in metal.
    public var temperament: Temperament?
    /// The preset last applied — the setup's *provenance*. An explicit pick
    /// (another preset, or a tuning from the menu) replaces it; granular
    /// edits (a string stepper, a reference step) keep it, and the pill shows
    /// "T-bird (edited)" while the values have drifted from its payload —
    /// clearing on edit made the pill announce a catalog tuning nobody
    /// picked. Optional and absent from old stored JSON, which decodes as
    /// nil.
    public var loadedPresetID: String?
    /// When this instrument was last opened. Optional: absent from old
    /// stored JSON, never shown to the user.
    public var lastUsedAt: Date?
    /// When any field last changed — the currency of last-writer-wins
    /// syncing (ROADMAP: iCloud sync). Stamped by the store's one update
    /// chokepoint; optional for old stored JSON.
    public var modifiedAt: Date?

    public var reference: ReferencePitch { ReferencePitch(hz: referenceHz) }

    /// The temperament in force — nil storage reads as the family default.
    public var appliedTemperament: Temperament {
        temperament ?? (template?.family == .bowed ? .pure : .equal)
    }

    public var template: Instrument? { Instrument.named(templateID) }

    /// The instrument as the detection stack sees it: the template's family
    /// and this instance's name and strings.
    public var instrument: Instrument {
        Instrument(
            id: id, name: name, strings: strings,
            family: template?.family ?? .other)
    }

    /// What the tuning is called right now: a catalog name when the pitches
    /// match one, "Custom" otherwise.
    public var tuningName: String? {
        template.map { $0.knownTuning(matching: strings)?.name ?? "Custom" }
    }
}

/// Owns every instrument instance, persists them, and hands out the default
/// one per template on demand.
///
/// Persisted as JSON through `LaunchStores.defaults` like everything else, so
/// the UI-test isolation gate stays total.
@MainActor
public final class InstrumentStore: ObservableObject {
    private static let key = "instruments.v1"

    @Published public private(set) var instances: [InstrumentInstance] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    /// Seeds a new instance's reference — "from wherever you came from".
    private let seedReference: () -> ReferencePitch

    public init(defaults: UserDefaults, seedReference: @escaping () -> ReferencePitch) {
        self.defaults = defaults
        self.seedReference = seedReference
        if let data = defaults.data(forKey: Self.key),
            let stored = try? JSONDecoder().decode([InstrumentInstance].self, from: data)
        {
            instances = stored
        } else {
            instances = []
        }
        seedFactoryInstruments()
    }

    private static let seededKey = "instruments.seeded.v1"

    /// The factory list, as real instruments: one ordinary, fully editable
    /// instance per catalog template, so the app is browsable and tunable
    /// from first launch with nothing to add. Runs once (deletions stick
    /// afterwards — an empty list is a legitimate state); ids are the
    /// template ids, DELIBERATELY stable: two devices seed identically, so
    /// a future first sync merges clean instead of doubling the list, and
    /// pre-existing favorites keep resolving.
    private func seedFactoryInstruments() {
        guard !defaults.bool(forKey: Self.seededKey) else { return }
        for template in Instrument.choosable.flatMap(\.instruments)
        where instance(id: template.id) == nil {
            instances.append(
                InstrumentInstance(
                    id: template.id,
                    templateID: template.id,
                    name: template.name,
                    strings: template.strings,
                    referenceHz: seedReference().hz,
                    isLocked: false,
                    loadedPresetID: nil,
                    lastUsedAt: nil))
        }
        defaults.set(true, forKey: Self.seededKey)
    }

    public func instance(id: String) -> InstrumentInstance? {
        instances.first { $0.id == id }
    }

    /// Every instance of one template, default first.
    public func instances(of template: Instrument) -> [InstrumentInstance] {
        instances.filter { $0.templateID == template.id }
            .sorted {
                ($0.id == template.id ? 0 : 1, $0.name) < ($1.id == template.id ? 0 : 1, $1.name)
            }
    }

    /// The name `add(of:)` would give the next instance — for prefilling a
    /// creation prompt without creating anything. Counts the default the
    /// add would materialize, so the suggestion and the eventual name agree.
    public func nextAddedName(for template: Instrument) -> String {
        let existing = instances.filter { $0.templateID == template.id }.count
        return existing == 0
            ? template.name
            : "\(template.name) \(existing + 1)"
    }

    /// "Add another guitar…" — a second instance of a template, named after
    /// it ("Guitar 2") until renamed to what it really is ("Strat"). A
    /// custom `stringCount` extends the template's tuning along its own
    /// interval pattern (see `Instrument.strings(count:)`), so a 6-string
    /// bass or a 9-string guitar is a creation choice, not a blocked shape.
    @discardableResult
    public func add(of template: Instrument, stringCount: Int? = nil) -> InstrumentInstance {
        let siblings = instances.filter { $0.templateID == template.id }.count
        let created = InstrumentInstance(
            id: UUID().uuidString,
            templateID: template.id,
            name: "\(template.name) \(siblings + 1)",
            strings: stringCount.map(template.strings(count:)) ?? template.strings,
            referenceHz: seedReference().hz,
            isLocked: false,
            loadedPresetID: nil,
            lastUsedAt: nil)
        instances.append(created)
        return created
    }

    /// The creation sheet's confirm: everything decided in the sheet —
    /// name and strings together — comes to exist here, in one move.
    /// Nothing was in the store before this; cancelling the sheet had
    /// nothing to undo.
    @discardableResult
    public func add(
        of template: Instrument, named name: String, strings: [Int],
        referenceHz: Double? = nil
    ) -> InstrumentInstance {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = InstrumentInstance(
            id: UUID().uuidString,
            templateID: template.id,
            name: trimmed.isEmpty ? nextAddedName(for: template) : trimmed,
            strings: strings.isEmpty ? template.strings : strings,
            referenceHz: referenceHz ?? seedReference().hz,
            isLocked: false,
            loadedPresetID: nil,
            lastUsedAt: nil)
        instances.append(created)
        return created
    }

    /// Clone an instrument: copied tuning and reference, fresh unlocked, a
    /// numbered name awaiting a rename — someone with a rack of guitars sets
    /// up the first and duplicates it per instrument.
    @discardableResult
    public func duplicate(id: String) -> InstrumentInstance? {
        guard let source = instance(id: id) else { return nil }
        let created = InstrumentInstance(
            id: UUID().uuidString,
            templateID: source.templateID,
            name: nextName(after: source.name, templateID: source.templateID),
            strings: source.strings,
            referenceHz: source.referenceHz,
            isLocked: false,
            loadedPresetID: nil,
            lastUsedAt: nil)
        instances.append(created)
        return created
    }

    /// "Strat 2", or "Strat 3" when that's taken — numbered against the
    /// template's other instances. The duplicate sheet prefills with this.
    public func nextName(after base: String, templateID: String) -> String {
        let taken = Set(instances.filter { $0.templateID == templateID }.map(\.name))
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Remove an instrument — any instrument: the seeded factory ones are
    /// ordinary, and an empty list is a legitimate state (the + menu is
    /// always the way back). Deletions stick; the seed never reruns.
    public func remove(id: String) {
        instances.removeAll { $0.id == id }
    }

    public func rename(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id: id) { $0.name = trimmed }
    }

    /// Apply a tuning — same string count only, which the UI guarantees by
    /// construction (a tuning that doesn't fit is never offered) and this
    /// guards anyway.
    public func setTuning(id: String, strings: [Int]) {
        guard let current = instance(id: id), current.strings.count == strings.count else {
            return
        }
        update(id: id) {
            $0.strings = strings
            $0.loadedPresetID = nil
        }
    }

    /// Change one string's target — the string view's stepper. Editing a
    /// named tuning relabels it Custom automatically, because the tuning's
    /// identity follows the pitches (see `InstrumentInstance.tuningName`).
    ///
    /// Clamped to the range the detector can actually search
    /// (`Detection.fullBand`): a target the app can never hear would be a
    /// dial that can never light, presented as if it could.
    public func setString(id: String, index: Int, midi: Int) {
        guard let current = instance(id: id), current.strings.indices.contains(index) else {
            return
        }
        let clamped = min(
            max(midi, Self.editableMIDIRange.lowerBound),
            Self.editableMIDIRange.upperBound)
        // Keeps the preset claim: a granular edit is drift, not a new pick.
        update(id: id) { $0.strings[index] = clamped }
    }

    /// The shared target range (see `Detection.targetMIDIRange` for the
    /// rationale) — kept as the store's own name because the clamp is this
    /// type's contract with the stepper.
    public static let editableMIDIRange = Detection.targetMIDIRange

    /// Whether a string can be added at this end — `StringListEditing`
    /// holds the rule; this is the store's door to it.
    public func canAddString(id: String, lowEnd: Bool) -> Bool {
        guard let strings = instance(id: id)?.strings else { return false }
        return StringListEditing.canExtend(strings, lowEnd: lowEnd)
    }

    /// Grow the instrument by one string — the proposal logic lives in
    /// `StringListEditing`, shared with the creation sheet's draft. A
    /// structural change is a new shape, so any loaded preset's claim
    /// clears — the old shape's preset can't even fit.
    public func addString(id: String, lowEnd: Bool) {
        guard let current = instance(id: id) else { return }
        setEditedStrings(id: id, StringListEditing.extended(current.strings, lowEnd: lowEnd))
    }

    /// Remove one string, never the last — a zero-string instrument is a
    /// screen with nothing on it. Structural, so the preset claim clears.
    public func removeString(id: String, index: Int) {
        guard let current = instance(id: id) else { return }
        setEditedStrings(id: id, StringListEditing.removed(current.strings, at: index))
    }

    /// The instrument editor's single write path. The claim rule rides the
    /// shape: the same count is a nudge and keeps a loaded preset's claim,
    /// like every target stepper; a different count is structural and
    /// clears it.
    public func setEditedStrings(id: String, _ strings: [Int]) {
        guard let current = instance(id: id), !strings.isEmpty,
            strings != current.strings
        else { return }
        let structural = current.strings.count != strings.count
        update(id: id) {
            $0.strings = strings
            if structural { $0.loadedPresetID = nil }
        }
    }

    public func setReference(id: String, _ reference: ReferencePitch) {
        // Keeps the preset claim: drift shows as "(edited)", scope-aware —
        // a tuning-only preset never claimed the reference at all.
        update(id: id) { $0.referenceHz = reference.hz }
    }

    /// Change how the targets divide their intervals — a granular edit like
    /// a reference step, so the preset claim stays and shows "(edited)"
    /// while drifted. Stored verbatim: nil is reserved for "never chosen",
    /// which reads as the family default.
    public func setTemperament(id: String, _ temperament: Temperament) {
        update(id: id) { $0.temperament = temperament }
    }

    /// Called by `PresetStore.load` after applying a preset's fields, so the
    /// instance knows whose values it's carrying. Cleared again by any manual
    /// change (tuning pick, string edit, reference step) — the id means
    /// "loaded, and untouched since".
    public func presetApplied(id: String, presetID: String) {
        update(id: id) { $0.loadedPresetID = presetID }
    }

    public func setLocked(id: String, _ locked: Bool) {
        update(id: id) { $0.isLocked = locked }
    }

    /// Stamp an instrument as just-opened — the grid calls this on entry,
    /// so "my instruments" orders itself by actual use.
    public func markUsed(id: String) {
        update(id: id) { $0.lastUsedAt = Date() }
    }

    private func update(id: String, _ change: (inout InstrumentInstance) -> Void) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        change(&instances[index])
        instances[index].modifiedAt = Date()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
