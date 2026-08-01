import Foundation

/// Stabilizes the *display* without touching the detection.
///
/// Raw per-frame estimates are accurate but visibly jittery — vibrato, bow
/// noise, and normal string behaviour move the last cent or two continuously, and
/// a needle that twitches reads as "broken" even when it's right. So the
/// detector stays unsmoothed (its output is the truth, and the tests assert
/// against it) and the presentation layer smooths here.
///
/// Two stages, in order:
/// 1. **Median** over a short history — kills isolated outliers (a single frame
///    that landed on a harmonic) outright rather than averaging them in.
/// 2. **Exponential** — takes the remaining fine jitter off the needle.
///
/// Both operate in cents-from-a-reference rather than hertz, so the response is
/// uniform across the range: 2 Hz is a shrug at E5 and a wince at E1, but 5
/// cents is 5 cents everywhere.
public struct ReadingSmoother {
    /// Median window, in frames. 5 at ~21 fps is ~240 ms of history — enough to
    /// outvote a lone bad frame, short enough that a deliberate tuning change
    /// still shows up promptly.
    public static let medianWindow = 5

    /// Exponential weight for each new (post-median) sample. 0.35 settles in
    /// ~5 frames while still visibly tracking a peg turn.
    public static let smoothingFactor = 0.35

    /// A jump this large means a genuinely new note, not jitter — reset rather
    /// than sliding the needle across the dial. A semitone.
    public static let resetThresholdCents = 100.0

    private var history: [Double] = []
    private var smoothed: Double?

    public init() {}

    /// Feed one accepted reading; returns the value to display, in the same
    /// absolute-cents space as the input.
    public mutating func update(cents: Double) -> Double {
        if let last = smoothed, abs(cents - last) > Self.resetThresholdCents {
            // New note: drop the history so the old note's frames don't drag
            // the needle through the interval between them.
            history.removeAll(keepingCapacity: true)
            smoothed = nil
        }

        history.append(cents)
        if history.count > Self.medianWindow { history.removeFirst() }

        let median = history.sorted()[history.count / 2]
        let next = smoothed.map { $0 + Self.smoothingFactor * (median - $0) } ?? median
        smoothed = next
        return next
    }

    /// Forget everything — call when detection drops out, so the next note
    /// starts clean instead of easing over from the previous one.
    public mutating func reset() {
        history.removeAll(keepingCapacity: true)
        smoothed = nil
    }

    /// The current displayed value, or nil before the first reading.
    public var current: Double? { smoothed }
}
