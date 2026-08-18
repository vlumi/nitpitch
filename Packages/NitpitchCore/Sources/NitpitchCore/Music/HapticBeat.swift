import Foundation

/// The wrist's tuning vocabulary: tuning error rendered as TIMED taps — the
/// same physics the ear hears. A string off its target beats against it at
/// |f − f_target| Hz (A4 ten cents flat pulses ~2.5 times a second), so the
/// taps come at exactly that cadence, SILENCE inside the in-tune band. A
/// sounding double stop swaps to the PAIR's beat (`IntervalBeat`), slowing
/// and stopping exactly as the audible beats do. Pure policy, no WatchKit —
/// the platform driver owns the timer and the actuator.
///
/// The taps carry DISTANCE only, deliberately: the first design spoke
/// direction too (`.directionUp` while flat, `.directionDown` while sharp),
/// and the wrist test could not tell them apart instinctively — while the
/// glance at the arc gives direction anyway. One honest signal beats two
/// ambiguous ones.
public enum HapticBeat {
    /// One cadence: how often to tap.
    public struct Cue: Equatable, Sendable {
        public let ratePerSecond: Double

        public init(ratePerSecond: Double) {
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
        return Cue(ratePerSecond: min(rate, maxRatePerSecond))
    }

    /// A sounding pair: the PAIR's true beat rate, straight from the same
    /// resolution the interval chip displays.
    public static func cue(pair: IntervalBeat.Reading) -> Cue? {
        guard pair.beatHz >= stoppedHz else { return nil }
        return Cue(ratePerSecond: min(pair.beatHz, maxRatePerSecond))
    }
}
