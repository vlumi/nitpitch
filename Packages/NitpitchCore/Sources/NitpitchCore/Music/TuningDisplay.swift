import Foundation

/// Geometry for the tuning display, kept out of the view so it can be tested.
///
/// Two representations of the same cent offset, because they answer different
/// questions: the arc is a coarse "how far, which way" read from across a
/// room, and the lights are the fine one you actually tune against.
public enum TuningDisplay {
    /// ±5 cents — the band a player can't hear as mistuned, and what the
    /// readout treats as in tune.
    public static let inTuneCents = 5.0

    /// The cent offset at which the arc reaches full sweep. Beyond a semitone
    /// the note name itself has changed, so there's nothing to gain from more
    /// travel.
    public static let fullScaleCents = 50.0

    /// The arc's angular sweep from top-centre, in degrees, at full scale.
    ///
    /// A semitone of error swings the arc a quarter turn — far enough to be
    /// unmistakable, short of the horizontal where the band would start to
    /// double back on itself visually.
    public static let fullScaleDegrees = 90.0

    /// The arc for a cent offset: a band starting at vertical top-centre and
    /// sweeping toward the sharp or flat side.
    ///
    /// `sweep` carries both magnitude and direction (signed degrees), while
    /// `thickness` grows only once past the in-tune band. So being in tune is
    /// a thin mark standing straight up, and error reads as the band both
    /// swinging round and fattening.
    public struct Arc: Equatable, Sendable {
        /// Signed angular sweep from vertical, in degrees. Negative = flat
        /// (counter-clockwise), positive = sharp (clockwise).
        public let sweepDegrees: Double
        /// Band thickness, 0 (in tune) through 1 (a semitone or more off).
        public let thickness: Double

        public init(sweepDegrees: Double, thickness: Double) {
            self.sweepDegrees = sweepDegrees
            self.thickness = thickness
        }
    }

    /// The sweep curve's knee: the in-tune boundary's cents, and the angle
    /// it lands at. Inside the knee the sweep is linear (a log has no
    /// zero); outside, each DOUBLING of the error adds the same angle.
    private static let sweepKneeCents = 2.0
    private static let sweepKneeDegrees = 18.0

    /// Maps a cent offset to the arc's sweep and thickness.
    ///
    /// Sweep is LOGARITHMIC in the offset, like the light strip below it —
    /// the ear's sensitivity to mistuning is proportional, so equal RATIOS
    /// of error get equal angles. Linear sweep spent nearly all its travel
    /// on errors too large to care about precisely: the last two cents of
    /// a peg turn moved the needle 3.6°, invisible exactly where tuning
    /// actually happens. Now ±2¢ is 18°, and every doubling beyond adds
    /// ~15.5° — so the ticks, which share this mapping, land at even
    /// spacing on the same doubling thresholds as the dots. Thickness
    /// stays at zero through the in-tune band so a thin upright mark means
    /// right, then grows as the note goes clearly wrong.
    public static func arc(forCents cents: Double) -> Arc {
        guard cents.isFinite else { return Arc(sweepDegrees: 0, thickness: 0) }
        let clamped = cents.clamped(to: -fullScaleCents...fullScaleCents)
        let magnitude = abs(clamped)
        let degrees: Double
        if magnitude <= sweepKneeCents {
            degrees = magnitude / sweepKneeCents * sweepKneeDegrees
        } else {
            let octaves = log2(magnitude / sweepKneeCents)
            let fullOctaves = log2(fullScaleCents / sweepKneeCents)
            degrees =
                sweepKneeDegrees
                + octaves / fullOctaves * (fullScaleDegrees - sweepKneeDegrees)
        }
        let sweep = (clamped < 0 ? -1.0 : 1.0) * degrees

        let beyondInTune = max(0, abs(clamped) - inTuneCents)
        let thicknessRange = fullScaleCents - inTuneCents
        let thickness = thicknessRange > 0 ? beyondInTune / thicknessRange : 0

        return Arc(sweepDegrees: sweep, thickness: thickness)
    }

    /// One mark on the arc's scale.
    public struct Tick: Equatable, Sendable {
        /// The cent offset this mark sits at; negative is flat.
        public let cents: Double
        /// Where it sits on the dial, in signed degrees from vertical.
        public let degrees: Double
        /// Marks at or beyond the in-tune band (and at full scale) are drawn
        /// longer; the two inside it stay small — within the band the only
        /// value that matters is the needle's own zero.
        public let isMajor: Bool

        public init(cents: Double, degrees: Double, isMajor: Bool) {
            self.cents = cents
            self.degrees = degrees
            self.isMajor = isMajor
        }
    }

    /// Marks along the arc, so its sweep can be read as a quantity rather than
    /// just "more" or "less".
    ///
    /// Deliberately the same thresholds as the light strip below it: two scales
    /// on one screen disagreeing about where 8¢ sits would be worse than no
    /// scale at all. Zero is omitted — the needle already marks it.
    public static var ticks: [Tick] {
        let magnitudes = lightThresholds + [fullScaleCents]
        return magnitudes.flatMap { magnitude -> [Tick] in
            // Through the same mapping as the readings, or an 8¢ tick and
            // an 8¢ needle would disagree about where 8¢ is.
            let degrees = arc(forCents: magnitude).sweepDegrees
            let major = magnitude == fullScaleCents || magnitude >= inTuneCents
            return [
                Tick(cents: -magnitude, degrees: -degrees, isMajor: major),
                Tick(cents: magnitude, degrees: degrees, isMajor: major),
            ]
        }
    }

    /// Cent thresholds for the light strip, from the centre outward.
    ///
    /// Roughly doubling each step: the ear's sensitivity to mistuning is
    /// proportional, so equal *ratios* of error are what deserve equal spacing
    /// on screen. A linear strip would spend most of its length on errors too
    /// large to care about precisely and give almost no resolution near zero,
    /// which is the only place tuning actually happens.
    public static let lightThresholds: [Double] = [2, 4, 8, 16, 32]

    /// Total lights in the strip: one centre, plus `lightThresholds` per side.
    public static var lightCount: Int { lightThresholds.count * 2 + 1 }

    /// Index of the centre light.
    public static var centerLightIndex: Int { lightThresholds.count }

    /// Which light the given offset lights up, indexed from the flat end.
    ///
    /// Returns the centre index when within the innermost threshold, so the
    /// centre light means "in tune" rather than "exactly zero" — a reading
    /// that never stops moving would otherwise never light it.
    public static func litLightIndex(forCents cents: Double) -> Int {
        guard cents.isFinite else { return centerLightIndex }
        let magnitude = abs(cents)
        var step = 0
        for threshold in lightThresholds where magnitude > threshold {
            step += 1
        }
        if step == 0 { return centerLightIndex }
        return cents < 0 ? centerLightIndex - step : centerLightIndex + step
    }

    /// How strongly a light should read, 0...1, given the current offset.
    ///
    /// The lit light is full strength and its immediate neighbours glow
    /// faintly, which keeps the strip from looking like it's jumping between
    /// discrete states as a note settles.
    public static func lightIntensity(index: Int, cents: Double) -> Double {
        let lit = litLightIndex(forCents: cents)
        switch abs(index - lit) {
        case 0: return 1
        case 1: return 0.25
        default: return 0
        }
    }

    /// Whether an offset counts as in tune.
    public static func isInTune(cents: Double) -> Bool {
        cents.isFinite && abs(cents) <= inTuneCents
    }
}
