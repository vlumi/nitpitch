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

    // MARK: - Stepping

    func testSteppingMovesOneHertz() {
        let a440 = ReferencePitch(hz: 440)
        XCTAssertEqual(a440.raised().hz, 441)
        XCTAssertEqual(a440.lowered().hz, 439)
    }

    func testSteppingIsReversible() {
        for hz in [415.0, 440, 442, 443] {
            let pitch = ReferencePitch(hz: hz)
            XCTAssertEqual(pitch.raised().lowered(), pitch)
            XCTAssertEqual(pitch.lowered().raised(), pitch)
        }
    }

    /// Stepping past an edge holds rather than wrapping or throwing — the
    /// button is disabled there, but the model must not depend on the UI.
    func testSteppingStopsAtTheBounds() {
        let top = ReferencePitch(hz: ReferencePitch.range.upperBound)
        let bottom = ReferencePitch(hz: ReferencePitch.range.lowerBound)
        XCTAssertEqual(top.raised(), top)
        XCTAssertEqual(bottom.lowered(), bottom)
    }

    func testCanStepReportsHeadroom() {
        let top = ReferencePitch(hz: ReferencePitch.range.upperBound)
        let bottom = ReferencePitch(hz: ReferencePitch.range.lowerBound)
        XCTAssertFalse(top.canRaise)
        XCTAssertTrue(top.canLower)
        XCTAssertTrue(bottom.canRaise)
        XCTAssertFalse(bottom.canLower)
    }

    /// Every step must land on a whole hertz, since the readout renders
    /// `Int(hz)` — a fractional value would display as a lie.
    func testSteppingStaysOnWholeHertz() {
        var pitch = ReferencePitch(hz: ReferencePitch.range.lowerBound)
        while pitch.canRaise {
            pitch = pitch.raised()
            XCTAssertEqual(pitch.hz, pitch.hz.rounded(), "landed on \(pitch.hz)")
        }
        XCTAssertEqual(pitch.hz, ReferencePitch.range.upperBound)
    }

    /// The common orchestral and baroque settings must all be reachable by
    /// stepping from the default.
    func testCommonPitchesAreReachable() {
        for target in [415.0, 432, 442, 443, 466] {
            var pitch = ReferencePitch.standard
            var steps = 0
            while pitch.hz != target && steps < 200 {
                pitch = pitch.hz < target ? pitch.raised() : pitch.lowered()
                steps += 1
            }
            XCTAssertEqual(pitch.hz, target, "could not reach A=\(target)")
        }
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

    // MARK: - Per-string bands

    /// The whole point of splitting at midpoints rather than a fixed width:
    /// a fixed ±N leaves dead zones wherever strings sit more than 2N apart,
    /// and a string slack enough to land in one lights nothing at all.
    func testStringBandsAreContiguousWithNoGapsOrOverlap() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            let bands = instrument.stringBands().sorted { $0.lowerBound < $1.lowerBound }
            for i in 1..<bands.count {
                XCTAssertEqual(
                    bands[i - 1].upperBound, bands[i].lowerBound, accuracy: 1e-6,
                    "\(instrument.name) has a gap or overlap between bands \(i - 1) and \(i)")
            }
        }
    }

    /// Each dial has to answer for its own string above all — if a string's
    /// own pitch fell outside its band, tuning it would be impossible.
    func testEachStringFallsInItsOwnBand() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            let bands = instrument.stringBands()
            for (note, band) in zip(instrument.notes, bands) {
                XCTAssertTrue(
                    band.contains(note.frequency()),
                    "\(instrument.name): \(note.fullName) is outside its own band")
            }
        }
    }

    /// Swept rather than spot-checked: anywhere in the instrument's range,
    /// exactly one dial should light. Two would be ambiguous, none would be
    /// a dead zone.
    func testEveryPitchInRangeBelongsToExactlyOneBand() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            let bands = instrument.stringBands()
            guard let low = bands.map(\.lowerBound).min(),
                let high = bands.map(\.upperBound).max()
            else { continue }
            // A deliberately awkward step, so the sweep doesn't land on the
            // boundaries it's meant to be probing between.
            var hz = low + 0.37
            while hz < high {
                let matches = bands.filter { $0.contains(hz) }.count
                XCTAssertEqual(
                    matches, 1,
                    "\(instrument.name): \(matches) bands claim \(hz) Hz")
                hz += 0.37
            }
        }
    }

    /// A newly fitted string starts far below pitch, so the outermost bands
    /// have to reach well past the strings themselves.
    func testOutermostBandsExtendBeyondTheirStrings() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            let bands = instrument.stringBands()
            let sorted = bands.sorted { $0.lowerBound < $1.lowerBound }
            guard let lowestString = instrument.strings.min(),
                let highestString = instrument.strings.max()
            else { continue }
            XCTAssertLessThan(
                sorted[0].lowerBound, Note(midi: lowestString).frequency(),
                "\(instrument.name) has no headroom below its lowest string")
            XCTAssertGreaterThan(
                sorted[sorted.count - 1].upperBound, Note(midi: highestString).frequency(),
                "\(instrument.name) has no headroom above its highest string")
        }
    }

    /// Bands come back parallel to `strings`, so a grid can zip them together.
    func testStringBandsMatchTheStringOrder() {
        for instrument in Instrument.all {
            XCTAssertEqual(instrument.stringBands().count, instrument.strings.count)
        }
        XCTAssertTrue(Instrument.chromatic.stringBands().isEmpty)
    }

    /// Midpoints are taken in MIDI space: pitch is logarithmic, so the mean of
    /// two frequencies sits sharp of the note halfway between them. Between
    /// A4 (440) and A5 (880) the true midpoint is A♯4/B♭4 at ~622 Hz, not 660.
    func testMidpointsAreMusicalNotArithmetic() {
        let octave = Instrument(id: "octave", name: "Octave", strings: [69, 81])
        // An octave apart, so the midpoint is 6 semitones out — past the
        // default cap. Lift it to isolate the thing under test.
        let bands = octave.stringBands(maxSemitones: 99)
        let boundary = bands[0].upperBound
        XCTAssertEqual(boundary, 440 * pow(2, 0.5), accuracy: 0.01)
        XCTAssertLessThan(boundary, 660, "an arithmetic midpoint would sit here")
    }

    /// The reference shifts every boundary with it, or a band would drift off
    /// the string it belongs to.
    func testStringBandsFollowTheReference() {
        let at440 = Instrument.violin.stringBands(reference: ReferencePitch(hz: 440))
        let at442 = Instrument.violin.stringBands(reference: ReferencePitch(hz: 442))
        for (a, b) in zip(at440, at442) {
            XCTAssertLessThan(a.lowerBound, b.lowerBound)
            XCTAssertLessThan(a.upperBound, b.upperBound)
        }
        for (note, band) in zip(Instrument.violin.notes, at442) {
            XCTAssertTrue(band.contains(note.frequency(reference: ReferencePitch(hz: 442))))
        }
    }

    /// The shipped default has to leave the midpoints alone, or the tiling
    /// invariants above would be testing a narrower thing than the app runs.
    func testDefaultCapDoesNotNarrowAnyBand() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            let capped = instrument.stringBands()
            let uncapped = instrument.stringBands(maxSemitones: 99)
            XCTAssertEqual(capped, uncapped, "\(instrument.name) is clipped at the default cap")
        }
    }

    /// Narrowing may open gaps — that's the knob's whole purpose — but it must
    /// never make two dials answer for the same pitch.
    func testNarrowingNeverCreatesOverlap() {
        for semitones in [0.5, 1.0, 2.0, 3.0] {
            for instrument in Instrument.all where !instrument.strings.isEmpty {
                let bands = instrument.stringBands(maxSemitones: semitones)
                    .sorted { $0.lowerBound < $1.lowerBound }
                for i in 1..<bands.count {
                    XCTAssertLessThanOrEqual(
                        bands[i - 1].upperBound, bands[i].lowerBound + 1e-9,
                        "\(instrument.name) overlaps at ±\(semitones)")
                }
            }
        }
    }

    /// However narrow, a string's own pitch stays in its own band — a cap that
    /// clipped past the target would make that string untunable.
    func testStringStaysInItsBandAtEveryCap() {
        for semitones in [0.5, 1.0, 2.0, 3.0] {
            for instrument in Instrument.all where !instrument.strings.isEmpty {
                let bands = instrument.stringBands(maxSemitones: semitones)
                for (note, band) in zip(instrument.notes, bands) {
                    XCTAssertTrue(
                        band.contains(note.frequency()),
                        "\(instrument.name): \(note.fullName) falls outside its own ±\(semitones)")
                }
            }
        }
    }

    // MARK: - Tunings

    /// Every catalog tuning must fit its own instrument — a wrong string
    /// count in the catalog would be unloadable by construction.
    func testKnownTuningsFitTheirInstrument() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            for tuning in instrument.knownTunings {
                XCTAssertEqual(
                    tuning.strings.count, instrument.strings.count,
                    "\(instrument.name): \(tuning.name ?? "?") has the wrong string count")
                XCTAssertNotNil(tuning.name, "catalog tunings are all named")
            }
            XCTAssertEqual(
                instrument.knownTunings.first?.strings, instrument.strings,
                "\(instrument.name): Standard must come first and match the template")
        }
    }

    /// Identity follows the values: pitches matching a catalog entry ARE that
    /// tuning, anything else is custom (nil).
    func testTuningIdentityFollowsTheValues() {
        let dropD = [38, 45, 50, 55, 59, 64]
        XCTAssertEqual(Instrument.guitar.knownTuning(matching: dropD)?.name, "Drop D")
        XCTAssertNil(Instrument.guitar.knownTuning(matching: [39, 45, 50, 55, 59, 64]))
        XCTAssertEqual(
            Instrument.guitar.knownTuning(matching: Instrument.guitar.strings)?.name,
            "Standard")
    }

    /// A tuning the catalog offers but the app couldn't hear or the stepper
    /// couldn't reach would be a standing contradiction — the bass drop D
    /// was exactly that until the floors were unified.
    func testEveryCatalogTuningIsDetectableEverywhere() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            for tuning in instrument.knownTunings {
                for midi in tuning.strings {
                    XCTAssertTrue(
                        Detection.fullBand.contains(Note(midi: midi).frequency()),
                        "\(instrument.name) \(tuning.name ?? "?"): MIDI \(midi) is outside the chromatic band"
                    )
                }
            }
        }
    }

    /// Half-step down is exactly that, string for string.
    func testHalfStepDownIsAUniformShift() {
        let halfStep = Instrument.guitar.knownTunings.first { $0.name == "Half-step down" }!
        XCTAssertEqual(halfStep.strings, Instrument.guitar.strings.map { $0 - 1 })
    }

    // MARK: - Picker grouping

    /// The picker renders `grouped`, so anything missing from it is an
    /// instrument the user simply cannot select.
    func testGroupingCoversEveryInstrumentExactlyOnce() {
        let grouped = Instrument.grouped.flatMap(\.instruments)
        XCTAssertEqual(grouped.count, Instrument.all.count)
        XCTAssertEqual(Set(grouped), Set(Instrument.all))
    }

    /// Within a family the order is high to low; that's the rule the section
    /// headings exist to make visible, so it has to actually hold.
    func testEachFamilyRunsHighToLow() {
        for (family, instruments) in Instrument.grouped {
            let tops = instruments.compactMap { $0.strings.max() }
            guard tops.count == instruments.count else { continue }
            XCTAssertEqual(
                tops, tops.sorted(by: >),
                "\(family.name) is not ordered high to low")
        }
    }

    /// The variants ship as templates rather than a string-count picker:
    /// their low strings are the very notes the detection floor was set for.
    func testVariantLowStringsSitOnTheDetectionFloor() {
        XCTAssertEqual(Instrument.bassGuitar5.notes.first?.fullName, "B0")
        XCTAssertEqual(Instrument.guitar8.notes.first?.fullName, "F♯1")
        for instrument in [Instrument.bassGuitar5, .guitar7, .guitar8] {
            for note in instrument.notes {
                XCTAssertTrue(Detection.fullBand.contains(note.frequency()))
            }
        }
    }

    /// Violin leads — it's the default and the app's reason for existing.
    func testViolinIsFirst() {
        XCTAssertEqual(Instrument.all.first, .violin)
        XCTAssertEqual(Instrument.grouped.first?.instruments.first, .violin)
    }

    /// The chooser is reached *from* the chromatic tuner, so offering
    /// chromatic there would be offering to navigate to where you already are.
    func testChoosableExcludesChromaticButKeepsEverythingElse() {
        let choosable = Instrument.choosable.flatMap(\.instruments)
        XCTAssertFalse(choosable.contains(.chromatic))
        XCTAssertEqual(Set(choosable), Set(Instrument.all).subtracting([.chromatic]))
        // Every instrument in it still has strings to show — that's what the
        // screen it opens is for.
        XCTAssertTrue(choosable.allSatisfy { !$0.strings.isEmpty })
    }

    func testChromaticIsTheOnlyStringlessInstrument() {
        let stringless = Instrument.all.filter(\.strings.isEmpty)
        XCTAssertEqual(stringless, [.chromatic])
    }
}
