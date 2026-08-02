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
    /// Minimum NSDF peak height to accept an estimate. Raising it rejects more
    /// marginal frames; lowering it makes the dial livelier and twitchier.
    public var clarityThreshold: Double

    /// Fraction of the tallest peak a shorter-lag candidate must reach to win.
    /// This is the octave guard: lower it and the fundamental beats its own
    /// harmonics more readily, but genuine higher notes start reading an octave
    /// low.
    public var peakPickThreshold: Double

    /// Frames quieter than this are skipped before any DSP.
    public var silenceRMS: Float

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
        clarityThreshold: Double = Detection.clarityThreshold,
        peakPickThreshold: Double = Detection.peakPickThreshold,
        silenceRMS: Float = Detection.silenceRMS,
        maxSemitonesFromString: Double = Instrument.outerHeadroomSemitones
    ) {
        self.clarityThreshold = clarityThreshold
        self.peakPickThreshold = peakPickThreshold
        self.silenceRMS = silenceRMS
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
        public static let semitones: ClosedRange<Double> =
            0.5...Instrument.outerHeadroomSemitones
    }
}
