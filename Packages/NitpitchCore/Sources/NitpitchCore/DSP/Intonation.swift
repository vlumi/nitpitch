import Accelerate
import Foundation

/// Which of the intonation check's two notes a reading belongs to.
public enum IntonationSlot: Equatable, Sendable {
    /// The string played open — the reference the octave is judged against.
    case open
    /// The note an octave up: fretted at the 12th, fingered at the octave,
    /// or the natural harmonic — whichever the player's method uses, they
    /// all land here.
    case octave
}

/// What one analysis window turned out to hold, intonation-wise.
public enum IntonationSounding: Equatable, Sendable {
    case nothing
    /// A note attributed to a slot, as cents against that slot's own
    /// target (open vs f, octave vs 2f).
    case note(slot: IntonationSlot, cents: Double, clarity: Double)
}

/// The intonation check, headless: is a string's octave where the open
/// string says it should be?
///
/// One estimator target — the OPEN string — and no second one for the
/// octave, because the octave *can't* have its own: every partial of a note
/// at 2f sits on one of f's even harmonic slots, so a second target would
/// find all of its evidence shared and measure nothing
/// (`HarmonicEstimator.measure` skips shared partials entirely). What
/// actually separates the two notes is **parity**: the open string always
/// brings odd evidence (3f and 5f survive even where a microphone rolls the
/// fundamental off), while a note at 2f sounds even slots exclusively
/// (`Reading.evenPartialsOnly`).
///
/// Both notes then measure on the same scale. An even-only estimate f̂ means
/// the sounding note is at 2f̂, and its deviation from 2f in cents equals
/// f̂'s from f — one number serves whichever slot the parity picks.
///
/// Spectral only, no MPM fallback: intonation is checked on a string that's
/// already tuned, so the discovery engine's territory — a peg three
/// semitones out — is out of scope by definition here.
public final class IntonationAnalyzer: @unchecked Sendable {
    /// One window's verdict.
    public struct Frame: Equatable, Sendable {
        public let sounding: IntonationSounding
        /// Meter drive, 0...1 — `Detection.displayLevel`, so the meter
        /// reads identically in and out of the mode.
        public let level: Double

        public init(sounding: IntonationSounding, level: Double) {
            self.sounding = sounding
            self.level = level
        }
    }

    /// Same locking story as `DetectorBank`: `analyze` runs on the audio
    /// analysis queue while configuration arrives from the main actor.
    private let lock = NSLock()
    private let sampleRate: Double
    /// The open string's frequency, in hertz.
    private var target: Double
    private var tuning: DetectionTuning
    /// Created on first use, kept across mode toggles — same economics as
    /// the bank's estimator.
    private var estimator: HarmonicEstimator?
    /// Whether the mode is on. `analyze` answers nil while it isn't, so the
    /// subscription can call unconditionally and pay nothing when off.
    private var active = false
    /// The last note's slot, and whether real silence has passed since —
    /// what separates a fresh octave from a decaying open (see `analyze`).
    private var lastNoteSlot: IntonationSlot?
    private var quietFrames = 0
    /// Consecutive RMS-silent frames before a following note counts as a
    /// fresh attack rather than the same note continuing.
    private static let freshAttackQuietFrames = 3

    public init(sampleRate: Double, target: Double = 0, tuning: DetectionTuning = .default) {
        self.sampleRate = sampleRate
        self.target = target
        self.tuning = tuning
    }

    /// Aim at a string. Resets the phase pair: the estimator must not
    /// compare windows across a retarget.
    public func configure(target: Double, tuning: DetectionTuning) {
        lock.lock()
        defer { lock.unlock() }
        self.target = target
        self.tuning = tuning
        estimator?.reset()
        lastNoteSlot = nil
        quietFrames = 0
    }

    public func setActive(_ isActive: Bool) {
        lock.lock()
        defer { lock.unlock() }
        active = isActive
        if !isActive { estimator?.reset() }
    }

    /// Capture stopped and restarted — the phase pair must not span the gap.
    public func interrupted() {
        lock.lock()
        defer { lock.unlock() }
        estimator?.reset()
    }

    /// One window in, one verdict out — or nil while the mode is off.
    public func analyze(_ window: [Float]) -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        guard active, target > 0 else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))
        let level = Detection.displayLevel(rms: Double(rms))
        guard rms > tuning.silenceRMS else {
            estimator?.reset()
            quietFrames += 1
            return Frame(sounding: .nothing, level: level)
        }

        let estimator = self.estimator ?? HarmonicEstimator(sampleRate: sampleRate)
        self.estimator = estimator
        estimator.ingest(window)

        guard let reading = estimator.measure(target: target, others: []),
            reading.strength >= tuning.spectralStrengthGate
        else {
            return Frame(sounding: .nothing, level: level)
        }
        let cents = PitchMath.cents(from: target, to: reading.frequency)
        var slot: IntonationSlot = reading.evenPartialsOnly ? .octave : .open
        // A decaying open string sheds its ODD partials first — the weak
        // fundamental and the 3rd fade into the floor while the 2nd lingers —
        // so its tail reads even-only: the octave's fingerprint on a note
        // that isn't one (field-found on a bass, flashing the delta at the
        // end of every open pluck). A real octave arrives after a GAP (damp,
        // refinger); a direct open→octave transition with no silence between
        // is the same note dying, and is measured as what it is — the folded
        // cents are identical by construction.
        if slot == .octave, lastNoteSlot == .open,
            quietFrames < Self.freshAttackQuietFrames
        {
            slot = .open
        }
        lastNoteSlot = slot
        quietFrames = 0
        return Frame(
            sounding: .note(slot: slot, cents: cents, clarity: reading.agreement),
            level: level)
    }
}

/// The two captured samples and the verdict between them, built one frame at
/// a time. Pure state — no audio, no clocks — so the gating rules are
/// testable as arithmetic.
///
/// A sample records only from a **consensus**: at least `stableFrames`
/// frames in the same slot agreeing within `stabilityWindowCents`, out of a
/// rolling run of up to `runLength`. That's what keeps a sympathetic
/// resonance, a transient octave-jump, or the tail of a decaying pluck out
/// of the record — cross-talk may flicker on the live display all it wants,
/// but a captured number has to have been *held*. Within a continuing run
/// the sample keeps refreshing, and a later run simply replaces the value:
/// latest wins, so a polluted capture costs one deliberate re-play, not a
/// reset ritual.
///
/// Inliers around the median, not a spread veto — the shape a bass demanded
/// (and its player proposed). A picked low string wobbles at the attack and
/// dies toward the gate quickly, so the frames worth keeping are scattered
/// among ones that aren't; demanding that the *last N* frames be
/// collectively tight held the lock hostage to where the wobble landed.
/// Instead the run's median names the consensus, frames within half the
/// window of it are the evidence, and enough evidence locks — outliers are
/// discarded rather than given a veto. A genuine drift still refuses:
/// drifting values never put `stableFrames` of themselves around one
/// median. Silence gets `quietGraceFrames` of grace (late-decay frames
/// flicker at the strength gate), and the pause before a re-play after a
/// saddle adjustment is what resets the run.
public struct IntonationCapture: Equatable, Sendable {
    /// Agreeing same-slot frames a sample needs — just over a quarter
    /// second of evidence at the ~21 Hz analysis rate.
    public static let stableFrames = 6
    /// How many recent frames the run remembers — about a pluck's worth
    /// above the gate.
    public static let runLength = 16
    /// The consensus band, in cents: an inlier sits within half of this of
    /// the run's median.
    public static let stabilityWindowCents = 4.0
    /// How many below-gate frames a run survives before it resets.
    public static let quietGraceFrames = 4

    /// The open string's deviation from its target, in cents.
    public private(set) var open: Double?
    /// The octave note's deviation from ITS target (2f), in cents.
    public private(set) var octave: Double?
    /// The intonation verdict: how far the octave sits from where the open
    /// string promises it, in cents. Positive = octave sharp — on a guitar,
    /// the saddle wants to move back. Nil until both slots have samples.
    public var delta: Double? {
        guard let open, let octave else { return nil }
        return octave - open
    }

    private var runSlot: IntonationSlot?
    private var run: [Double] = []
    private var quietRun = 0

    public init() {}

    public mutating func ingest(_ frame: IntonationAnalyzer.Frame) {
        guard case .note(let slot, let cents, _) = frame.sounding else {
            quietRun += 1
            if quietRun > Self.quietGraceFrames {
                runSlot = nil
                run.removeAll(keepingCapacity: true)
            }
            return
        }
        quietRun = 0
        if slot != runSlot {
            runSlot = slot
            run.removeAll(keepingCapacity: true)
        }
        run.append(cents)
        if run.count > Self.runLength {
            run.removeFirst()
        }
        guard run.count >= Self.stableFrames else { return }
        // The run's median names the consensus; frames within half the
        // window of it are the evidence. Enough evidence locks, and the
        // value is the median of the evidence alone — an outlier neither
        // vetoes the lock nor leaves a fingerprint on the number.
        let consensus = Self.median(run.sorted())
        let inliers = run.filter { abs($0 - consensus) <= Self.stabilityWindowCents / 2 }
        guard inliers.count >= Self.stableFrames else { return }
        let value = Self.median(inliers.sorted())
        switch slot {
        case .open: open = value
        case .octave: octave = value
        }
    }

    private static func median(_ sorted: [Double]) -> Double {
        (sorted[sorted.count / 2] + sorted[(sorted.count - 1) / 2]) / 2
    }

    public mutating func reset() {
        open = nil
        octave = nil
        runSlot = nil
        run.removeAll(keepingCapacity: true)
        quietRun = 0
    }
}
