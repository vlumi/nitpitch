import Foundation

/// The package's fundamental pitch arithmetic, defined exactly once: what a
/// MIDI number sounds like, what a frequency ratio measures in cents, and
/// what a cents offset beats at. Everything else — targets, bands, spreads,
/// strobe velocity, the wrist's tap cadence — derives from these.
public enum PitchMath {
    /// A (possibly fractional) MIDI number's frequency under a reference.
    /// Fractional, because band boundaries fall between notes and demo
    /// voices carry cent offsets.
    public static func frequency(
        midi: Double, reference: ReferencePitch = .standard
    ) -> Double {
        reference.hz * pow(2, (midi - 69) / 12)
    }

    /// The signed distance from `target` up to `frequency`, in cents.
    public static func cents(from target: Double, to frequency: Double) -> Double {
        1200 * log2(frequency / target)
    }

    /// The frequency error a cents offset means at a target — the physical
    /// rate it beats against it, signed. The strobe scrolls by the sign;
    /// the wrist taps at the magnitude.
    public static func hzError(cents: Double, targetHz: Double) -> Double {
        targetHz * (pow(2, cents / 1200) - 1)
    }
}
