import XCTest

@testable import NitpitchCore

final class NoteNamingTests: XCTestCase {
    /// Middle C through the octave above it, in each convention.
    private func octaveNames(_ naming: NoteNaming) -> [String] {
        (0..<12).map { Note(pitchClass: $0, octave: 4).name(in: naming) }
    }

    func testEveryConventionSpellsAllTwelvePitchClasses() {
        for naming in NoteNaming.allCases {
            let names = octaveNames(naming)
            XCTAssertEqual(names.count, 12, "\(naming) is missing pitch classes")
            XCTAssertEqual(Set(names).count, 12, "\(naming) reuses a spelling")
            XCTAssertFalse(names.contains(where: \.isEmpty), "\(naming) has a blank name")
        }
    }

    func testEnglishIsUnchangedFromTheDefault() {
        XCTAssertEqual(
            octaveNames(.english),
            ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"])
    }

    /// The whole reason German can't be a relabelling: B♮ is H, and the name
    /// `B` is taken by B♭. Getting this backwards is the classic bug.
    func testGermanUsesHForBNaturalAndBForBFlat() {
        let a = Note(pitchClass: 9, octave: 4)
        let bFlat = Note(pitchClass: 10, octave: 4)
        let bNatural = Note(pitchClass: 11, octave: 4)
        XCTAssertEqual(a.name(in: .german), "A")
        XCTAssertEqual(bFlat.name(in: .german), "B")
        XCTAssertEqual(bNatural.name(in: .german), "H")
        // And B♮ must not be spelled "B", which would be B♭ to a German reader.
        XCTAssertNotEqual(bNatural.name(in: .german), "B")
    }

    func testGermanSpellsSharpsWithTheIsSuffix() {
        XCTAssertEqual(Note(pitchClass: 1, octave: 4).name(in: .german), "Cis")
        XCTAssertEqual(Note(pitchClass: 6, octave: 4).name(in: .german), "Fis")
        // No ♯ glyphs in the German row — the suffix is the spelling.
        XCTAssertFalse(octaveNames(.german).contains { $0.contains("♯") })
    }

    func testItalianUsesFixedDo() {
        XCTAssertEqual(Note(pitchClass: 0, octave: 4).name(in: .italian), "Do")
        XCTAssertEqual(Note(pitchClass: 9, octave: 4).name(in: .italian), "La")
        XCTAssertEqual(Note(pitchClass: 11, octave: 4).name(in: .italian), "Si")
    }

    /// イ is A, not the first name in the row — the iroha cycle starts from A
    /// while the pitch-class array starts from C.
    func testJapaneseMapsAToI() {
        XCTAssertEqual(Note(pitchClass: 9, octave: 4).name(in: .japanese), "イ")
        XCTAssertEqual(Note(pitchClass: 0, octave: 4).name(in: .japanese), "ハ")
        XCTAssertEqual(Note(pitchClass: 11, octave: 4).name(in: .japanese), "ロ")
        XCTAssertEqual(Note(pitchClass: 1, octave: 4).name(in: .japanese), "嬰ハ")
    }

    /// A=440 is the anchor of the whole app; every convention has to agree on
    /// which pitch class that is, whatever it calls it.
    func testConcertAIsPitchClass9InEveryConvention() {
        let a4 = PitchReading(frequency: 440).note
        XCTAssertEqual(a4.pitchClass, 9)
        XCTAssertEqual(a4.name(in: .english), "A")
        XCTAssertEqual(a4.name(in: .german), "A")
        XCTAssertEqual(a4.name(in: .italian), "La")
        XCTAssertEqual(a4.name(in: .japanese), "イ")
    }

    /// The reference-pitch label is built from this, so it must agree with
    /// what the readout would call the same note — otherwise one screen names
    /// concert A two different ways.
    func testConcertANameMatchesTheReadout() {
        let a4 = Note(pitchClass: 9, octave: 4)
        for naming in NoteNaming.allCases {
            XCTAssertEqual(
                naming.concertAName, a4.name(in: naming),
                "\(naming) labels the reference differently from the note")
        }
        XCTAssertEqual(NoteNaming.english.concertAName, "A")
        XCTAssertEqual(NoteNaming.german.concertAName, "A")
        XCTAssertEqual(NoteNaming.italian.concertAName, "La")
        XCTAssertEqual(NoteNaming.japanese.concertAName, "イ")
    }

    // MARK: - Readout label

    /// English needs no parenthetical — `A4 (A)` would be noise.
    func testEnglishShowsNoAlternate() {
        for pitchClass in 0..<12 {
            let label = Note(pitchClass: pitchClass, octave: 4).readoutLabel(in: .english)
            XCTAssertNil(label.alternate, "\(label.name) should not repeat itself")
        }
    }

    func testPrimaryIsAlwaysScientific() {
        let label = Note(pitchClass: 9, octave: 4).readoutLabel(in: .japanese)
        XCTAssertEqual(label.name, "A")
        XCTAssertEqual(label.octave, 4)
        XCTAssertEqual(label.alternate, "イ")
    }

    /// German is the case where the scientific letter is actively ambiguous: a
    /// bare `B4` reads as B-flat to a German musician. Both notes around that
    /// clash must carry the parenthetical that disambiguates them.
    func testGermanDisambiguatesBAndH() {
        let bFlat = Note(pitchClass: 10, octave: 4).readoutLabel(in: .german)
        let bNatural = Note(pitchClass: 11, octave: 4).readoutLabel(in: .german)
        XCTAssertEqual(bFlat.name, "A♯")
        XCTAssertEqual(bFlat.alternate, "B")
        XCTAssertEqual(bNatural.name, "B")
        XCTAssertEqual(bNatural.alternate, "H")
    }

    /// German naturals that match English (C, D, E, F, G, A) drop the
    /// parenthetical; only the spellings that differ keep it.
    func testGermanShowsAlternateOnlyWhereItDiffers() {
        XCTAssertNil(Note(pitchClass: 0, octave: 4).readoutLabel(in: .german).alternate)
        XCTAssertNil(Note(pitchClass: 9, octave: 4).readoutLabel(in: .german).alternate)
        XCTAssertEqual(Note(pitchClass: 1, octave: 4).readoutLabel(in: .german).alternate, "Cis")
    }

    func testOctaveTravelsWithThePrimaryLabel() {
        XCTAssertEqual(Note(midi: 69).readoutLabel(in: .italian).octave, 4)
        XCTAssertEqual(Note(midi: 57).readoutLabel(in: .italian).octave, 3)
        XCTAssertEqual(Note(midi: 81).readoutLabel(in: .italian).octave, 5)
        // The localized name never carries an octave — that's the whole point
        // of keeping the two labels apart.
        for note in [Note(midi: 57), Note(midi: 69), Note(midi: 81)] {
            XCTAssertEqual(note.readoutLabel(in: .italian).alternate, "La")
        }
    }

    func testFullNameAppendsTheOctave() {
        let note = Note(pitchClass: 1, octave: 5)
        XCTAssertEqual(note.fullName(in: .english), "C♯5")
        XCTAssertEqual(note.fullName(in: .german), "Cis5")
    }

    func testDefaultNameStillMeansEnglish() {
        let note = Note(pitchClass: 10, octave: 3)
        XCTAssertEqual(note.name, note.name(in: .english))
        XCTAssertEqual(note.fullName, note.fullName(in: .english))
    }

    /// VoiceOver reads the glyph poorly, so the spoken form spells it out.
    func testAccessibleNameSpeaksTheAccidental() {
        XCTAssertEqual(Note(pitchClass: 1, octave: 4).accessibleName(in: .english), "C sharp 4")
        XCTAssertEqual(Note(pitchClass: 0, octave: 4).accessibleName(in: .english), "C 4")
    }

    func testEveryConventionHasADistinctPickerLabel() {
        let labels = NoteNaming.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, NoteNaming.allCases.count)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    /// Persisted in defaults, so the raw values are a storage format and must
    /// not drift when cases are reordered or renamed.
    func testRawValuesAreStable() {
        XCTAssertEqual(NoteNaming.english.rawValue, "english")
        XCTAssertEqual(NoteNaming.german.rawValue, "german")
        XCTAssertEqual(NoteNaming.italian.rawValue, "italian")
        XCTAssertEqual(NoteNaming.japanese.rawValue, "japanese")
        XCTAssertEqual(NoteNaming(rawValue: "german"), .german)
        XCTAssertNil(NoteNaming(rawValue: "klingon"))
    }
}
