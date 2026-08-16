import Foundation

/// The interval between two sounding adjacent strings, in the ear's own
/// units: BEATS. In a fifth, the lower string's 3rd harmonic and the upper's
/// 2nd land at (nearly) the same frequency; off pure, those partials sit
/// |3·f_L − 2·f_U| hertz apart and their sum audibly pulses at exactly that
/// rate. A violinist tunes by making the pulsing stop — "3 beats/sec,
/// slowing" is what the ear does, and this is its display. Fourths are the
/// same physics one ratio over (4:3).
///
/// Derived from the two pitches rather than measured off the amplitude
/// envelope: `HarmonicEstimator` reads both notes of a double stop to
/// sub-cent accuracy — ~0.05 Hz of beat resolution — and its
/// skip-shared-partials rule means neither pitch is contaminated by the very
/// coincidence partial that beats. (An envelope method would also capture
/// string inharmonicity; it waits for the field to ask.)
public enum IntervalBeat {
    /// The interval class of a nominal adjacent-string gap — only the pure
    /// ratios the app tunes by. A guitar's G–B major third beats too, but
    /// fretted instruments tune to frets, and thirds stay out of scope.
    public enum Kind: Equatable, Sendable {
        case fifth
        case fourth

        /// Which harmonic of the LOWER string sits at the coincidence.
        public var lowerHarmonic: Int {
            switch self {
            case .fifth: return 3
            case .fourth: return 4
            }
        }

        /// Which harmonic of the UPPER string meets it there.
        public var upperHarmonic: Int {
            switch self {
            case .fifth: return 2
            case .fourth: return 3
            }
        }

        /// The beatless width, in cents.
        public var pureCents: Double {
            1200 * log2(Double(lowerHarmonic) / Double(upperHarmonic))
        }

        /// The interval a nominal semitone gap names, or nil when it isn't
        /// one the app tunes pure.
        public init?(semitones: Int) {
            switch semitones {
            case 7: self = .fifth
            case 5: self = .fourth
            default: return nil
            }
        }
    }

    /// One sounding pair, resolved.
    public struct Reading: Equatable, Sendable {
        /// The lower string's index; the pair is (lowerIndex, lowerIndex+1).
        public let lowerIndex: Int
        public let kind: Kind
        /// The pulse the ear hears, |m·f_L − n·f_U|, in hertz.
        public let beatHz: Double
        /// Signed width against PURE: positive = wide, negative = narrow.
        public let wideCents: Double
    }

    /// The first adjacent pair sounding together, resolved to its beats —
    /// or nil when no tunable pair is. Three strings at once would offer
    /// two pairs; the lowest wins, and a bow can't really do three anyway.
    public static func resolve(frequencies: [Double?], midis: [Int]) -> Reading? {
        guard frequencies.count == midis.count, midis.count >= 2 else { return nil }
        for index in 0..<(midis.count - 1) {
            guard let lower = frequencies[index], let upper = frequencies[index + 1],
                let kind = Kind(semitones: midis[index + 1] - midis[index])
            else { continue }
            let beat = abs(
                Double(kind.lowerHarmonic) * lower - Double(kind.upperHarmonic) * upper)
            let wide = PitchMath.cents(from: lower, to: upper) - kind.pureCents
            return Reading(
                lowerIndex: index, kind: kind, beatHz: beat, wideCents: wide)
        }
        return nil
    }

    /// What the beat SHOULD read once both strings sit on their targets —
    /// zero under pure temperament by construction, ~1 Hz for an
    /// equal-tempered fifth. The display aims here, not blindly at silence:
    /// equal temperament is deliberately not beatless, and pretending
    /// otherwise would tune the player away from their own targets.
    public static func targetBeatHz(
        kind: Kind, lowerTargetHz: Double, upperTargetHz: Double
    ) -> Double {
        abs(
            Double(kind.lowerHarmonic) * lowerTargetHz
                - Double(kind.upperHarmonic) * upperTargetHz)
    }
}
