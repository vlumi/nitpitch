import Combine
import Foundation
import NitpitchCore

/// Drives one string's dial: takes that string's detection results and reports
/// how far the string is from where it should be.
///
/// A sibling of `NitpitchViewModel` rather than a mode of it. The chromatic
/// model resolves each reading to whichever note is *nearest*; this one knows
/// its target up front and measures against that, so it never re-rounds and
/// never renames. Folding both into one type would put a conditional through
/// the middle of the only interesting step.
///
/// Unlike the chromatic model it does **not** subscribe to audio or run a
/// detector: the strings of an instrument can't be judged independently — one
/// played note shows up in several detectors and something has to compare them
/// (see `DetectorBank`) — so `StringTuners` analyses each window once for the
/// whole instrument and feeds every dial its own slice through `ingest`.
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

    /// Signal strength behind the current reading, 0...1, for the cell's
    /// signal bar. Zero while nothing reads: no reading, no authority.
    ///
    /// Quantized to twentieths before publishing — it arrives ~21×/second per
    /// string, and re-rendering every cell for an invisible change is the kind
    /// of cost a grid of N dials can't afford.
    @Published public private(set) var level: Double = 0

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

    /// The band this dial's detector searches, for the diagnostics readout.
    /// Owned and used by `DetectorBank`; this copy is display only.
    public private(set) var band: ClosedRange<Double>

    private let audio: AudioSessionController
    /// The synthetic-reading loop, when running under `-demo`.
    private var demo: Task<Void, Never>?
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
        reference: ReferencePitch = .standard
    ) {
        self.audio = audio
        self.target = target
        self.reference = reference
        self.band = band
    }

    /// Re-tune when the reference or the band moves. The detector itself lives
    /// in the bank; here only the display copy and the smoothing reset.
    public func configure(band: ClosedRange<Double>, reference: ReferencePitch) {
        self.reference = reference
        self.band = band
        smoother.reset()
    }

    /// Start showing readings. Under `-demo` this runs the synthetic swing;
    /// otherwise results arrive from outside through `ingest`.
    public func begin() {
        if LaunchStores.isDemo {
            guard demo == nil else { return }
            demo = Task { await runDemo() }
            return
        }
        state = .waiting
    }

    /// Stop. Safe to call repeatedly.
    public func end() {
        demo?.cancel()
        demo = nil
        smoother.reset()
        state = .idle
        level = 0
    }

    /// This string's slice of a frame's analysis, from `StringTuners`.
    func ingest(_ result: DetectionResult) {
        guard state != .idle else { return }
        if isReportingRaw { lastResult = result }
        let quantized = (result.level * 20).rounded() / 20
        if quantized != level { level = quantized }
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
            level = ((0.55 + 0.25 * sin(tick * 1.7)) * 20).rounded() / 20
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
}
