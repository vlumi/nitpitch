import XCTest

@testable import NitpitchCore

final class IntonationTests: XCTestCase {

    // MARK: - Classification: the parity claim

    func testClassifiesTheOpenString() {
        let g3 = 196.0
        let signal = tone(detuned(g3, cents: -7), count: signalLength(hops: 3))
        let sounded = frames(of: signal, target: g3, hops: 3).compactMap(\.note)
        XCTAssertFalse(sounded.isEmpty, "an open string must be heard")
        for (slot, cents) in sounded {
            XCTAssertEqual(slot, .open)
            XCTAssertEqual(cents, -7, accuracy: 1)
        }
    }

    /// The fretted 12th (or the fingered octave): partials at 2f, 4f, 6f —
    /// exclusively even slots of the open target — and its cents measured
    /// against 2f, on the same scale the open string uses against f.
    func testClassifiesTheOctave() {
        let g3 = 196.0
        let signal = tone(
            detuned(2 * g3, cents: 6), count: signalLength(hops: 3),
            harmonics: [1.0, 0.6, 0.4])
        let sounded = frames(of: signal, target: g3, hops: 3).compactMap(\.note)
        XCTAssertFalse(sounded.isEmpty, "the octave must be heard")
        for (slot, cents) in sounded {
            XCTAssertEqual(slot, .octave)
            XCTAssertEqual(cents, 6, accuracy: 1)
        }
    }

    /// A phone microphone rolls off a bass low E's fundamental — the note
    /// arrives with orders 2...6 and nothing at f. Order 3 is odd evidence,
    /// so parity still says open; a missing fundamental must never read as
    /// a fretted octave.
    func testRolledOffFundamentalIsStillTheOpenString() {
        let e2 = 82.4
        let signal = tone(
            detuned(e2, cents: 4), count: signalLength(hops: 3),
            harmonics: [0.0, 1.0, 0.8, 0.5, 0.3, 0.2])
        let sounded = frames(of: signal, target: e2, hops: 3).compactMap(\.note)
        XCTAssertFalse(sounded.isEmpty)
        for (slot, cents) in sounded {
            XCTAssertEqual(slot, .open)
            XCTAssertEqual(cents, 4, accuracy: 1)
        }
    }

    /// At a hot input gain the OTHER strings' leftover rings rise out of
    /// the floor — and on a guitar they land in the measured string's ODD
    /// slots (an A string's 4th harmonic is the D string's 3rd slot, a low
    /// E's 3rd is the B string's 1st). One faint ring partial must not
    /// flip the octave's parity claim — dominance decides, not purity
    /// (field-found: with the input volume up, every octave read as the
    /// open string — "another string" on the low strings, nothing at all
    /// on the high ones; turning the volume down "fixed" it by drowning
    /// the rings in the floor).
    func testANeighbourRingDoesNotFlipTheOctaveClaim() {
        let d3 = 146.83
        let octave = tone(detuned(2 * d3, cents: 4), count: signalLength(hops: 4))
        let ring = tone(110, count: signalLength(hops: 4))  // guitar A: h4 in D's slot 3
        let signal = zip(octave, ring).map { $0 + 0.25 * $1 }
        let sounded = frames(of: signal, target: d3, hops: 4).compactMap(\.note)
        XCTAssertFalse(sounded.isEmpty)
        for (slot, cents) in sounded {
            XCTAssertEqual(slot, .octave, "the ring is a sliver; the octave is the note")
            XCTAssertEqual(cents, 4, accuracy: 1.5)
        }
    }

    /// Fretting the 12th stops the OPEN string instantly — but the other
    /// strings ring on, so the window never goes RMS-quiet. The string
    /// itself going unreadable for a few frames is the gap that marks a
    /// fresh attack (field-found at a hot input gain: G/B/D's 12th frets
    /// never registered, and E's unclaimed octave walked the screen to the
    /// D string whose band it sits in).
    func testAFreshAttackIsSeenThroughARingingNeighbour() {
        let d3 = 146.83
        let analyzer = IntonationAnalyzer(
            sampleRate: sampleRate, target: d3, tuning: .default)
        analyzer.setActive(true)

        let phase = 20480
        var signal: [Float] = []
        signal += tone(d3, count: phase)
        signal += [Float](repeating: 0, count: 16384)
        signal += tone(detuned(2 * d3, cents: 4), count: phase)
        signal += [Float](repeating: 0, count: Detection.windowSize)
        // A neighbour rings through EVERYTHING — gap included: the guitar A,
        // whose 4th harmonic also sits in D's odd slot 3.
        let ring = tone(110, count: signal.count)
        signal = zip(signal, ring).map { $0 + 0.25 * $1 }

        var capture = IntonationCapture()
        var sawOctave = false
        var hop = 0
        while (hop * Detection.hopSize + Detection.windowSize) <= signal.count {
            let start = hop * Detection.hopSize
            let window = Array(signal[start..<(start + Detection.windowSize)])
            if let frame = analyzer.analyze(window) {
                capture.ingest(frame)
                if case .note(.octave, _, _) = frame.sounding { sawOctave = true }
            }
            hop += 1
        }

        XCTAssertTrue(sawOctave, "the string went quiet even though the room didn't")
        XCTAssertEqual(capture.delta ?? .nan, 4, accuracy: 1.5, "the verdict registers")
    }

    /// KNOWN LIMITATION, deliberately not guarded: on a guitar the low E's
    /// harmonics sit two cents from EVERY slot of the B string (E2 × 3 =
    /// B3 + 2¢), so a ringing low E can impersonate the open B outright —
    /// same anchor, same agreement, every gate passed. AGENTS.md records
    /// the same coincidence for the grid's collision set.
    ///
    /// A resting-slot snapshot ("judge what the note ADDED") was built for
    /// this and REVERTED: the check's two notes share one target's slots by
    /// construction — that IS the parity design — so subtracting a resting
    /// baseline subtracts the octave from itself, and the 12th fret stopped
    /// registering at all (see `IntonationPluckTests`, the case that
    /// matters). Mute or damp the neighbours while checking intonation;
    /// the capture's consensus rules mean a polluted sample costs one
    /// re-play, not a reset.
    ///
    /// Left as a test that documents the limit rather than asserts a fix:
    /// if a future round finds a discriminator that doesn't fight parity,
    /// this is the scenario it has to beat.

    /// The fresh-attack rule's two sides, pinned against the constant that
    /// has already been wrong in the field once (five frames, ~230 ms —
    /// slower than a fret-and-pluck, so most 12th frets were dismissed as
    /// the open note's tail).
    ///
    /// NOT expressed as "exactly N quiet frames": the estimator drops its
    /// phase pair on every silent window, so the first window after any
    /// silence cannot be measured and counts as quiet too — a caller can
    /// feed two silences and the rule will have counted three. What IS
    /// testable, and what the player cares about: a tail that follows the
    /// note with NO gap stays the open string, and the same spectrum after
    /// a hand-sized gap is the octave. If the constant creeps up toward the
    /// old five frames, the short-gap case starts failing.
    func testATailWithoutAGapIsOpenAndWithOneIsTheOctave() {
        let d3 = 146.832
        let evenOnly: [Double] = [0, 1.0, 0, 0.5, 0, 0.25]

        func lastSlot(gapHops: Int) -> IntonationSlot? {
            let analyzer = IntonationAnalyzer(
                sampleRate: sampleRate, target: d3, tuning: .default)
            analyzer.setActive(true)
            var signal = tone(d3, count: signalLength(hops: 5))
            if gapHops > 0 {
                signal += [Float](repeating: 0, count: gapHops * Detection.hopSize)
            }
            signal += tone(d3, count: signalLength(hops: 5), harmonics: evenOnly)
            var last: IntonationSlot?
            var hop = 0
            while hop * Detection.hopSize + Detection.windowSize <= signal.count {
                let start = hop * Detection.hopSize
                if let frame = analyzer.analyze(
                    Array(signal[start..<(start + Detection.windowSize)])),
                    case .note(let slot, _, _) = frame.sounding
                {
                    last = slot
                }
                hop += 1
            }
            return last
        }

        XCTAssertEqual(
            lastSlot(gapHops: 0), .open,
            "an even-only tail continuing the note IS the note, dying")
        XCTAssertEqual(
            lastSlot(gapHops: 3), .octave,
            "the same spectrum after a hand-sized gap is a fresh attack")
    }

    func testSilenceSoundsNothing() {
        let silence = [Float](repeating: 0, count: signalLength(hops: 2))
        for frame in frames(of: silence, target: 196, hops: 2) {
            XCTAssertEqual(frame.sounding, .nothing)
        }
    }

    func testInactiveAnswersNil() {
        let analyzer = IntonationAnalyzer(sampleRate: sampleRate, target: 196)
        let window = tone(196, count: Detection.windowSize)
        XCTAssertNil(analyzer.analyze(window))
    }

    /// The decay-tail rule, on a bass D2's full story: a plucked open
    /// string sheds its odd partials first, so its tail reads even-only —
    /// the octave's fingerprint on a note that isn't one (field-found: the
    /// delta flashed at the end of every open pluck). A direct open→even
    /// transition with NO silence between is the same note dying and stays
    /// .open; the SAME spectrum arriving after a real gap is a fresh attack
    /// and is the octave. The capture then registers the D2 delta end to
    /// end — the scenario the wrist couldn't complete.
    func testADecayingOpenIsNotAnOctaveButAFreshAttackIs() {
        let d2 = Instrument.bassGuitar.notes[2].frequency()
        let analyzer = IntonationAnalyzer(
            sampleRate: sampleRate, target: d2, tuning: .default)
        analyzer.setActive(true)

        let evenOnly: [Double] = [0, 1.0, 0, 0.5, 0, 0.25]
        let phase = 20480  // ten hops per phase
        var signal: [Float] = []
        // Both phases decay, as a plucked bass string does: the open pluck
        // fading, then its even-only tail fading further.
        signal += tone(d2, count: phase, decaySeconds: 1.5)
        signal += tone(
            d2, count: phase, harmonics: evenOnly, decaySeconds: 1.2, peakLevel: 0.35)
        signal += [Float](repeating: 0, count: 16384)  // damp: a real gap
        signal += tone(detuned(2 * d2, cents: 4), count: phase)  // the 12th
        signal += [Float](repeating: 0, count: Detection.windowSize)

        var capture = IntonationCapture()
        var slots: [Int: IntonationSlot] = [:]
        var hop = 0
        while (hop * Detection.hopSize + Detection.windowSize) <= signal.count {
            let start = hop * Detection.hopSize
            let window = Array(signal[start..<(start + Detection.windowSize)])
            if let frame = analyzer.analyze(window) {
                capture.ingest(frame)
                if case .note(let slot, _, _) = frame.sounding {
                    slots[hop] = slot
                }
            }
            hop += 1
        }

        // Interior hops of each phase (boundaries hold mixed windows).
        for hop in 2...7 {
            XCTAssertEqual(slots[hop], .open, "open phase, hop \(hop)")
        }
        for hop in 12...17 {
            XCTAssertEqual(
                slots[hop], .open,
                "the decaying tail must stay the open string, hop \(hop)")
        }
        let octaveHops = (29...36).compactMap { slots[$0] }
        XCTAssertTrue(
            octaveHops.contains(.octave),
            "after a real gap the same spectrum IS the octave")
        XCTAssertFalse(
            slots.filter { $0.key < 26 }.values.contains(.octave),
            "no octave claims before the gap")

        XCTAssertEqual(capture.delta ?? .nan, 4, accuracy: 1, "the D2 verdict registers")
    }

    /// The damp between two notes is judged RELATIVELY: at a hot input
    /// gain the interface's noise floor alone exceeds any absolute silence
    /// threshold, and the fresh-attack rule would never see a gap — every
    /// octave read as the open's decay tail, intonation dead (field-found:
    /// raising the Mac input volume killed the panel). Same story as the
    /// decay test above, but the "silent" gap hums at four times the
    /// absolute gate — and the octave must still register.
    func testADampIsADampOverANoisyFloor() {
        let d2 = Instrument.bassGuitar.notes[2].frequency()
        let analyzer = IntonationAnalyzer(
            sampleRate: sampleRate, target: d2, tuning: .default)
        analyzer.setActive(true)

        let phase = 20480
        var signal: [Float] = []
        signal += tone(d2, count: phase)
        // The damp: only mains hum remains — rms ~0.004, four times the
        // absolute silence gate, yet ~39 dB below the played tone.
        let hum = (0..<16384).map { i in
            Float(0.0057 * sin(2 * .pi * 60 * Double(i) / sampleRate))
        }
        signal += hum
        signal += tone(detuned(2 * d2, cents: 4), count: phase)
        signal += [Float](repeating: 0, count: Detection.windowSize)

        var capture = IntonationCapture()
        var sawOctave = false
        var hop = 0
        while (hop * Detection.hopSize + Detection.windowSize) <= signal.count {
            let start = hop * Detection.hopSize
            let window = Array(signal[start..<(start + Detection.windowSize)])
            if let frame = analyzer.analyze(window) {
                capture.ingest(frame)
                if case .note(.octave, _, _) = frame.sounding { sawOctave = true }
            }
            hop += 1
        }

        XCTAssertTrue(sawOctave, "the gap was a damp, hum or not")
        XCTAssertEqual(capture.open ?? .nan, 0, accuracy: 1, "the open string recorded")
        XCTAssertEqual(capture.octave ?? .nan, 4, accuracy: 1, "and so did the octave")
        XCTAssertEqual(capture.delta ?? .nan, 4, accuracy: 1, "the verdict registers")
    }

}
