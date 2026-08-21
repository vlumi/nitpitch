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
    /// The last note's slot, and whether the string has gone quiet since —
    /// what separates a fresh octave from a decaying open (see `analyze`).
    private var lastNoteSlot: IntonationSlot?
    private var quietFrames = 0
    /// Consecutive frames WITHOUT a reading of this string before a
    /// following note counts as a fresh attack rather than the same note
    /// continuing. No reading, not RMS silence: fretting the 12th stops the
    /// open string instantly while the OTHER strings ring on — the window
    /// never goes quiet, but this string does (field-found: at a hot input
    /// gain the RMS test saw no gap, ever, and every 12th fret stayed "the
    /// open's tail" — unregistered on G/B/D, and on E the unclaimed octave
    /// never fired the focus boost, so E3 read as the D string whose band
    /// it sits in). Five frames (~230 ms) — a real refinger takes longer,
    /// while the raw per-window flicker a decaying tail throws is shorter.
    private static let freshAttackQuietFrames = 5
    /// The loudest recent window RMS, fading slowly — what "silence" is
    /// judged AGAINST. An absolute threshold broke at a hot input gain: the
    /// interface's noise floor alone exceeded it, no damp was ever seen,
    /// and every octave was reclassified as the open string's decay tail —
    /// intonation died entirely (field-found: raising the Mac input volume
    /// for a quiet guitar killed the panel; lowering it starved the plain
    /// strings instead).
    private var peakRMS: Float = 0
    /// A window this far below the recent peak is a damp whatever the
    /// absolute floor: ~34 dB down — below any tail worth measuring, above
    /// an interface's noise floor at any practical gain.
    private static let dampShare: Float = 0.02
    /// The peak reference fades ~2 dB/s, so one early loud pluck doesn't
    /// set an unreachable bar for quieter playing after it.
    private static let peakDecayPerFrame: Float = 0.99
    /// What the target's slots held while the string was QUIET — the
    /// neighbours' standing deposit. On a guitar the low E's harmonics sit
    /// 2 cents from EVERY slot of the B string (E2 × 3 ≈ B3), so a ringing
    /// E impersonates the open B outright — same anchor, same agreement —
    /// and no gate on the reading itself can tell them apart. What can:
    /// a ring is STATIONARY, a played note is new energy. The verdicts in
    /// `analyze` are made on what the sound ADDED to this snapshot.
    private var restingSlots: [Double]?
    /// A note must bring at least this share of its slots' current energy
    /// as NEW energy — below it, the "note" is the resting ring persisting
    /// through the reading gates, and the string is quiet.
    private static let freshEnergyShare = 0.25
    /// The loudest recent slot total, fading slowly — the drop detector.
    /// The resting snapshot is frozen while a note sounds, so the moment
    /// the note ends, what survives (the neighbours' ring) would read as
    /// "new" against the stale snapshot. It isn't new — it's what's LEFT:
    /// a frame whose slots hold only a fraction of their recent peak is
    /// residue, however cleanly it reads, and it teaches the snapshot.
    private var slotPeak = 0.0
    private static let residueShare = 0.3
    private static let slotPeakDecayPerFrame = 0.99
    /// A no-reading frame teaches the resting snapshot only once the quiet
    /// has HELD this long: a one-frame gate flutter mid-note must not
    /// absorb the note itself into the snapshot (everything after would
    /// read as "nothing new"), while a real refinger gap has frames to
    /// spare. The high-confidence residue path (a collapsed slot total)
    /// teaches immediately.
    private static let restingLearnQuietFrames = 3

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
        peakRMS = 0
        restingSlots = nil
        slotPeak = 0
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

    /// The drop test: slots holding a fraction of their recent peak are
    /// what SURVIVED the note, not a new one — the ring, teaching the
    /// resting snapshot — however cleanly they might read. True consumes
    /// the frame as quiet, bookkeeping done. Teaching also RE-ARMS the
    /// peak to the leftovers' scale: the note whose residue was feared is
    /// over, and the next note must be judged fresh against its own world
    /// — a fretted 12th is honestly quieter than the open pluck before it
    /// (half the slots, softer attack), and holding it to the open's peak
    /// swallowed most octaves whole (field-found: "2nd harmonic" on the
    /// dial, nothing in the panel, every string). The fresh-energy gate
    /// below stays the durable guard against the ring itself.
    private func consumedAsResidue(slots: [Double]) -> Bool {
        let slotTotal = slots.reduce(0, +)
        guard slotTotal < slotPeak * Self.residueShare else {
            slotPeak = max(slotPeak * Self.slotPeakDecayPerFrame, slotTotal)
            return false
        }
        restingSlots = slots
        slotPeak = slotTotal
        quietFrames += 1
        return true
    }

    /// What this sound ADDED to the resting slots — or nil, consuming the
    /// frame as quiet, when it added (nearly) nothing: a ring that
    /// impersonates the string (the guitar E's harmonics ARE the B's slots,
    /// two cents off) passes every reading gate and still adds nothing.
    /// Every verdict is judged on the note's own energy, not the ring's.
    /// Consuming re-arms the peak the same way residue does.
    private func freshEnergy(slots: [Double]) -> [Double]? {
        let resting = restingSlots ?? []
        let fresh = slots.enumerated().map { index, weight in
            max(0, weight - (index < resting.count ? resting[index] : 0))
        }
        guard fresh.reduce(0, +) >= slots.reduce(0, +) * Self.freshEnergyShare else {
            restingSlots = slots
            slotPeak = slots.reduce(0, +)
            quietFrames += 1
            return nil
        }
        return fresh
    }

    /// No reading of THIS string is this string going quiet, however loud
    /// the neighbours keep the window (see quietFrames) — and once the
    /// quiet holds, what the slots still carry is the neighbours' deposit,
    /// and the peak re-arms to its scale.
    private func consumeUnread(slots: [Double]) {
        quietFrames += 1
        if quietFrames >= Self.restingLearnQuietFrames {
            restingSlots = slots
            slotPeak = slots.reduce(0, +)
        }
    }

    /// One window in, one verdict out — or nil while the mode is off.
    public func analyze(_ window: [Float]) -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        guard active, target > 0 else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))
        let level = Detection.displayLevel(rms: Double(rms))
        let silenceFloor = max(tuning.silenceRMS, peakRMS * Self.dampShare)
        peakRMS = max(peakRMS * Self.peakDecayPerFrame, rms)
        guard rms > silenceFloor else {
            estimator?.reset()
            // True silence: the slots hold nothing.
            restingSlots = nil
            slotPeak = 0
            quietFrames += 1
            return Frame(sounding: .nothing, level: level)
        }

        let estimator = self.estimator ?? HarmonicEstimator(sampleRate: sampleRate)
        self.estimator = estimator
        estimator.ingest(window)

        let slots = estimator.slotWeights(target: target) ?? []
        guard !consumedAsResidue(slots: slots) else {
            return Frame(sounding: .nothing, level: level)
        }

        guard let reading = estimator.measure(target: target, others: []),
            reading.strength >= tuning.spectralStrengthGate
        else {
            consumeUnread(slots: slots)
            return Frame(sounding: .nothing, level: level)
        }
        guard let fresh = freshEnergy(slots: slots) else {
            return Frame(sounding: .nothing, level: level)
        }
        // Orders 1, 3, 5 live at even indices.
        let freshOdd = stride(from: 0, to: fresh.count, by: 2)
            .map { fresh[$0] }.reduce(0, +)
        let cents = PitchMath.cents(from: target, to: reading.frequency)
        var slot: IntonationSlot =
            freshOdd <= fresh.reduce(0, +) * HarmonicEstimator.oddPollutionShare
            ? .octave : .open
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
