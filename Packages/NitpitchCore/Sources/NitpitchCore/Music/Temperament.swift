import Foundation

/// How an instrument's open strings divide their intervals: the app's one
/// deliberate departure from `reference × 2^(semitones/12)`.
///
/// String players tune by ear to BEATLESS fifths — the pure 3:2 ratio,
/// 701.955 cents, not equal temperament's 700 — so a violin tuned to an
/// equal-tempered tuner gets every fifth two cents narrow and ends up ~4¢
/// disagreeing with itself by the G string. That's what `.pure` repairs. It
/// covers the double bass for free: a pure fourth (4:3, 498.045¢) is the
/// pure fifth inverted, and both fall out of the same arithmetic.
///
/// This applies to open-string TARGETS only, and only where the instrument's
/// construction doesn't forbid it: frets are equal temperament cast in
/// metal, so fretted instruments never see this — pure open strings would
/// disagree with every fretted note. The chromatic screen keeps naming
/// nearest equal-tempered notes (re-tempering all twelve needs a root, which
/// is a different feature), and the intonation layer is untouched by
/// construction — octaves are 2:1 in every temperament.
public enum Temperament: String, Codable, CaseIterable, Sendable {
    /// Every semitone 100¢ — the default, and all a fretted instrument can
    /// use.
    case equal
    /// Adjacent strings a pure 3:2 or 4:3 apart, anchored at the A string —
    /// the orchestra's procedure: A from the oboe, then beatless intervals
    /// outward.
    case pure

    /// 1200·log₂(3/2): the beatless fifth.
    public static let pureFifthCents = 1200 * log2(3.0 / 2.0)
    /// 1200·log₂(4/3): the beatless fourth — the fifth inverted.
    public static let pureFourthCents = 1200 * log2(4.0 / 3.0)

    /// Per-string cent offsets from equal temperament for these open strings
    /// (MIDI, low to high) — what the targets shift by.
    ///
    /// Anchored at the A string (the one every standard bowed tuning has;
    /// with several As, the one nearest A4 — a viola's A4 over a
    /// hypothetical A3). From the anchor outward, each adjacent pair whose
    /// nominal interval is a fifth or a fourth takes the pure ratio; any
    /// other interval steps equal-tempered, so an exotic custom tuning
    /// degrades gracefully instead of guessing. No A at all means no
    /// anchor and no offsets — silently equal, which is also what `.equal`
    /// always answers.
    public func offsets(for strings: [Int]) -> [Double] {
        guard self == .pure, !strings.isEmpty else {
            return Array(repeating: 0, count: strings.count)
        }
        // The A nearest the orchestra's A4, midi 69.
        let anchor = strings.indices
            .filter { strings[$0] % 12 == 9 }
            .min { abs(strings[$0] - 69) < abs(strings[$1] - 69) }
        guard let anchor else { return Array(repeating: 0, count: strings.count) }

        var offsets = Array(repeating: 0.0, count: strings.count)
        for index in stride(from: anchor + 1, to: strings.count, by: 1) {
            let step = strings[index] - strings[index - 1]
            offsets[index] = offsets[index - 1] + Self.pureExcess(forStep: step)
        }
        for index in stride(from: anchor - 1, through: 0, by: -1) {
            let step = strings[index + 1] - strings[index]
            offsets[index] = offsets[index + 1] - Self.pureExcess(forStep: step)
        }
        return offsets
    }

    /// How far a pure step exceeds its equal-tempered size, in cents —
    /// zero for anything that isn't a fifth or a fourth.
    private static func pureExcess(forStep semitones: Int) -> Double {
        switch semitones {
        case 7: return pureFifthCents - 700
        case 5: return pureFourthCents - 500
        default: return 0
        }
    }
}
