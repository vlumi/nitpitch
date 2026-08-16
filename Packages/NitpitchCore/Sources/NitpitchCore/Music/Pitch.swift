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

    /// Adjustment granularity. Orchestras work in whole hertz — 440, 442, 443,
    /// baroque 415 — so finer steps would be false precision that only makes
    /// the control slower to use.
    public static let step: Double = 1

    public let hz: Double

    public init(hz: Double) {
        self.hz = hz.clamped(to: Self.range)
    }

    /// One step sharper, or unchanged at the top of the range.
    public func raised() -> ReferencePitch { ReferencePitch(hz: hz + Self.step) }

    /// One step flatter, or unchanged at the bottom of the range.
    public func lowered() -> ReferencePitch { ReferencePitch(hz: hz - Self.step) }

    /// Whether there's room to step further, for disabling the buttons.
    public var canRaise: Bool { hz < Self.range.upperBound }
    public var canLower: Bool { hz > Self.range.lowerBound }
}

/// A pitch class plus octave, in scientific pitch notation (A4 = 440 Hz).
///
/// Sharps rather than flats throughout: a tuner shows one spelling, and
/// sharps are the convention on the instruments this targets. (Flat spelling
/// would need key context the app doesn't have.) Per-convention spellings
/// live in `NoteNaming`.
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

    /// Name without the octave in the given convention, e.g. "C♯", "Cis", "嬰ハ".
    public func name(in naming: NoteNaming) -> String { naming.names[pitchClass] }

    /// Name with octave, e.g. "A4", "Cis5".
    public func fullName(in naming: NoteNaming) -> String { "\(name(in: naming))\(octave)" }

    /// Spoken form for VoiceOver, e.g. "C sharp 5".
    public func accessibleName(in naming: NoteNaming) -> String {
        naming.accessibleName(pitchClass: pitchClass, octave: octave)
    }

    /// How the readout labels this note: the scientific designator, plus the
    /// chosen convention's name when that differs.
    ///
    /// Rendered as `A4 (イ)` rather than `イ₄`. Appending the octave to a
    /// localized name produces a hybrid no native reader would write — German
    /// marks octaves by case and primes (`c'`), Japanese by 一点 prefixes, and
    /// both restructure the name rather than suffixing it. Kept apart, each
    /// label is correct on its own terms.
    ///
    /// **The two halves are international to different degrees.** The octave
    /// *number* is scientific pitch notation (C4 = middle C), which is used
    /// worldwide — MIDI and audio software everywhere speak it. The *letter*
    /// isn't part of that spec: SPN assumes A–G, so the primary label is
    /// really "English letter + SPN octave". That matters most for German,
    /// where a bare `B4` would read as B-flat; the parenthetical resolves it,
    /// since B♮ shows as `B4 (H)` and B♭ as `A♯4 (B)`. (Accidentals are the
    /// real glyph `♯`, U+266F, not the number sign.)
    ///
    /// The parenthetical is dropped when the convention agrees with English,
    /// since `A4 (A)` is noise.
    public func readoutLabel(in naming: NoteNaming) -> ReadoutLabel {
        let english = name(in: .english)
        let localized = name(in: naming)
        return ReadoutLabel(
            name: english, octave: octave,
            alternate: localized == english ? nil : localized)
    }

    /// The parts of the readout's note label, kept separate so the view can
    /// size and place each one.
    public struct ReadoutLabel: Equatable, Sendable {
        /// The English letter, which the octave number belongs to.
        public let name: String
        /// The scientific octave, rendered as a subscript.
        public let octave: Int
        /// The chosen convention's name, or nil when it matches English.
        public let alternate: String?

        public init(name: String, octave: Int, alternate: String?) {
            self.name = name
            self.octave = octave
            self.alternate = alternate
        }
    }

    /// Sharp-spelled English name, e.g. "A", "C♯".
    public var name: String { name(in: .english) }

    /// English name with octave, e.g. "A4", "C♯5".
    public var fullName: String { fullName(in: .english) }

    /// The note's own frequency under a given reference.
    public func frequency(reference: ReferencePitch = .standard) -> Double {
        PitchMath.frequency(midi: Double(midi), reference: reference)
    }
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

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
