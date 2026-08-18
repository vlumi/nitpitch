import Foundation
import NitpitchCore
import WatchKit

/// One string at a time, hands-free: the screen is PINNED to one string's
/// target while the per-string bank listens to all of them — and
/// `StringFocus` (NitpitchCore, where its rules are pinned by tests) decides
/// when the pin moves: a sustained rival, the settled advance, or the crown.
///
/// The wrist's first haptic words live here: a click when focus moves by
/// inference, a success tap when the string settles — tuning without
/// looking, which is the watch's whole reason to exist.
@MainActor
final class WatchInstrumentTunerViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case reading(cents: Double)
        case denied
        case unavailable
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var focusIndex: Int
    @Published private(set) var isSettled = false

    /// Per-string labels for the screen and the crown ("G3", "D4"…) —
    /// published, because a synced retune renames them under a live screen.
    @Published private(set) var stringNames: [String]

    private let audio = WatchAudioInput()
    private let haptics = WatchHaptics()
    private let bank: DetectorBank
    private var instrument: Instrument
    private var targets: [Double]
    private var focus: StringFocus
    private var smoother = ReadingSmoother()
    private var reference: ReferencePitch
    private var temperament: Temperament
    private var naming: NoteNaming

    /// `instrument` carries the strings being tuned — a catalog template,
    /// or an instance's own (possibly custom) tuning via
    /// `InstrumentInstance.instrument`. Reference and temperament come from
    /// wherever the caller's truth lives: synced Settings for the catalog,
    /// the instance itself for instances.
    init(
        instrument: Instrument, reference: ReferencePitch, temperament: Temperament,
        naming: NoteNaming, initialIndex: Int = 0
    ) {
        self.instrument = instrument
        self.reference = reference
        self.temperament = temperament
        self.naming = naming
        targets = Self.temperedTargets(
            instrument: instrument, reference: reference, temperament: temperament)
        stringNames = instrument.notes.map { $0.fullName(in: naming) }
        focus = StringFocus(stringCount: instrument.strings.count, initialIndex: initialIndex)
        focusIndex = focus.focusIndex
        bank = DetectorBank(
            sampleRate: audio.sampleRate,
            targets: targets,
            bands: instrument.stringBands(reference: reference))

        audio.onWindow = { [weak self, bank] window in
            // Analysis queue; only the results hop to main.
            let results = bank.analyze(window)
            Task { @MainActor [weak self] in self?.consume(results) }
        }
    }

    /// A knob moved — the settings screen's, or a synced edit arriving from
    /// the phone mid-view: retarget in place. Focus and its settled state
    /// survive when the shape allows — moving the orchestra's A doesn't
    /// change which string you were working on, only what "in tune" means
    /// for it. A string-count change (sync replaced the tuning wholesale)
    /// rebuilds focus; the caller's `.id` should normally prevent that.
    func configure(
        instrument: Instrument, reference: ReferencePitch, temperament: Temperament,
        naming: NoteNaming
    ) {
        guard
            instrument != self.instrument || reference != self.reference
                || temperament != self.temperament || naming != self.naming
        else { return }
        let countChanged = instrument.strings.count != targets.count
        self.instrument = instrument
        self.reference = reference
        self.temperament = temperament
        self.naming = naming
        retarget()
        if countChanged {
            focus = StringFocus(stringCount: targets.count)
            focusIndex = focus.focusIndex
        }
        bank.configure(
            targets: targets, bands: instrument.stringBands(reference: reference),
            tuning: .default)
        smoother.reset()
    }

    /// Targets and labels from the current knobs — the half of retuning
    /// that init and configure share.
    private func retarget() {
        targets = Self.temperedTargets(
            instrument: instrument, reference: reference, temperament: temperament)
        stringNames = instrument.notes.map { $0.fullName(in: naming) }
    }

    private static func temperedTargets(
        instrument: Instrument, reference: ReferencePitch, temperament: Temperament
    ) -> [Double] {
        let offsets = temperament.offsets(for: instrument.strings)
        return zip(instrument.notes, offsets).map { note, offset in
            note.frequency(reference: reference) * pow(2, offset / 1200)
        }
    }

    func begin() async {
        state = .listening
        switch await audio.activate() {
        case .permissionDenied: state = .denied
        case .unavailable: state = .unavailable
        case .running, .idle: break
        }
    }

    func end() {
        audio.stop()
        haptics.stop()
        smoother.reset()
        state = .idle
    }

    /// The crown's pick: instant and authoritative (see `StringFocus`).
    func select(_ index: Int) {
        guard index != focus.focusIndex else { return }
        focus.select(index)
        apply(event: .none)
        haptics.stop()
        smoother.reset()
        state = .listening
    }

    private var quietFrames = 0
    /// ~1.1 s: plucked notes decay and rests between plucks are the norm
    /// on the wrist — the phone's 8 frames serve continuous bowing.
    private static let quietFramesBeforeIdle = 24

    private func consume(_ results: [DetectionResult]) {
        let levels = results.map { $0.frequency != nil ? $0.level : nil }

        var cents: Double?
        if let hz = results[focus.focusIndex].frequency {
            let raw = PitchMath.cents(from: targets[focus.focusIndex], to: hz)
            cents = smoother.update(cents: raw)
        }

        let event = focus.ingest(
            levels: levels,
            focusedInTune: cents.map(TuningDisplay.isInTune(cents:)))
        apply(event: event)
        haptics.update(hapticCue(results: results, cents: cents))

        if let cents {
            quietFrames = 0
            state = .reading(cents: cents)
        } else {
            // The same dropout as every other screen: the dial clears after
            // a beat of silence rather than freezing on a stale reading —
            // or flickering off at the first rest.
            quietFrames += 1
            if quietFrames >= Self.quietFramesBeforeIdle, case .reading = state {
                smoother.reset()
                state = .listening
            }
        }
    }

    /// The wrist's word for this frame — the haptic beat vocabulary
    /// (`HapticBeat`): a sounding pair's beat wins, else the focused
    /// string's own beat against its target, from the same smoothed cents
    /// the screen shows. Octave claims are parity-flagged and never
    /// masquerade as a pair member (the interval readout's rule).
    private func hapticCue(results: [DetectionResult], cents: Double?) -> HapticBeat.Cue? {
        if let pair = IntervalBeat.resolve(
            frequencies: results.map { $0.evenPartialsOnly ? nil : $0.frequency },
            midis: instrument.strings)
        {
            return HapticBeat.cue(pair: pair)
        }
        guard let cents else { return nil }
        return HapticBeat.cue(cents: cents, targetHz: targets[focus.focusIndex])
    }

    private func apply(event: StringFocus.Event) {
        switch event {
        case .focused:
            WKInterfaceDevice.current().play(.click)
            smoother.reset()
            quietFrames = 0
            state = .listening
        case .settled:
            WKInterfaceDevice.current().play(.success)
        case .none:
            break
        }
        if focusIndex != focus.focusIndex { focusIndex = focus.focusIndex }
        if isSettled != focus.isSettled { isSettled = focus.isSettled }
    }
}
