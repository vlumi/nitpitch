import NitpitchCore
import SwiftUI

/// The string view's audio: one target, the whole instrument's band.
///
/// A sibling of `StringTuners` for the N = 1 case, with the crucial
/// difference in the *band*: the grid's cells split the range at midpoints so
/// dials can disambiguate, but a view bound to one string has nothing to
/// disambiguate against — so it hears everything the instrument can produce,
/// and the hybrid does the rest (spectral precision near target, MPM finding
/// a slack string from anywhere).
@MainActor
final class SingleStringTuner: ObservableObject {
    let tuner: StringTunerViewModel

    /// Overall input level for the meter, same curve and quantization as the
    /// grid's — and the same observable island (see `InputLevel`): the
    /// string view's whole body re-rendering per meter tick would fight the
    /// swipe animation for no reason.
    let inputLevel = InputLevel()

    /// The intonation mode's state, its own island for the same reason.
    let intonation = IntonationMonitor()

    /// Whether the intonation check is running (`IntonationMode`) — the
    /// analyzer works only then: in tuning mode a 12th-fret note is simply
    /// the string, folded by the dial, with no octave question to answer.
    private var isChecking = false

    /// The app's ONE reference tone, through the controller — a single
    /// engine so two screens can never sound at once (the field found the
    /// double when each screen owned its own).
    var tone: ToneGenerator { audio.tone }

    private var instrument: Instrument
    private let audio: AudioSessionController
    private let bank: DetectorBank
    /// Rides alongside the bank on the analysis queue, answering nil while
    /// the mode is off — the subscription calls it unconditionally.
    private let analyzer: IntonationAnalyzer
    /// The frequency the analyzer is aimed at, so `apply` can tell a real
    /// retarget (captures invalid) from an incidental instance change like
    /// the lock toggling (captures fine).
    private var analyzerTarget: Double
    private var subscription: AudioSessionController.Subscription?
    private var reference: ReferencePitch
    /// Kept so retargeting doesn't quietly reset debug-tuned thresholds.
    private var tuning: DetectionTuning

    init(
        instrument: Instrument, index: Int, audio: AudioSessionController,
        reference: ReferencePitch, temperament: Temperament = .equal,
        tuning: DetectionTuning = .default
    ) {
        self.instrument = instrument
        self.audio = audio
        self.reference = reference
        self.tuning = tuning
        let band = instrument.band(reference: reference)
        let note = instrument.notes[index]
        let offset = temperament.offsets(for: instrument.strings)[index]
        tuner = StringTunerViewModel(
            audio: audio, target: note, band: band, reference: reference,
            targetOffsetCents: offset)
        analyzerTarget =
            note.frequency(reference: reference) * pow(2, offset / 1200)
        bank = DetectorBank(
            sampleRate: audio.sampleRate,
            targets: [analyzerTarget],
            bands: [band],
            tuning: tuning)
        analyzer = IntonationAnalyzer(
            sampleRate: audio.sampleRate, target: analyzerTarget, tuning: tuning)
    }

    func attach() {
        tuner.begin()
        analyzer.setActive(isChecking)
        // Navigation begins in silence: whatever tone the previous screen
        // left ringing stops here, and capture takes the session back.
        if tone.playingTag != nil {
            let audio = audio
            Task { await audio.silenceTone() }
        }
        guard subscription == nil else { return }
        subscription = audio.subscribe { [weak self, bank, analyzer] window in
            // Analysis queue; only the results hop to main.
            let results = bank.analyze(window)
            let frame = analyzer.analyze(window)
            Task { @MainActor [weak self] in
                guard let self, let result = results.first else { return }
                // Who gets this frame — the main dial or the octave's tuner —
                // is a real decision with two classifiers behind it; see
                // `IntonationRouting` for why either alone leaks.
                let routed = IntonationRouting.route(
                    result: result, frame: frame, target: self.analyzerTarget)
                self.tuner.ingest(routed.dial)
                self.inputLevel.set((result.displayLevel * 20).rounded() / 20)
                if let frame = routed.intonation { self.intonation.ingest(frame) }
            }
        }
    }

    /// Sound the string's target, or stop it. Capture yields while the
    /// tone plays — detection suspends rather than hearing the app's own
    /// voice — and the dial honestly goes idle: frozen readings pretending
    /// to be live is a lesson this app has already paid for.
    func toggleTone() async {
        await toggle(hz: analyzerTarget, tag: .single)
    }

    /// Sound the reference A itself — the readout beside the stepper is
    /// the button.
    func toggleTone(reference: ReferencePitch) async {
        await toggle(hz: reference.hz, tag: .reference)
    }

    private func toggle(hz: Double, tag: ToneTag) async {
        let stopping = tone.playingTag == tag
        let wasSilent = tone.playingTag == nil
        await audio.toggleTone(hz: hz, tag: tag)
        if stopping {
            tuner.begin()
        } else if wasSilent {
            tuner.end()
            inputLevel.set(0)
        }
    }

    /// Enter or leave the intonation check. Fresh either way: a stale
    /// capture reappearing later would look authoritative and be anything
    /// but — the grid's layer follows the same rule.
    func setChecking(_ on: Bool) {
        guard isChecking != on else { return }
        isChecking = on
        analyzer.setActive(on)
        intonation.reset()
    }

    func detach() {
        subscription?.cancel()
        subscription = nil
        inputLevel.set(0)
        bank.interrupted()
        analyzer.setActive(false)
        tuner.end()
        // Leaving mid-tone: silence it and hand the session back to
        // capture, which the next screen is already listening through.
        if tone.playingTag != nil {
            let audio = audio
            Task { await audio.silenceTone() }
        }
    }

    /// The one entry point for "aim here now": swiping to a neighbour, the
    /// reference moving, or the target itself being edited — all end up as a
    /// note, a band, and a reference to measure against.
    func apply(instance: InstrumentInstance, index: Int, tuning: DetectionTuning) {
        self.instrument = instance.instrument
        self.reference = instance.reference
        self.tuning = tuning
        guard instrument.notes.indices.contains(index) else { return }
        let note = instrument.notes[index]
        let band = instrument.band(reference: reference)
        let offset = instance.appliedTemperament.offsets(for: instrument.strings)[index]
        let hz = note.frequency(reference: reference) * pow(2, offset / 1200)
        bank.configure(
            targets: [hz],
            bands: [band],
            tuning: tuning)
        tuner.configure(band: band, reference: reference, targetOffsetCents: offset)
        if tuner.target != note {
            tuner.retarget(note)
        }
        // The intonation captures answer for one specific target; a real
        // retarget invalidates them. An incidental instance change — the
        // lock toggling — moves nothing and must not wipe a measurement.
        analyzer.configure(target: hz, tuning: tuning)
        if hz != analyzerTarget {
            analyzerTarget = hz
            intonation.reset()
        }
        // A sounding tone follows whatever moved it, BY TAG: the string's
        // tone glides with a swipe (the tune-by-fifths flow), the reference
        // A follows its stepper, and neither ever grabs the other's pitch.
        if tone.playingTag == .single {
            tone.retune(hz: hz)
        } else if tone.playingTag == .reference {
            tone.retune(hz: reference.hz)
        }
    }

    func retune(_ tuning: DetectionTuning) {
        self.tuning = tuning
        bank.retune(tuning)
        analyzer.configure(target: analyzerTarget, tuning: tuning)
    }

}

extension IntonationAnalyzer.Frame {
    /// Whether this frame's note is the octave — the main dial's cue to
    /// stand down and let the octave's own tuner answer.
    var soundsOctave: Bool {
        if case .note(slot: .octave, cents: _, clarity: _) = sounding { return true }
        return false
    }
}
