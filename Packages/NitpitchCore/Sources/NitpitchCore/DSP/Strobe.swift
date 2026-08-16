import Foundation

/// The strobe's arithmetic: tuning error rendered as MOTION, not position.
///
/// A needle at +0.3¢ is indistinguishable from a needle at zero — but a
/// pattern crawling slowly rightward is unmistakable, because the eye
/// detects velocity far better than displacement and integrates it over
/// time. That's how hardware strobes reach their famous ~0.1¢: precision
/// comes from watching for a second, not from any single estimate.
///
/// The software equivalent is an integrator over readings the app already
/// has: convert the current cents error to hertz against the (tempered)
/// target, accumulate phase, and let a segmented band scroll by it. One
/// full revolution = one hertz-second of accumulated error, so a violin A
/// one cent sharp (+0.25 Hz) crawls a quarter revolution per second.
public struct StrobeIntegrator: Equatable, Sendable {
    /// Accumulated phase in revolutions, wrapped to 0..<1 — the renderer
    /// multiplies by its segment pitch.
    public private(set) var phase: Double = 0

    public init() {}

    /// The frequency error a cents offset means at a given target — the
    /// strobe's velocity, in revolutions (= hertz) per second.
    public static func hzError(cents: Double, targetHz: Double) -> Double {
        PitchMath.hzError(cents: cents, targetHz: targetHz)
    }

    /// Advance by one reading's worth of time.
    public mutating func advance(cents: Double, targetHz: Double, dt: Double) {
        let wrapped = (phase + Self.hzError(cents: cents, targetHz: targetHz) * dt)
            .truncatingRemainder(dividingBy: 1)
        phase = wrapped < 0 ? wrapped + 1 : wrapped
    }

    public mutating func reset() {
        phase = 0
    }
}
