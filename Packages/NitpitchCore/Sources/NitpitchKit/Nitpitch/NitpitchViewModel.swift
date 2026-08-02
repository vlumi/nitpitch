import Combine
import Foundation
import NitpitchCore

/// Drives the readout: subscribes to the shared microphone, runs the detector
/// on each window, and publishes a smoothed reading for the view.
///
/// It does *not* own the capture. `AudioSessionController` does, so that
/// several of these can be live at once — one per string, once the grid lands
/// (ROADMAP § 2) — all reading the same stream.
@MainActor
public final class NitpitchViewModel: ObservableObject {
    /// What the display should currently show.
    public enum State: Equatable {
        /// Not started, or stopped.
        case idle
        /// Permission was refused — the UI offers a route to Settings.
        case permissionDenied
        /// Running, but nothing confident enough to show.
        case listening
        /// A confident reading.
        case reading(PitchReading, cents: Double, clarity: Double)
    }

    @Published public private(set) var state: State = .idle
    /// Input level, 0...1, for a signal meter. Published separately from `state`
    /// so the meter stays live while the readout says "listening".
    @Published public private(set) var level: Double = 0

    private let audio: AudioSessionController
    private var subscription: AudioSessionController.Subscription?
    private var detector: PitchDetector
    private var smoother = ReadingSmoother()
    private var reference: ReferencePitch
    /// Frames without a confident reading; after enough of them the display
    /// drops back to "listening" rather than freezing on a stale note.
    private var quietFrames = 0
    private static let quietFramesBeforeIdle = 8

    public init(
        audio: AudioSessionController,
        reference: ReferencePitch = .standard, band: ClosedRange<Double> = Detection.fullBand
    ) {
        self.reference = reference
        self.audio = audio
        self.detector = PitchDetector(sampleRate: audio.sampleRate, band: band)
    }

    /// Re-tune the detector when the instrument changes: narrowing the searched
    /// band is what keeps a cello's low C from being found as a violin harmonic.
    public func configure(reference: ReferencePitch, band: ClosedRange<Double>) {
        self.reference = reference
        self.detector = PitchDetector(sampleRate: audio.sampleRate, band: band)
        smoother.reset()
    }

    /// Begin receiving windows. The engine itself is the controller's business
    /// — this only starts listening to it.
    public func attach() async {
        if LaunchStores.isDemo {
            await runDemo()
            return
        }
        subscription = audio.subscribe { [weak self] window in
            // Runs on the analysis queue. Do the DSP here, then hop to main
            // with only the result.
            guard let self else { return }
            let result = self.detector.analyze(window)
            Task { @MainActor in self.consume(result) }
        }
        state = audio.status == .permissionDenied ? .permissionDenied : .listening
    }

    /// Drives the display from a synthetic reading, for laying out the UI
    /// where there's no usable microphone (see `LaunchStores.isDemo`).
    ///
    /// Oscillates rather than holding a fixed pitch: a static value would
    /// leave the arc, the colour ramp and most of the light strip untested,
    /// and those are what the layout has to accommodate at their extremes.
    ///
    /// Sinusoidal rather than a linear sweep — it eases at the turning points
    /// and crosses the centre quickly, so the in-tune state is legible instead
    /// of flashing past at the same rate as everything else. A slower second
    /// term detunes the swing so it doesn't look mechanical.
    private func runDemo() async {
        state = .listening
        let target = Note(midi: 69)  // A4, so the octave subscript shows
        var tick = 0.0

        while !Task.isCancelled {
            let swing = sin(tick) * 0.75 + sin(tick * 0.31) * 0.25
            let cents = swing * TuningDisplay.fullScaleCents
            let hz = target.frequency(reference: reference) * pow(2, cents / 1200)

            state = .reading(
                PitchReading(frequency: hz, reference: reference),
                cents: cents, clarity: 0.98)
            level = 0.45 + 0.2 * sin(tick * 1.7)

            tick += 0.055
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Stop receiving windows. Deliberately leaves the engine running: it's
    /// shared, and tearing it down on every navigation would churn the audio
    /// session for whoever else is listening.
    public func detach() {
        subscription?.cancel()
        subscription = nil
        smoother.reset()
        state = .idle
        level = 0
    }

    private func consume(_ result: DetectionResult) {
        // A short log-ish curve: RMS is tiny for quiet playing, and a linear
        // meter would sit near zero for everything but a loud bow.
        level = min(1, sqrt(result.rms) * 3)

        guard let hz = result.frequency else {
            quietFrames += 1
            if quietFrames >= Self.quietFramesBeforeIdle, audio.status == .running {
                smoother.reset()
                state = .listening
            }
            return
        }
        quietFrames = 0

        let raw = PitchReading(frequency: hz, reference: reference)
        // Smooth in absolute cents (MIDI×100 + offset) so the median and the
        // exponential filter see a continuous line across note boundaries
        // instead of a sawtooth at every ±50.
        let absolute = Double(raw.note.midi) * 100 + raw.cents
        let smoothedAbsolute = smoother.update(cents: absolute)
        // Re-resolve the smoothed value: near a boundary the smoothed reading
        // can belong to the neighbouring note, and the name must agree with the
        // needle.
        let smoothedMidi = Int((smoothedAbsolute / 100).rounded())
        let displayCents = smoothedAbsolute - Double(smoothedMidi) * 100
        let display = PitchReading(
            frequency: Note(midi: smoothedMidi).frequency(reference: reference)
                * pow(2, displayCents / 1200),
            reference: reference)
        state = .reading(display, cents: displayCents, clarity: result.clarity)
    }
}
