import Foundation

/// The reference pitch A4 is tuned against, in hertz.
///
/// 440 is the ISO standard; European orchestras commonly sit at 442 or 443, and
/// baroque ensembles at 415. The whole app derives note names and cent offsets
/// from this one value, so changing it retunes everything consistently.
public struct ReferencePitch: Equatable, Hashable, Codable, Sendable {
    public static let standard = ReferencePitch(hz: 440)

    /// Range offered in the UI. Below 390 / above 466 the nearest-note mapping
    /// starts to mean something different to the player than "my A is flat".
    public static let range: ClosedRange<Double> = 390...466

    public let hz: Double

    public init(hz: Double) {
        self.hz = hz.clamped(to: Self.range)
    }
}

/// A pitch class plus octave, in scientific pitch notation (A4 = 440 Hz).
public struct Note: Equatable, Hashable, Sendable {
    /// Semitone within the octave, 0 = C.
    public let pitchClass: Int
    /// Scientific octave number: C4 is middle C, A4 the reference.
    public let octave: Int

    public init(pitchClass: Int, octave: Int) {
        self.pitchClass = pitchClass
        self.octave = octave
    }

    /// MIDI note number — the canonical integer form. A4 = 69.
    public var midi: Int { (octave + 1) * 12 + pitchClass }

    public init(midi: Int) {
        // Swift's % is remainder, not modulo: it returns negative values for
        // negative operands, which would give a nonsense pitch class below C-1.
        self.pitchClass = ((midi % 12) + 12) % 12
        self.octave = Int((Double(midi) / 12.0).rounded(.down)) - 1
    }

    /// Sharp-spelled name without the octave, e.g. "A", "C♯".
    public var name: String { Self.sharpNames[pitchClass] }

    /// Name with octave, e.g. "A4", "C♯5".
    public var fullName: String { "\(name)\(octave)" }

    /// The note's own frequency under a given reference.
    public func frequency(reference: ReferencePitch = .standard) -> Double {
        reference.hz * pow(2, Double(midi - 69) / 12)
    }

    /// Sharps rather than flats throughout: a tuner shows one spelling, and
    /// sharps are the convention on the instruments this targets. (Flat
    /// spelling would need key context the app doesn't have.)
    static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
}

/// A measured frequency resolved against the chromatic scale: which note it is,
/// and how far off it sits in cents.
public struct PitchReading: Equatable, Sendable {
    /// The measured fundamental, in hertz.
    public let frequency: Double
    /// The nearest chromatic note.
    public let note: Note
    /// Signed distance from that note, in cents. Negative = flat, positive =
    /// sharp. Always within ±50 — beyond that a different note is nearer.
    public let cents: Double

    public init(frequency: Double, reference: ReferencePitch = .standard) {
        self.frequency = frequency
        // Semitones from A4, as a real number; rounding gives the nearest note
        // and the remainder is the cent offset.
        let semitonesFromA4 = 12 * log2(frequency / reference.hz)
        let nearest = semitonesFromA4.rounded()
        self.note = Note(midi: Int(nearest) + 69)
        self.cents = (semitonesFromA4 - nearest) * 100
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
