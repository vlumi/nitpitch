import Foundation

/// Which convention note names are spelled in.
///
/// These are not translations of each other. German renames one natural note
/// (B♮ is `H`, and plain `B` means B♭), Italian is fixed-do solfège, and
/// Japanese uses the iroha syllables — so each system needs its own spelling
/// of both the naturals and the accidentals, not a lookup table over English.
public enum NoteNaming: String, CaseIterable, Codable, Sendable {
    /// C D E F G A B — English-speaking convention.
    case english
    /// C D E F G A H, with B meaning B♭ — German and much of central/northern
    /// Europe, and the notation most orchestral parts are printed in there.
    case german
    /// Do Re Mi Fa Sol La Si — fixed do, as used in Italy, France, and Spain.
    case italian
    /// ハニホヘトイロ — the Japanese iroha names, where イ is A.
    case japanese

    /// Untranslated label for the picker: each convention is named in its own
    /// terms, so the list reads the same regardless of app language.
    public var label: String {
        switch self {
        case .english: return "A B C"
        case .german: return "A H C"
        case .italian: return "Do Re Mi"
        case .japanese: return "イロハ"
        }
    }

    /// Spelling for each of the twelve pitch classes, starting at C.
    ///
    /// Sharps throughout rather than flats, with one deliberate exception: the
    /// German row spells pitch class 10 as `B`, because that *is* the German
    /// name for B♭ and writing `Ais` there would be the unidiomatic choice.
    var names: [String] {
        switch self {
        case .english:
            return ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        case .german:
            // Cis/Dis/Fis/Gis are the spoken and written forms; H is B natural.
            return ["C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "B", "H"]
        case .italian:
            return [
                "Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si",
            ]
        case .japanese:
            // 嬰 (ei) prefixes a sharpened note: 嬰ハ is C♯.
            return [
                "ハ", "嬰ハ", "ニ", "嬰ニ", "ホ", "ヘ", "嬰ヘ", "ト", "嬰ト", "イ", "嬰イ", "ロ",
            ]
        }
    }

    /// Spoken/accessible form, for VoiceOver — "C sharp" reads better than the
    /// glyph, which some voices skip entirely.
    func accessibleName(pitchClass: Int, octave: Int) -> String {
        let base = names[pitchClass]
        let spoken = base.replacingOccurrences(of: "♯", with: " sharp")
        return "\(spoken) \(octave)"
    }

    /// What to call concert A in this convention.
    ///
    /// The reference pitch is defined as *this note* at some frequency, so the
    /// label has to follow the notation setting — showing "A=442" beside a
    /// readout spelling notes as `La` or `イ` names the same pitch two ways.
    public var concertAName: String { names[Self.concertAPitchClass] }

    /// A is pitch class 9; the naming tables start at C.
    static let concertAPitchClass = 9
}
