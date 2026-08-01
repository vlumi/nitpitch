import Combine
import Foundation
import NitpitchCore

/// Drives the readout: owns the audio input, runs the detector on each window,
/// and publishes a smoothed reading for the view.
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

    private let audio: AudioInput
    private var detector: PitchDetector
    private var smoother = ReadingSmoother()
    private var reference: ReferencePitch
    /// Frames without a confident reading; after enough of them the display
    /// drops back to "listening" rather than freezing on a stale note.
    private var quietFrames = 0
    private static let quietFramesBeforeIdle = 8

    public init(
        reference: ReferencePitch = .standard, band: ClosedRange<Double> = Detection.fullBand
    ) {
        self.reference = reference
        self.audio = AudioInput()
        self.detector = PitchDetector(sampleRate: audio.sampleRate, band: band)

        audio.onWindow = { [weak self] window in
            // Runs on the analysis queue. Do the DSP here, then hop to main
            // with only the result.
            guard let self else { return }
            let result = self.detector.analyze(window)
            Task { @MainActor in self.consume(result) }
        }
    }

    /// Re-tune the detector when the instrument changes: narrowing the searched
    /// band is what keeps a cello's low C from being found as a violin harmonic.
    public func configure(reference: ReferencePitch, band: ClosedRange<Double>) {
        self.reference = reference
        self.detector = PitchDetector(sampleRate: audio.sampleRate, band: band)
        smoother.reset()
    }

    public func start() async {
        guard await AudioInput.requestPermission() else {
            state = .permissionDenied
            return
        }
        do {
            try audio.start()
            state = .listening
        } catch {
            state = .idle
        }
    }

    public func stop() {
        audio.stop()
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
            if quietFrames >= Self.quietFramesBeforeIdle, audio.isRunning {
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
