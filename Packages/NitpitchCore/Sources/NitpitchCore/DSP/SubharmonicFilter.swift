import Foundation

/// Decides which of several per-string detections are real.
///
/// With one detector per string, each runs the same NSDF over the same
/// full-spectrum signal — a narrow band restricts which *lags* are searched, it
/// does not filter the audio. So every detector sees every string, and one
/// whose band happens to contain a subharmonic of what's actually playing finds
/// it at full clarity. Playing violin A4 makes the G3 detector report 220.0 Hz
/// at clarity 1.000: a real, perfectly periodic signal, genuinely inside G's
/// band, 200¢ from G. No clarity threshold rejects it, because nothing about it
/// is unclear; no band width rejects it, because it's where a slack G would be.
///
/// It can only be recognized by comparing the detectors against *each other*.
/// A subharmonic's frequency is an integer division of the real note's — that's
/// what makes it a subharmonic — so when one reading divides another, the
/// higher one is the fundamental and the lower is its shadow.
public enum SubharmonicFilter {
    /// One string's detection, as handed to the filter.
    public struct Candidate: Equatable, Sendable {
        /// Which string this came from, so the caller can match results back.
        public let id: Int
        public let frequency: Double

        public init(id: Int, frequency: Double) {
            self.id = id
            self.frequency = frequency
        }
    }

    /// How far from an exact integer ratio still counts as a subharmonic.
    ///
    /// Generous at 35¢: a real subharmonic lands within a cent or two, and the
    /// nearest thing that *isn't* one is a semitone (100¢) away, so there's a
    /// wide gap to sit in. Being generous costs nothing and catches a slightly
    /// mistuned string whose shadow lands a few cents off the exact ratio.
    public static let toleranceCents = 35.0

    /// The candidates that aren't shadows of another candidate.
    ///
    /// Keeps the highest of any chain: with A4 sounding, G3's 220 Hz divides
    /// A4's 440 Hz, so G3 goes and A4 stays. Order and ids are preserved.
    ///
    /// Note the rule is *not* "drop anything far from its target". Guitar's E2
    /// and E4 are exactly two octaves apart, so playing the high E makes the E2
    /// detector read −0¢ — a shadow that looks perfectly in tune. Distance from
    /// target can't tell those apart; the ratio between readings can.
    public static func real(among candidates: [Candidate]) -> [Candidate] {
        candidates.filter { candidate in
            !candidates.contains { other in
                other.id != candidate.id && divides(candidate.frequency, into: other.frequency)
            }
        }
    }

    /// Whether `lower` is `higher` divided by a whole number ≥ 2 — that is,
    /// whether a signal at `higher` would also look periodic at `lower`.
    private static func divides(_ lower: Double, into higher: Double) -> Bool {
        guard lower > 0, higher > lower else { return false }
        let ratio = higher / lower
        let nearest = ratio.rounded()
        guard nearest >= 2 else { return false }
        return abs(PitchMath.cents(from: nearest, to: ratio)) < toleranceCents
    }
}
