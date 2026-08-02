import Combine
import Foundation
import NitpitchCore

/// Drives one string's dial: watches its own narrow band and reports how far
/// that string is from where it should be.
///
/// A sibling of `NitpitchViewModel` rather than a mode of it. The chromatic
/// model resolves each reading to whichever note is *nearest*; this one knows
/// its target up front and measures against that, so it never re-rounds and
/// never renames. Folding both into one type would put a conditional through
/// the middle of the only interesting step.
///
/// Several are live at once — one per string — all subscribing to the same
/// `AudioSessionController` stream.
@MainActor
public final class StringTunerViewModel: ObservableObject {
    /// What this string's dial should show.
    public enum State: Equatable {
        /// Not started, or stopped.
        case idle
        /// Listening, but nothing in this string's band.
        case waiting
        /// How far this string is from its target, in cents. Can exceed ±50:
        /// a string a whole tone flat reads −200, and the dial pins while the
        /// number keeps counting.
        case reading(cents: Double, clarity: Double)
    }

    @Published public private(set) var state: State = .idle

    /// The string this dial answers for.
    public let target: Note

    /// The last frame's raw detector output, before smoothing and before the
    /// state machine decides whether to show anything — the difference between
    /// "this dial is blank" and knowing *why* it's blank, which is the whole
    /// question when tuning thresholds against a real instrument.
    ///
    /// Only published while `isReportingRaw`: this changes on every frame,
    /// ~21×/second per string, and publishing it unconditionally would redraw
    /// every cell in the grid that often even with no diagnostics on screen.
    @Published public private(set) var lastResult: DetectionResult = .silent

    /// Whether to publish `lastResult`. Set by the diagnostics screen while
    /// it's visible, so the cost is paid only when someone is watching.
    public var isReportingRaw = false

    /// The band this dial currently searches, for the diagnostics readout.
    public private(set) var band: ClosedRange<Double>

    private let audio: AudioSessionController
    private var subscription: AudioSessionController.Subscription?
    /// The synthetic-reading loop, when running under `-demo`.
    private var demo: Task<Void, Never>?
    private var detector: PitchDetector
    private var smoother = ReadingSmoother()
    private var reference: ReferencePitch
    /// Frames with nothing in this string's band; after enough of them the
    /// dial clears rather than freezing on a stale reading.
    private var quietFrames = 0
    private static let quietFramesBeforeIdle = 8

    public init(
        audio: AudioSessionController,
        target: Note,
        band: ClosedRange<Double>,
        reference: ReferencePitch = .standard,
        tuning: DetectionTuning = .default
    ) {
        self.audio = audio
        self.target = target
        self.reference = reference
        self.band = band
        self.detector = PitchDetector(sampleRate: audio.sampleRate, band: band, tuning: tuning)
    }

    /// Re-tune when the reference or the band moves. Rebuilds the detector,
    /// since the band is baked into its lag bounds and its scratch buffers.
    public func configure(band: ClosedRange<Double>, reference: ReferencePitch) {
        self.reference = reference
        self.band = band
        let tuning = detector.tuning
        self.detector = PitchDetector(sampleRate: audio.sampleRate, band: band, tuning: tuning)
        smoother.reset()
    }

    /// Change the thresholds without disturbing the band.
    ///
    /// Deliberately not a rebuild: the sliders move continuously, and throwing
    /// away the smoother on every tick would make the dial jump in a way that
    /// has nothing to do with the threshold being tested.
    public func retune(_ tuning: DetectionTuning) {
        detector.tuning = tuning
    }

    public func attach() {
        guard subscription == nil, demo == nil else { return }
        if LaunchStores.isDemo {
            demo = Task { await runDemo() }
            return
        }
        subscription = audio.subscribe { [weak self] window in
            // Runs on the analysis queue. Do the DSP here, then hop to main
            // with only the result.
            guard let self else { return }
            let result = self.detector.analyze(window)
            Task { @MainActor in self.consume(result) }
        }
        state = .waiting
    }

    /// Drives this dial from a synthetic reading where there's no usable
    /// microphone (see `LaunchStores.isDemo`) — the grid is otherwise a page of
    /// blank cells on the simulator, which is no use for judging the layout.
    ///
    /// Each string swings at its own rate and phase, offset by its position in
    /// the instrument. A grid moving in lockstep would look like one dial drawn
    /// six times and would hide exactly what the layout has to survive: cells
    /// disagreeing, some in tune while others are pinned at the ends.
    private func runDemo() async {
        state = .waiting
        var tick = phaseOffset

        while !Task.isCancelled {
            let swing = sin(tick) * 0.75 + sin(tick * 0.31) * 0.25
            let cents = swing * TuningDisplay.fullScaleCents
            state = .reading(cents: cents, clarity: 0.98)
            // A plausible raw result too, so the diagnostics screen shows
            // moving numbers rather than a column of dashes.
            if isReportingRaw {
                let hz = target.frequency(reference: reference) * pow(2, cents / 1200)
                lastResult = DetectionResult(frequency: hz, clarity: 0.98, rms: 0.05)
            }

            tick += 0.055
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Where this string starts in the demo swing, so the dials don't move as
    /// one. Derived from the target rather than the index — the model doesn't
    /// know its position in the grid, and this is stable across rebuilds.
    private var phaseOffset: Double {
        Double(target.midi % 12) * 0.5
    }

    /// Stop listening. Leaves the engine alone — it's shared.
    public func detach() {
        subscription?.cancel()
        subscription = nil
        demo?.cancel()
        demo = nil
        smoother.reset()
        state = .idle
    }

    private func consume(_ result: DetectionResult) {
        if isReportingRaw { lastResult = result }
        guard let hz = result.frequency else {
            quietFrames += 1
            if quietFrames >= Self.quietFramesBeforeIdle, audio.status == .running {
                smoother.reset()
                state = .waiting
            }
            return
        }
        quietFrames = 0

        // Smooth in absolute cents (MIDI×100 + offset) so the filter sees a
        // continuous line rather than a sawtooth at note boundaries — the same
        // reason the chromatic model does it, and the smoother is already
        // target-agnostic.
        let raw = PitchReading(frequency: hz, reference: reference)
        let absolute = Double(raw.note.midi) * 100 + raw.cents
        let smoothed = smoother.update(cents: absolute)
        // Against *this string*, not the nearest note. No re-rounding: the
        // answer to "how far is the G string from G" is allowed to be 340.
        let cents = smoothed - Double(target.midi) * 100
        state = .reading(cents: cents, clarity: result.clarity)
    }
}
