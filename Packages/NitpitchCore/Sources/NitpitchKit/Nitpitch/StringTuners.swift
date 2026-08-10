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
    /// frame with no visible change publishes nothing. Its own island, NOT a
    /// `@Published` here: this object anchors the whole grid, and a screen
    /// re-rendering per meter tick closed any open macOS menu (see
    /// `InputLevel`).
    let inputLevel = InputLevel()

    private let audio: AudioSessionController
    /// All the DSP, shared with the analysis queue — see `DetectorBank` for
    /// the locking story.
    private let bank: DetectorBank
    private var subscription: AudioSessionController.Subscription?
    /// Drives `inputLevel` under `-demo`, where no audio flows.
    private var demo: Task<Void, Never>?
    /// Whether the intonation layer is on — gates the octave claim routing.
    private var isIntonating = false
    /// The strings' target frequencies, for the router's 2f arithmetic.
    /// Kept alongside the bank's copy, which it doesn't share back.
    private var targets: [Double]
    /// Nominal MIDI per string, for the interval arithmetic.
    private var midis: [Int]

    /// The interval readout — beats between two sounding adjacent strings —
    /// its own island like the meter's.
    let interval = IntervalMonitor()

    init(
        instrument: Instrument, audio: AudioSessionController, reference: ReferencePitch,
        temperament: Temperament = .equal, tuning: DetectionTuning = .default
    ) {
        self.audio = audio
        let bands = instrument.stringBands(
            reference: reference, maxSemitones: tuning.maxSemitonesFromString)
        // The temperament shifts the targets a few cents; the bands stay
        // MIDI-derived — they're semitones wide, and 2¢ moves nothing.
        let offsets = temperament.offsets(for: instrument.strings)
        tuners = zip(zip(instrument.notes, bands), offsets).map { pair, offset in
            StringTunerViewModel(
                audio: audio, target: pair.0, band: pair.1, reference: reference,
                targetOffsetCents: offset)
        }
        targets = Self.temperedTargets(
            notes: instrument.notes, offsets: offsets, reference: reference)
        midis = instrument.strings
        bank = DetectorBank(
            sampleRate: audio.sampleRate,
            targets: targets,
            bands: bands,
            tuning: tuning)
        interval.configure(midis: midis, targets: targets)
    }

    private static func temperedTargets(
        notes: [Note], offsets: [Double], reference: ReferencePitch
    ) -> [Double] {
        zip(notes, offsets).map { note, offset in
            note.frequency(reference: reference) * pow(2, offset / 1200)
        }
    }

    func attachAll() {
        for tuner in tuners { tuner.begin() }
        // Navigation begins in silence: whatever tone the previous screen
        // left ringing stops here.
        if tone.playingTag != nil {
            let audio = audio
            Task { await audio.silenceTone() }
        }
        if LaunchStores.isDemo {
            guard demo == nil else { return }
            demo = Task { await runDemoLevel() }
            return
        }
        guard subscription == nil else { return }
        subscription = audio.subscribe { [weak self, bank] window in
            // Runs on the analysis queue. All the DSP happens here; only the
            // finished results hop to main.
            let frame = bank.analyzeWithAbove(window)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let results = frame.strings
                // With the intonation layer on, octave findings get claimed
                // by their owners first — MPM puts a fretted 12th on a
                // NEIGHBOUR's dial or above every band entirely (the
                // sentinel's territory), because a string's own octave is
                // always outside its own band (see `GridIntonationRouting`).
                let routed =
                    self.isIntonating
                    ? GridIntonationRouting.route(
                        results: results, targets: self.targets, above: frame.above)
                    : results
                for (tuner, result) in zip(self.tuners, routed) {
                    tuner.ingest(result)
                }
                // The interval readout hears the same frame — open strings
                // only, so an octave claim (parity-flagged) never
                // masquerades as a sounding pair member.
                self.interval.ingest(
                    frequencies: routed.map {
                        $0.evenPartialsOnly ? nil : $0.frequency
                    })
                // Every result carries the same frame's RMS; the meter shows
                // the shared display curve of it.
                if let frame = results.first {
                    self.inputLevel.set((frame.displayLevel * 20).rounded() / 20)
                }
            }
        }
    }

    /// The demo's overall meter, so the top of the screen moves like the rest
    /// of the synthetic layout — and a synthetic double stop on the middle
    /// pair, its beats breathing between ~3/s and 0, so the interval chip,
    /// its pulse and both of its homes are judged live.
    private func runDemoLevel() async {
        var tick = 0.0
        while !Task.isCancelled {
            inputLevel.set(((0.5 + 0.3 * sin(tick * 1.3)) * 20).rounded() / 20)
            if midis.count >= 3, targets.count == midis.count,
                let kind = IntervalBeat.Kind(semitones: midis[2] - midis[1])
            {
                let beat = max(0, 3 * (0.5 + 0.5 * sin(tick * 0.25)))
                let lower = targets[1]
                let upper =
                    (Double(kind.lowerHarmonic) * lower - beat)
                    / Double(kind.upperHarmonic)
                var frequencies = [Double?](repeating: nil, count: midis.count)
                frequencies[1] = lower
                frequencies[2] = upper
                interval.ingest(frequencies: frequencies)
            }
            tick += 0.055
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func detachAll() {
        subscription?.cancel()
        subscription = nil
        demo?.cancel()
        demo = nil
        inputLevel.set(0)
        interval.reset()
        // The spectral engine's phase pair must not span the gap.
        bank.interrupted()
        for tuner in tuners { tuner.end() }
        // Leaving mid-tone: silence it and hand the session back to capture.
        if tone.playingTag != nil {
            let audio = audio
            Task { await audio.silenceTone() }
        }
    }

    /// Re-tune every band when the reference, the temperament or the band
    /// width moves — they all shift together.
    func configure(
        instrument: Instrument, reference: ReferencePitch,
        temperament: Temperament = .equal, tuning: DetectionTuning = .default
    ) {
        let bands = instrument.stringBands(
            reference: reference, maxSemitones: tuning.maxSemitonesFromString)
        let offsets = temperament.offsets(for: instrument.strings)
        targets = Self.temperedTargets(
            notes: instrument.notes, offsets: offsets, reference: reference)
        midis = instrument.strings
        interval.configure(midis: midis, targets: targets)
        bank.configure(
            targets: targets,
            bands: bands,
            tuning: tuning)
        // The tuners are built per string at init and the count is fixed
        // for an instrument's life (see `InstrumentStore.setEditedStrings`),
        // so this zip should never truncate. It's asserted rather than
        // assumed: when the shape COULD change, `zip` silently configured
        // only the strings both sides had — a 7th string with no dial, and
        // a removed string's dial still on screen.
        assert(
            tuners.count == instrument.notes.count,
            "a tuner per string: \(tuners.count) tuners, \(instrument.notes.count) strings")
        for (tuner, ((note, band), offset)) in zip(
            tuners, zip(zip(instrument.notes, bands), offsets))
        {
            tuner.configure(band: band, reference: reference, targetOffsetCents: offset)
            // The tuning may have moved this string to a different note —
            // Drop D turns E2's dial into D2's. Rebanding alone would leave
            // the cell measuring (and labelled) against the old target.
            if tuner.target != note {
                tuner.retarget(note)
            }
        }
        // A sounding tone follows whatever moved it: stepping the reference
        // while its A plays retunes the pitch live, and a retuned string
        // glides its speaker along.
        if let tag = tone.playingTag {
            if tag == "reference" {
                tone.retune(hz: reference.hz)
            } else if let index = Int(tag.dropFirst("string.".count)),
                targets.indices.contains(index)
            {
                tone.retune(hz: targets[index])
            }
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

    /// The intonation check, for every string at once — the grid's whole
    /// point is not switching strings.
    func setIntonating(_ on: Bool) {
        isIntonating = on
        for tuner in tuners { tuner.setIntonating(on) }
    }

    // MARK: - The reference tone, from the grid

    /// The app's ONE tone, through the controller — tapping another speaker
    /// while one sounds GLIDES to it, and no two screens can ever sound at
    /// once, because there is exactly one engine to sound with.
    var tone: ToneGenerator { audio.tone }

    /// Sound one string's tempered target.
    func toggleTone(string index: Int) async {
        guard targets.indices.contains(index) else { return }
        await toggle(hz: targets[index], tag: "string.\(index)")
    }

    /// Sound the reference itself — the A the footer stepper shows. While
    /// it plays, stepping the reference retunes it live (`configure`).
    func toggleTone(reference: ReferencePitch) async {
        await toggle(hz: reference.hz, tag: "reference")
    }

    private func toggle(hz: Double, tag: String) async {
        let stopping = tone.playingTag == tag
        let wasSilent = tone.playingTag == nil
        await audio.toggleTone(hz: hz, tag: tag)
        if stopping {
            for tuner in tuners { tuner.begin() }
        } else if wasSilent {
            // Capture yields; every dial goes honestly idle rather than
            // freezing on its last reading.
            for tuner in tuners { tuner.end() }
            inputLevel.set(0)
        }
    }
}
