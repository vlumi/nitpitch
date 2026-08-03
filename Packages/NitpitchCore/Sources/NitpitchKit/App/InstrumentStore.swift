import Combine
import Foundation
import NitpitchCore

/// An instrument you own: "Strat", "Acoustic", "Violin" — a named instance of
/// a template, holding its own mutable state, autosaved, waiting as you left
/// it (ROADMAP § 1).
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
    /// The padlock: a locked instrument's controls are doors (they never
    /// mutate and never ignore a touch — they offer the unlock).
    public var isLocked: Bool

    public var reference: ReferencePitch { ReferencePitch(hz: referenceHz) }

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

    /// The default instance for a template, created on first use — which is
    /// what makes a beginner's path free of the whole concept: tap Violin,
    /// get the violin, never learn that instances exist.
    public func defaultInstance(for template: Instrument) -> InstrumentInstance {
        if let existing = instance(id: template.id) { return existing }
        let created = InstrumentInstance(
            id: template.id,
            templateID: template.id,
            name: template.name,
            strings: template.strings,
            referenceHz: seedReference().hz,
            isLocked: false)
        instances.append(created)
        return created
    }

    /// "Add another guitar…" — a second instance of a template, named after
    /// it ("Guitar 2") until renamed to what it really is ("Strat").
    @discardableResult
    public func add(of template: Instrument) -> InstrumentInstance {
        // Make sure the default exists first, so numbering reads naturally.
        _ = defaultInstance(for: template)
        let count = instances.filter { $0.templateID == template.id }.count
        let created = InstrumentInstance(
            id: UUID().uuidString,
            templateID: template.id,
            name: "\(template.name) \(count + 1)",
            strings: template.strings,
            referenceHz: seedReference().hz,
            isLocked: false)
        instances.append(created)
        return created
    }

    /// Remove an added instrument. Removing a *default* instance just resets
    /// it: the template row would recreate it on the next tap anyway, so
    /// pretending it can be deleted would only manufacture surprise.
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
        update(id: id) { $0.strings = strings }
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
        update(id: id) { $0.strings[index] = clamped }
    }

    /// MIDI notes whose frequency at any offered reference stays inside
    /// `Detection.fullBand`. The floor is B0 (23 ≈ 30.9 Hz at A=440) — a
    /// 5-string bass's low string, and comfortably below bass drop D — the
    /// same line the catalog's own tunings respect. Found the hard way: the
    /// first floor was derived from an older, higher `fullBand`, and the
    /// stepper refused D1 one semitone before the most common bass drop
    /// tuning while the tuning menu happily set it.
    public static let editableMIDIRange = 23...95

    public func setReference(id: String, _ reference: ReferencePitch) {
        update(id: id) { $0.referenceHz = reference.hz }
    }

    public func setLocked(id: String, _ locked: Bool) {
        update(id: id) { $0.isLocked = locked }
    }

    private func update(id: String, _ change: (inout InstrumentInstance) -> Void) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        change(&instances[index])
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
