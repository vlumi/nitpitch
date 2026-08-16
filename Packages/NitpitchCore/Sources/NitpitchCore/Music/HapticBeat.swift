import Foundation

/// The wrist's tuning vocabulary: tuning error rendered as TIMED taps — the
/// same physics the ear hears. A string off its target beats against it at
/// |f − f_target| Hz (A4 ten cents flat pulses ~2.5 times a second), so the
/// taps come at exactly that cadence: `.up` ("come up") while flat, `.down`
/// while sharp, SILENCE inside the in-tune band. A sounding double stop
/// swaps to the PAIR's beat (`IntervalBeat`), clicks slowing and stopping
/// exactly as the audible beats do. Pure policy, no WatchKit — the platform
/// driver owns the timer and the actuator.
public enum HapticBeat {
    /// Which preset haptic the driver plays per pulse.
    public enum Pattern: Equatable, Sendable {
        /// Flat — come up.
        case up
        /// Sharp — come down.
        case down
        /// A double stop's audible beat, rendered on the skin.
        case beat
    }

    /// One cadence: what to play, and how often.
    public struct Cue: Equatable, Sendable {
        public let pattern: Pattern
        public let ratePerSecond: Double

        public init(pattern: Pattern, ratePerSecond: Double) {
            self.pattern = pattern
            self.ratePerSecond = ratePerSecond
        }
    }

    /// Past ~8/s the skin feels roughness, not pulses — the interval chip's
    /// dot caps at the same rate for the same reason.
    public static let maxRatePerSecond: Double = 8

    /// Below this the beat has effectively stopped (the chip's "0/s" rule).
    static let stoppedHz = 0.05

    /// The focused string alone: its physical beat rate against the target,
    /// from the same smoothed cents the screen shows. In tune is silence —
    /// the band's edge is where the taps start.
    public static func cue(cents: Double, targetHz: Double) -> Cue? {
        guard cents.isFinite, targetHz > 0, !TuningDisplay.isInTune(cents: cents)
        else { return nil }
        let rate = abs(PitchMath.hzError(cents: cents, targetHz: targetHz))
        guard rate >= stoppedHz else { return nil }
        return Cue(
            pattern: cents < 0 ? .up : .down,
            ratePerSecond: min(rate, maxRatePerSecond))
    }

    /// A sounding pair: the PAIR's true beat rate, straight from the same
    /// resolution the interval chip displays.
    public static func cue(pair: IntervalBeat.Reading) -> Cue? {
        guard pair.beatHz >= stoppedHz else { return nil }
        return Cue(pattern: .beat, ratePerSecond: min(pair.beatHz, maxRatePerSecond))
    }
}
