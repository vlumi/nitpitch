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

    let instrument: Instrument
    /// Per-string labels for the screen and the crown ("G3", "D4"…).
    let stringNames: [String]

    private let audio = WatchAudioInput()
    private let bank: DetectorBank
    private var targets: [Double]
    private var focus: StringFocus
    private var smoother = ReadingSmoother()
    private var reference: ReferencePitch
    private var temperament: Temperament

    init(instrument: Instrument, initialIndex: Int = 0) {
        self.instrument = instrument
        // The wrist's stored knobs (see `WatchTuning`) — the phone's
        // defaults until touched: A=440, pure fifths on bowed instruments.
        let reference = WatchTuning.storedReference()
        let temperament = WatchTuning.storedTemperament(for: instrument.family)
        self.reference = reference
        self.temperament = temperament
        targets = Self.temperedTargets(
            instrument: instrument, reference: reference, temperament: temperament)
        stringNames = instrument.notes.map(\.fullName)
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

    /// The settings sheet changed a knob: retarget in place. Focus and its
    /// settled state survive — moving the orchestra's A doesn't change which
    /// string you were working on, only what "in tune" means for it.
    func configure(reference: ReferencePitch, temperament: Temperament) {
        guard reference != self.reference || temperament != self.temperament else { return }
        self.reference = reference
        self.temperament = temperament
        targets = Self.temperedTargets(
            instrument: instrument, reference: reference, temperament: temperament)
        bank.configure(
            targets: targets, bands: instrument.stringBands(reference: reference),
            tuning: .default)
        smoother.reset()
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
        smoother.reset()
        state = .idle
    }

    /// The crown's pick: instant and authoritative (see `StringFocus`).
    func select(_ index: Int) {
        guard index != focus.focusIndex else { return }
        focus.select(index)
        apply(event: .none)
        smoother.reset()
        state = .listening
    }

    private var quietFrames = 0
    private static let quietFramesBeforeIdle = 8

    private func consume(_ results: [DetectionResult]) {
        let sounding = results.map { $0.frequency != nil }

        var cents: Double?
        if let hz = results[focus.focusIndex].frequency {
            let raw = 1200 * log2(hz / targets[focus.focusIndex])
            cents = smoother.update(cents: raw)
        }

        let event = focus.ingest(
            sounding: sounding,
            focusedInTune: cents.map(TuningDisplay.isInTune(cents:)))
        apply(event: event)

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
