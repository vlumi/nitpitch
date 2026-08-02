import Foundation

/// The detector's thresholds, as a value that can be varied at runtime.
///
/// These began as constants in `Detection` and mostly still read from there for
/// their defaults. They became a value because the right numbers can't be
/// derived — they depend on the instrument, the room, and the microphone, and
/// the only way to find them is to sit with an instrument and turn the knobs.
/// The debug screen does exactly that; everywhere else uses `.default` and
/// behaves as it always did.
///
/// Deliberately *not* persisted alongside `Settings`: these aren't preferences,
/// they're a diagnostic. A value found here is meant to be read off and written
/// into `Detection` as the new constant, not carried around per-user.
public struct DetectionTuning: Equatable, Sendable {
    /// Which algorithm drives the per-string dials.
    public enum Engine: String, CaseIterable, Sendable {
        /// One `PitchDetector` per string over its own band, with
        /// `SubharmonicFilter` arbitrating between them. Monophonic: two
        /// strings at once confuse it — but it finds a string from anywhere
        /// in its band, semitones off target, and needs no fundamental.
        case mpm
        /// One `HarmonicEstimator` measuring every string from a shared
        /// spectrum. Handles double stops and is structurally immune to
        /// subharmonics, but declines a string more than `searchCents` from
        /// target, and needs the string's own low harmonics to reach the
        /// microphone (see the anchor rule).
        case spectral
        /// The shipped default: spectral wins any frame where it reads
        /// anything; MPM takes only the frames where spectral is silent.
        /// Whole frames, not per string — during a double stop MPM invents
        /// subharmonic ghosts on the unplayed strings, and a per-string
        /// fallback would reinsert exactly the readings spectral exists to
        /// prevent. Frame-level keeps every spectral win and still finds a
        /// badly slack string (or a mic'd bass with no audible fundamental),
        /// because those are precisely the frames spectral declines.
        case hybrid
    }

    /// Which algorithm drives the per-string dials.
    public var engine: Engine

    /// Minimum NSDF peak height to accept an estimate. Raising it rejects more
    /// marginal frames; lowering it makes the dial livelier and twitchier.
    /// MPM only.
    public var clarityThreshold: Double

    /// Fraction of the tallest peak a shorter-lag candidate must reach to win.
    /// This is the octave guard: lower it and the fundamental beats its own
    /// harmonics more readily, but genuine higher notes start reading an octave
    /// low.
    public var peakPickThreshold: Double

    /// Frames quieter than this are skipped before any DSP.
    ///
    /// Note what this can and cannot do: it judges the *whole frame*, so it
    /// only rejects actual silence. While anything is being played the frame
    /// is loud, the gate passes, and per-string junk has to be caught by
    /// `spectralStrengthGate` instead.
    public var silenceRMS: Float

    /// Spectral readings weaker than this are dropped — same 0...1 units as
    /// the cells' signal bars, so "junk shows below half, a bowed string near
    /// max" translates directly into a setting between the two. Spectral only;
    /// MPM has its clarity gate.
    ///
    /// The default was calibrated on a violin through a Mac microphone: junk
    /// sat below half, single bowed strings at or near full, and in a sloppy
    /// double stop the weaker string dipped intermittently below 0.9 — 0.75
    /// keeps it.
    public var spectralStrengthGate: Double

    /// A dial that wasn't reading lights only after this many consecutive
    /// frames agree — single-frame coincidences (a bow-attack transient landing
    /// right, one lucky frame of noise) never reach the screen. Costs one hop
    /// (~46 ms) at first light-up only: an already-lit dial tracks instantly,
    /// and the dropout side is separate (and slower) by design. Applies to
    /// both engines. 1 disables it.
    public var confirmationFrames: Int

    /// How far either side of a string's target its dial still answers, in
    /// semitones — but only as a *cap*. The real boundary is the midpoint to
    /// the neighbouring string, which is what guarantees the bands tile with no
    /// gaps; this narrows a band when the neighbour is further away than this.
    ///
    /// The default matches `Instrument.outerHeadroomSemitones`, the widest
    /// reach any shipped band has, so at the default it clips nothing and
    /// turning it down is a pure experiment. Anything narrower is a diagnostic:
    /// it opens gaps between the bands, and a pitch in a gap lights no dial.
    public var maxSemitonesFromString: Double

    public init(
        engine: Engine = .hybrid,
        clarityThreshold: Double = Detection.clarityThreshold,
        peakPickThreshold: Double = Detection.peakPickThreshold,
        silenceRMS: Float = Detection.silenceRMS,
        spectralStrengthGate: Double = 0.75,
        confirmationFrames: Int = 2,
        maxSemitonesFromString: Double = Instrument.outerHeadroomSemitones
    ) {
        self.engine = engine
        self.clarityThreshold = clarityThreshold
        self.peakPickThreshold = peakPickThreshold
        self.silenceRMS = silenceRMS
        self.spectralStrengthGate = spectralStrengthGate
        self.confirmationFrames = confirmationFrames
        self.maxSemitonesFromString = maxSemitonesFromString
    }

    /// What the app ships with — the constants in `Detection`.
    public static let `default` = DetectionTuning()

    /// The range each knob may be moved over, for the debug sliders. Wider than
    /// anything sensible on purpose: the point of the screen is to find out
    /// where it stops working, which means being able to go there.
    public enum Limits {
        public static let clarity: ClosedRange<Double> = 0.5...0.99
        public static let peakPick: ClosedRange<Double> = 0.5...1.0
        public static let silence: ClosedRange<Double> = 0.0001...0.02
        public static let strength: ClosedRange<Double> = 0.0...0.9
        public static let confirmation: ClosedRange<Double> = 1...4
        public static let semitones: ClosedRange<Double> =
            0.5...Instrument.outerHeadroomSemitones
    }
}
