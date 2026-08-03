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
    /// grid's.
    @Published private(set) var inputLevel: Double = 0

    private var instrument: Instrument
    private let audio: AudioSessionController
    private let bank: DetectorBank
    private var subscription: AudioSessionController.Subscription?
    private var demo: Task<Void, Never>?
    private var reference: ReferencePitch
    /// Kept so retargeting doesn't quietly reset debug-tuned thresholds.
    private var tuning: DetectionTuning

    init(
        instrument: Instrument, index: Int, audio: AudioSessionController,
        reference: ReferencePitch, tuning: DetectionTuning = .default
    ) {
        self.instrument = instrument
        self.audio = audio
        self.reference = reference
        self.tuning = tuning
        let band = instrument.band(reference: reference)
        let note = instrument.notes[index]
        tuner = StringTunerViewModel(
            audio: audio, target: note, band: band, reference: reference)
        bank = DetectorBank(
            sampleRate: audio.sampleRate,
            targets: [note.frequency(reference: reference)],
            bands: [band],
            tuning: tuning)
    }

    func attach() {
        tuner.begin()
        if LaunchStores.isDemo {
            guard demo == nil else { return }
            demo = Task { await runDemoLevel() }
            return
        }
        guard subscription == nil else { return }
        subscription = audio.subscribe { [weak self, bank] window in
            // Analysis queue; only the result hops to main.
            let results = bank.analyze(window)
            Task { @MainActor [weak self] in
                guard let self, let result = results.first else { return }
                self.tuner.ingest(result)
                let level = (result.displayLevel * 20).rounded() / 20
                if level != self.inputLevel { self.inputLevel = level }
            }
        }
    }

    func detach() {
        subscription?.cancel()
        subscription = nil
        demo?.cancel()
        demo = nil
        inputLevel = 0
        bank.interrupted()
        tuner.end()
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
        bank.configure(
            targets: [note.frequency(reference: reference)],
            bands: [band],
            tuning: tuning)
        tuner.configure(band: band, reference: reference)
        if tuner.target != note {
            tuner.retarget(note)
        }
    }

    func retune(_ tuning: DetectionTuning) {
        self.tuning = tuning
        bank.retune(tuning)
    }

    private func runDemoLevel() async {
        var tick = 0.0
        while !Task.isCancelled {
            inputLevel = ((0.5 + 0.3 * sin(tick * 1.3)) * 20).rounded() / 20
            tick += 0.055
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
