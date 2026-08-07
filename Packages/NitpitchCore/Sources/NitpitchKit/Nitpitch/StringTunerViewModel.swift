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

    /// The string this dial answers for. Grid cells never change it; the
    /// string view retargets when swiping between strings.
    public private(set) var target: Note

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

    /// Whether this string joins the grid's intonation check — set through
    /// `setIntonating`, for every sibling at once. Off by default: the grid
    /// is a tuning surface first, and the octave display is a chosen layer.
    public private(set) var isIntonating = false

    /// The octave sounding right now, in cents against 2f — the tiny
    /// strip's live reading. Nil while it isn't. Only moves while
    /// `isIntonating`.
    @Published public private(set) var octaveCents: Double?
    /// The captured samples and the verdict, tenth-quantized — the same
    /// consensus rules as the string view's panel (`IntonationCapture`).
    @Published public private(set) var openSample: Double?
    @Published public private(set) var octaveSample: Double?
    @Published public private(set) var delta: Double?

    private var capture = IntonationCapture()

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
        reference: ReferencePitch = .standard,
        targetOffsetCents: Double = 0
    ) {
        self.audio = audio
        self.target = target
        self.reference = reference
        self.band = band
        self.targetOffsetCents = targetOffsetCents
    }

    /// The temperament's shift of this string's target, in cents from equal
    /// — a violin E's +1.955 under pure fifths. Every cents answer measures
    /// against the shifted target.
    public private(set) var targetOffsetCents: Double

    /// The fine-tuning strobe's state — error as motion, fed from the same
    /// smoothed readings the dial shows. Its own island: only the band
    /// re-renders with it, and only the string view mounts one.
    let strobe = StrobeMonitor()

    /// One reading's worth of time, for the strobe's integrator.
    private static let hopSeconds = Double(Detection.hopSize) / 44100

    /// The tempered target in hertz — what the strobe measures against.
    private var targetHz: Double {
        target.frequency(reference: reference) * pow(2, targetOffsetCents / 1200)
    }

    /// Re-tune when the reference or the band moves. The detector itself lives
    /// in the bank; here only the display copy and the smoothing reset.
    public func configure(
        band: ClosedRange<Double>, reference: ReferencePitch, targetOffsetCents: Double = 0
    ) {
        // A moved reference — or a temperament shifting the target — moves
        // the target's frequency: captures answered for the old one.
        // Incidental re-configures (a lock toggle passing through) keep them.
        if reference != self.reference || targetOffsetCents != self.targetOffsetCents {
            resetIntonation()
        }
        self.reference = reference
        self.band = band
        self.targetOffsetCents = targetOffsetCents
        smoother.reset()
    }

    /// Aim at a different string — the string view swiping to a neighbour.
    /// The smoothing resets: a filter primed on the old target would blend
    /// two strings into one glide.
    public func retarget(_ note: Note) {
        target = note
        smoother.reset()
        resetIntonation()
        strobe.clear()
        if state != .idle { state = .waiting }
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
        strobe.clear()
    }

    /// This string's slice of a frame's analysis, from `StringTuners`.
    func ingest(_ result: DetectionResult) {
        guard state != .idle else { return }
        if isReportingRaw { lastResult = result }
        let quantized = (result.level * 20).rounded() / 20
        if quantized != level { level = quantized }
        guard let hz = result.frequency else {
            feedIntonation(.nothing, level: result.displayLevel)
            quietFrames += 1
            if quietFrames >= Self.quietFramesBeforeIdle, audio.status == .running {
                smoother.reset()
                state = .waiting
                strobe.clear()
                if octaveCents != nil { octaveCents = nil }
            }
            return
        }

        // A confident reading is tuning activity: the screen stays awake.
        audio.pokeScreenAwake()

        let raw = PitchReading(frequency: hz, reference: reference)
        let absolute = Double(raw.note.midi) * 100 + raw.cents
        // Against *this string's* TEMPERED target, not the nearest note. No
        // re-rounding: the answer to "how far is the G string from G" is
        // allowed to be 340 — and under pure fifths, "G" sits 3.9¢ below
        // equal's.
        let epsilon = absolute - Double(target.midi) * 100 - targetOffsetCents

        if isIntonating, result.evenPartialsOnly {
            // The octave is not the open string: the strobe holds its
            // silence rather than crawling at a pitch nobody is tuning.
            strobe.clear()
            ingestOctave(epsilon: epsilon, result: result)
            return
        }
        quietFrames = 0

        feedIntonation(
            .note(slot: .open, cents: epsilon, clarity: result.clarity),
            level: result.displayLevel)
        if octaveCents != nil { octaveCents = nil }

        // Smooth in absolute cents (MIDI×100 + offset) so the filter sees a
        // continuous line rather than a sawtooth at note boundaries — the same
        // reason the chromatic model does it, and the smoother is already
        // target-agnostic.
        let smoothed = smoother.update(cents: absolute)
        let cents = smoothed - Double(target.midi) * 100 - targetOffsetCents
        state = .reading(cents: cents, clarity: result.clarity)
        strobe.ingest(cents: cents, targetHz: targetHz, dt: Self.hopSeconds)
    }

    /// The octave, recognized by parity through this string's own slots:
    /// the estimate lands at f(1+ε) where ε is the octave's deviation from
    /// 2f, so one number serves both scales. The open display stands down
    /// softly — a held reading survives a flicker, sustained octave play
    /// fades it through the quiet path.
    private func ingestOctave(epsilon: Double, result: DetectionResult) {
        feedIntonation(
            .note(slot: .octave, cents: epsilon, clarity: result.clarity),
            level: result.displayLevel)
        let half = (epsilon * 2).rounded() / 2
        if half != octaveCents { octaveCents = half }
        quietFrames += 1
        if quietFrames >= Self.quietFramesBeforeIdle {
            smoother.reset()
            state = .waiting
        }
    }

    /// The capture's diet, gated on the layer being on at all.
    private func feedIntonation(_ sounding: IntonationSounding, level: Double) {
        guard isIntonating else { return }
        capture.ingest(IntonationAnalyzer.Frame(sounding: sounding, level: level))
        publishSamples()
    }

    /// Join or leave the intonation check. Captures do not survive the
    /// flip in either direction: a stale measurement reappearing later
    /// would look authoritative and be anything but.
    public func setIntonating(_ on: Bool) {
        guard isIntonating != on else { return }
        isIntonating = on
        resetIntonation()
    }

    private func resetIntonation() {
        capture.reset()
        octaveCents = nil
        openSample = nil
        octaveSample = nil
        delta = nil
    }

    private func publishSamples() {
        let tenth = { (value: Double) in (value * 10).rounded() / 10 }
        let nextOpen = capture.open.map(tenth)
        let nextOctave = capture.octave.map(tenth)
        let nextDelta = capture.delta.map(tenth)
        if nextOpen != openSample { openSample = nextOpen }
        if nextOctave != octaveSample { octaveSample = nextOctave }
        if nextDelta != delta { delta = nextDelta }
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
            strobe.ingest(cents: cents, targetHz: targetHz, dt: 0.05)
            level = ((0.55 + 0.25 * sin(tick * 1.7)) * 20).rounded() / 20
            // A finished measurement per string, values varied by target so
            // the layout is judged with cells disagreeing. Modulo 11, which
            // no regular tuning defeats: fifths collapsed mod 7 (a violin's
            // four cells all read the same Δ) and fourths would mod 5.
            if isIntonating, openSample == nil {
                openSample = -1.5
                octaveSample = Double(target.midi % 11) - 3.5
                delta = (octaveSample ?? 0) - (openSample ?? 0)
                octaveCents = octaveSample
            }
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
