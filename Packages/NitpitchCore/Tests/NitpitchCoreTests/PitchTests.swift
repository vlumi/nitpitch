import XCTest

@testable import NitpitchCore

final class PitchTests: XCTestCase {
    func testA4IsMidi69() {
        XCTAssertEqual(Note(midi: 69).fullName, "A4")
        XCTAssertEqual(Note(midi: 69).frequency(), 440, accuracy: 1e-9)
    }

    func testMiddleCIsC4() {
        XCTAssertEqual(Note(midi: 60).fullName, "C4")
    }

    func testViolinOpenStrings() {
        XCTAssertEqual(Instrument.violin.notes.map(\.fullName), ["G3", "D4", "A4", "E5"])
        // The canonical frequencies a violinist expects to see.
        let hz = Instrument.violin.notes.map { $0.frequency() }
        XCTAssertEqual(hz[0], 196.0, accuracy: 0.05)
        XCTAssertEqual(hz[1], 293.66, accuracy: 0.05)
        XCTAssertEqual(hz[2], 440.0, accuracy: 0.05)
        XCTAssertEqual(hz[3], 659.26, accuracy: 0.05)
    }

    func testBassLowEIsBelow42Hz() {
        // The hardest note the detector has to find; the band must include it.
        let low = Instrument.bassGuitar.notes[0]
        XCTAssertEqual(low.fullName, "E1")
        XCTAssertEqual(low.frequency(), 41.2, accuracy: 0.05)
        XCTAssertTrue(Detection.fullBand.contains(low.frequency()))
    }

    func testNegativeMidiDoesNotWrapPitchClass() {
        // Swift's % returns negatives; a naive implementation gives a pitch
        // class below C and an off-by-one octave here.
        XCTAssertEqual(Note(midi: 0).fullName, "C-1")
        XCTAssertEqual(Note(midi: 11).fullName, "B-1")
        XCTAssertEqual(Note(midi: 12).fullName, "C0")
    }

    func testExactPitchReadsZeroCents() {
        let reading = PitchReading(frequency: 440)
        XCTAssertEqual(reading.note.fullName, "A4")
        XCTAssertEqual(reading.cents, 0, accuracy: 1e-9)
    }

    func testFlatAndSharpSigns() {
        // A semitone is 100 cents; a quarter-tone flat should read about -50.
        let flat = PitchReading(frequency: 440 * pow(2, -0.25 / 12))
        XCTAssertEqual(flat.note.fullName, "A4")
        XCTAssertEqual(flat.cents, -25, accuracy: 0.01)

        let sharp = PitchReading(frequency: 440 * pow(2, 0.25 / 12))
        XCTAssertEqual(sharp.note.fullName, "A4")
        XCTAssertEqual(sharp.cents, 25, accuracy: 0.01)
    }

    func testCentsAlwaysWithinHalfSemitone() {
        // Sweep the violin range; the nearest note must always be within ±50.
        for i in 0..<2000 {
            let hz = 190.0 + Double(i) * 0.25
            XCTAssertLessThanOrEqual(abs(PitchReading(frequency: hz).cents), 50.000001)
        }
    }

    func testReferencePitchRetunesEverything() {
        // At A=442, a 440 Hz tone is no longer a perfect A4 — it reads flat by
        // about 8 cents. This is the setting European orchestras ask for.
        let reading = PitchReading(frequency: 440, reference: ReferencePitch(hz: 442))
        XCTAssertEqual(reading.note.fullName, "A4")
        XCTAssertEqual(reading.cents, -7.85, accuracy: 0.05)
    }

    func testReferencePitchClampsToOfferedRange() {
        XCTAssertEqual(ReferencePitch(hz: 100).hz, ReferencePitch.range.lowerBound)
        XCTAssertEqual(ReferencePitch(hz: 9000).hz, ReferencePitch.range.upperBound)
    }

    func testInstrumentBandCoversItsStrings() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            let band = instrument.band()
            for note in instrument.notes {
                XCTAssertTrue(
                    band.contains(note.frequency()),
                    "\(instrument.name) band excludes its own \(note.fullName)")
            }
        }
    }
}
