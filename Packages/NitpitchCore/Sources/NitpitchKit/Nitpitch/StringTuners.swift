import NitpitchCore
import SwiftUI

/// One instrument's live tuning: the view models the cells observe, and the
/// single audio subscription that feeds all of them.
///
/// One subscription rather than one per dial, because the strings can't be
/// judged independently: every detector hears the whole signal, so one played
/// note shows up in several and something has to see all the results together
/// to arbitrate (`DetectorBank`). Per-dial subscriptions structurally can't.
///
/// A single `@StateObject` rather than one per cell: the cells are produced by
/// a `ForEach` over lazily-created rows, and models that came and went with
/// their cells would lose their smoothing every time one scrolled away.
@MainActor
final class StringTuners: ObservableObject {
    let tuners: [StringTunerViewModel]

    /// The frame's overall input level, 0...1 — whether the app can hear
    /// *anything*, separate from whether any string registers. This is what
    /// tells "quiet room" apart from "sound coming in, just not near any
    /// string's target", which the per-string bars can't: they're zero in
    /// both cases. Quantized to twentieths, like the per-string levels, so a
    /// frame with no visible change publishes nothing.
    @Published private(set) var inputLevel: Double = 0

    private let audio: AudioSessionController
    /// All the DSP, shared with the analysis queue — see `DetectorBank` for
    /// the locking story.
    private let bank: DetectorBank
    private var subscription: AudioSessionController.Subscription?
    /// Drives `inputLevel` under `-demo`, where no audio flows.
    private var demo: Task<Void, Never>?

    init(
        instrument: Instrument, audio: AudioSessionController, reference: ReferencePitch,
        tuning: DetectionTuning = .default
    ) {
        self.audio = audio
        let bands = instrument.stringBands(
            reference: reference, maxSemitones: tuning.maxSemitonesFromString)
        tuners = zip(instrument.notes, bands).map { note, band in
            StringTunerViewModel(audio: audio, target: note, band: band, reference: reference)
        }
        bank = DetectorBank(
            sampleRate: audio.sampleRate,
            targets: instrument.notes.map { $0.frequency(reference: reference) },
            bands: bands,
            tuning: tuning)
    }

    func attachAll() {
        for tuner in tuners { tuner.begin() }
        if LaunchStores.isDemo {
            guard demo == nil else { return }
            demo = Task { await runDemoLevel() }
            return
        }
        guard subscription == nil else { return }
        subscription = audio.subscribe { [weak self, bank] window in
            // Runs on the analysis queue. All the DSP happens here; only the
            // finished results hop to main.
            let results = bank.analyze(window)
            Task { @MainActor [weak self] in
                guard let self else { return }
                for (tuner, result) in zip(self.tuners, results) {
                    tuner.ingest(result)
                }
                // Every result carries the same frame's RMS; the meter shows
                // the shared display curve of it.
                if let frame = results.first {
                    let level = (frame.displayLevel * 20).rounded() / 20
                    if level != self.inputLevel { self.inputLevel = level }
                }
            }
        }
    }

    /// The demo's overall meter, so the top of the screen moves like the rest
    /// of the synthetic layout.
    private func runDemoLevel() async {
        var tick = 0.0
        while !Task.isCancelled {
            inputLevel = ((0.5 + 0.3 * sin(tick * 1.3)) * 20).rounded() / 20
            tick += 0.055
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func detachAll() {
        subscription?.cancel()
        subscription = nil
        demo?.cancel()
        demo = nil
        inputLevel = 0
        // The spectral engine's phase pair must not span the gap.
        bank.interrupted()
        for tuner in tuners { tuner.end() }
    }

    /// Re-tune every band when the reference or the band width moves — they all
    /// shift together.
    func configure(
        instrument: Instrument, reference: ReferencePitch, tuning: DetectionTuning = .default
    ) {
        let bands = instrument.stringBands(
            reference: reference, maxSemitones: tuning.maxSemitonesFromString)
        bank.configure(
            targets: instrument.notes.map { $0.frequency(reference: reference) },
            bands: bands,
            tuning: tuning)
        for (tuner, band) in zip(tuners, bands) {
            tuner.configure(band: band, reference: reference)
        }
    }

    /// Thresholds or engine only — no band change, so the detectors keep their
    /// buffers and their smoothing while a slider is being dragged.
    func retune(_ tuning: DetectionTuning) {
        bank.retune(tuning)
    }

    /// Publish raw detector output, for as long as the diagnostics screen is up.
    func setReportingRaw(_ isReporting: Bool) {
        for tuner in tuners { tuner.isReportingRaw = isReporting }
    }
}
