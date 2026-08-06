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

    /// The reference tone, aimed at this string's tempered target — tune by
    /// ear against it, or survive a room too noisy to detect in. Its own
    /// observable island: only the toolbar button re-renders with it.
    let tone = ToneGenerator()

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
    private var demo: Task<Void, Never>?
    private var intonationDemo: Task<Void, Never>?
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
        analyzer.setActive(true)
        if LaunchStores.isDemo {
            guard demo == nil else { return }
            demo = Task { await runDemoLevel() }
            intonationDemo = Task { await runDemoIntonation() }
            return
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
        if tone.playingHz != nil {
            await tone.stop()
            await audio.endTonePlayback()
            tuner.begin()
            return
        }
        audio.beginTonePlayback()
        tuner.end()
        inputLevel.set(0)
        tone.start(hz: analyzerTarget)
    }

    func detach() {
        subscription?.cancel()
        subscription = nil
        demo?.cancel()
        demo = nil
        intonationDemo?.cancel()
        intonationDemo = nil
        inputLevel.set(0)
        bank.interrupted()
        analyzer.setActive(false)
        tuner.end()
        // Leaving mid-tone: silence it and hand the session back to
        // capture, which the next screen is already listening through.
        if tone.playingHz != nil {
            let tone = tone
            let audio = audio
            Task {
                await tone.stop()
                await audio.endTonePlayback()
            }
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
        // A sounding tone follows the retarget — swiping to the next string
        // glides the pitch, which IS the tune-by-fifths flow: A, then D.
        tone.retune(hz: hz)
    }

    func retune(_ tuning: DetectionTuning) {
        self.tuning = tuning
        bank.retune(tuning)
        analyzer.configure(target: analyzerTarget, tuning: tuning)
    }

    private func runDemoLevel() async {
        var tick = 0.0
        while !Task.isCancelled {
            inputLevel.set(((0.5 + 0.3 * sin(tick * 1.3)) * 20).rounded() / 20)
            tick += 0.055
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// A measurement in progress, synthesized: the open sample already
    /// captured, the octave being held — the panel's dial lit, both values
    /// and the delta populated. The layout is judged with every element
    /// live, which is the demo's whole job.
    private func runDemoIntonation() async {
        intonation.reset()
        for _ in 0..<IntonationCapture.stableFrames {
            intonation.ingest(
                IntonationAnalyzer.Frame(
                    sounding: .note(slot: .open, cents: -1.6, clarity: 0.97), level: 0.5))
        }
        intonation.ingest(IntonationAnalyzer.Frame(sounding: .nothing, level: 0.1))
        var tick = 0.0
        while !Task.isCancelled {
            // A gentle wobble inside the stability window, so the octave
            // sample records and then keeps refreshing like a held note's.
            let cents = 5.8 + sin(tick) * 1.2
            intonation.ingest(
                IntonationAnalyzer.Frame(
                    sounding: .note(slot: .octave, cents: cents, clarity: 0.97),
                    level: 0.5 + 0.2 * sin(tick * 1.7)))
            tick += 0.055
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
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
