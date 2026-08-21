import XCTest

@testable import NitpitchCore

/// The intonation check rests on one physical claim — parity: an open string
/// always brings odd partials, a note an octave up sounds even slots only.
/// Verified the way the estimator itself is: synthesized waveforms, no audio
/// hardware. The capture's gating rules are pure state and tested as such.
final class IntonationTests: XCTestCase {
    private let sampleRate = 44100.0

    /// A harmonically rich tone the way a plucked string is.
    private func tone(
        _ hz: Double, count: Int,
        harmonics: [Double] = [0.3, 1.0, 0.8, 0.5, 0.3, 0.2]
    ) -> [Float] {
        let raw = (0..<count).map { i in
            let t = Double(i) / sampleRate
            var s = 0.0
            for (k, a) in harmonics.enumerated() {
                s += a * sin(2 * .pi * hz * Double(k + 1) * t)
            }
            return s
        }
        let peak = raw.map(abs).max() ?? 1
        return raw.map { Float($0 / max(peak, 1e-12) * 0.8) }
    }

    private func detuned(_ hz: Double, cents: Double) -> Double {
        hz * pow(2, cents / 1200)
    }

    /// Run a signal through an analyzer as `AudioInput` would deliver it:
    /// hop-consecutive windows, all frames collected.
    private func frames(
        of signal: [Float], target: Double, hops: Int
    ) -> [IntonationAnalyzer.Frame] {
        let analyzer = IntonationAnalyzer(
            sampleRate: sampleRate, target: target, tuning: .default)
        analyzer.setActive(true)
        return (0..<hops).compactMap { hop in
            let start = hop * Detection.hopSize
            return analyzer.analyze(Array(signal[start..<(start + Detection.windowSize)]))
        }
    }

    private func signalLength(hops: Int) -> Int {
        Detection.windowSize + hops * Detection.hopSize
    }

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
        signal += tone(d2, count: phase)
        signal += tone(d2, count: phase, harmonics: evenOnly)  // the tail
        signal += [Float](repeating: 0, count: 8192)  // damp: a real gap
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
        let octaveHops = (25...32).compactMap { slots[$0] }
        XCTAssertTrue(
            octaveHops.contains(.octave),
            "after a real gap the same spectrum IS the octave")
        XCTAssertFalse(
            slots.filter { $0.key < 22 }.values.contains(.octave),
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
        let hum = (0..<8192).map { i in
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
        XCTAssertEqual(capture.delta ?? .nan, 4, accuracy: 1, "the verdict registers")
    }

    /// The grid's plumbing: the bank's spectral results carry the parity
    /// fingerprint up from the estimator, so every string's consumer can
    /// recognize its own octave without a second detector.
    func testTheBankCarriesParityThroughItsResults() {
        let g3 = 196.0
        let bank = DetectorBank(
            sampleRate: sampleRate, targets: [g3], bands: [100...400], tuning: .default)

        let octave = tone(
            detuned(2 * g3, cents: 5), count: signalLength(hops: 3),
            harmonics: [1.0, 0.6, 0.4])
        var litFrames = 0
        for hop in 0..<3 {
            let start = hop * Detection.hopSize
            let results = bank.analyze(Array(octave[start..<(start + Detection.windowSize)]))
            if let result = results.first, result.frequency != nil {
                XCTAssertTrue(result.evenPartialsOnly, "the octave is even slots only")
                litFrames += 1
            }
        }
        XCTAssertGreaterThan(litFrames, 0, "the octave must be measured at all")

        bank.interrupted()
        let open = tone(detuned(g3, cents: -7), count: signalLength(hops: 3))
        litFrames = 0
        for hop in 0..<3 {
            let start = hop * Detection.hopSize
            let results = bank.analyze(Array(open[start..<(start + Detection.windowSize)]))
            if let result = results.first, result.frequency != nil {
                XCTAssertFalse(result.evenPartialsOnly, "an open string brings odd evidence")
                litFrames += 1
            }
        }
        XCTAssertGreaterThan(litFrames, 0)
    }

    /// The note above every band — a bass D string's 12th fret, higher than
    /// the top of the top string's band — surfaces through the sentinel,
    /// which otherwise exists only to kill subharmonic shadows. This is the
    /// grid's only sight of that octave: too high for any dial's band, too
    /// low for the spectral estimator's bins.
    func testTheBankSurfacesTheNoteAboveEveryBand() {
        let bass = Instrument.bassGuitar
        let targets = bass.notes.map { $0.frequency() }
        let bank = DetectorBank(
            sampleRate: sampleRate, targets: targets, bands: bass.stringBands(),
            tuning: DetectionTuning(engine: .mpm))
        let d12th = 2 * targets[2] * pow(2, 5.0 / 1200)
        let signal = tone(d12th, count: signalLength(hops: 3), harmonics: [1.0, 0.6, 0.4])
        var seen = false
        for hop in 0..<3 {
            let start = hop * Detection.hopSize
            let frame = bank.analyzeWithAbove(
                Array(signal[start..<(start + Detection.windowSize)]))
            if let above = frame.above?.frequency {
                XCTAssertEqual(1200 * log2(above / d12th), 0, accuracy: 10)
                seen = true
            }
        }
        XCTAssertTrue(seen, "the sentinel must surface the above-band note")
    }

    /// The guitar field case: B4 and E5 live above every band, so their
    /// only route is the sentinel — and on a guitar something is always
    /// ringing for spectral to read, so spectral wins nearly every frame.
    /// The sentinel must answer on those frames too, or the top strings'
    /// octaves starve on exactly the instruments where spectral is healthy.
    func testTheSentinelAnswersOnSpectralFramesToo() {
        let guitar = Instrument.guitar
        let targets = guitar.notes.map { $0.frequency() }
        let bank = DetectorBank(
            sampleRate: sampleRate, targets: targets, bands: guitar.stringBands(),
            tuning: .default)
        // A fretted B4 (the B string's 12th, +5¢) over the open G string
        // ringing quietly underneath — the mix a real guitar hands the mic.
        let b12th = 2 * targets[4] * pow(2, 5.0 / 1200)
        let fretted = tone(b12th, count: signalLength(hops: 4), harmonics: [1.0, 0.5, 0.25])
        let ringing = tone(targets[3], count: signalLength(hops: 4))
        let signal = zip(fretted, ringing).map { $0 * 0.9 + $1 * 0.25 }

        var claimed = false
        for hop in 0..<4 {
            let start = hop * Detection.hopSize
            let frame = bank.analyzeWithAbove(
                Array(signal[start..<(start + Detection.windowSize)]))
            if let above = frame.above?.frequency {
                XCTAssertEqual(1200 * log2(above / b12th), 0, accuracy: 12)
                claimed = true
            }
        }
        XCTAssertTrue(claimed, "the octave above every band must surface")
    }

    // MARK: - End to end: signal in, samples out

    func testAHeldOctaveReachesTheCapture() {
        let g3 = 196.0
        let hops = IntonationCapture.stableFrames + 3
        let signal = tone(
            detuned(2 * g3, cents: 9), count: signalLength(hops: hops),
            harmonics: [1.0, 0.6, 0.4])
        var capture = IntonationCapture()
        for frame in frames(of: signal, target: g3, hops: hops) {
            capture.ingest(frame)
        }
        XCTAssertEqual(capture.octave ?? .nan, 9, accuracy: 1)
    }
}

extension IntonationAnalyzer.Frame {
    /// The sounding note's parts, for terse assertions.
    fileprivate var note: (slot: IntonationSlot, cents: Double)? {
        guard case .note(let slot, let cents, _) = sounding else { return nil }
        return (slot, cents)
    }
}

/// The capture's gating rules, as arithmetic — pure state, no audio, so
/// every rule is a scripted frame sequence.
final class IntonationCaptureTests: XCTestCase {

    private func note(
        _ slot: IntonationSlot, _ cents: Double
    ) -> IntonationAnalyzer.Frame {
        IntonationAnalyzer.Frame(
            sounding: .note(slot: slot, cents: cents, clarity: 1), level: 0.5)
    }

    private var nothing: IntonationAnalyzer.Frame {
        IntonationAnalyzer.Frame(sounding: .nothing, level: 0)
    }

    func testAStableRunRecordsItsMedian() {
        var capture = IntonationCapture()
        for cents in [-2.0, -1.5, -2.5, -2.0, -1.8, -2.2] {
            capture.ingest(note(.open, cents))
        }
        XCTAssertEqual(capture.open ?? .nan, -2.0, accuracy: 0.11)
        XCTAssertNil(capture.octave)
    }

    func testAWobblingRunRecordsNothing() {
        var capture = IntonationCapture()
        for cents in [-2.0, 3.0, -1.0, 4.0, -3.0, 2.0] {
            capture.ingest(note(.open, cents))
        }
        XCTAssertNil(capture.open, "a spread past the window is a note still settling")
    }

    /// A decaying note hovers at the strength gate and flickers
    /// note/nothing — a brief dropout must not restart the clock.
    func testABriefDropoutDoesNotBreakARun() {
        var capture = IntonationCapture()
        for _ in 0..<5 { capture.ingest(note(.open, -2)) }
        for _ in 0..<IntonationCapture.quietGraceFrames { capture.ingest(nothing) }
        capture.ingest(note(.open, -2))
        XCTAssertEqual(capture.open ?? .nan, -2, accuracy: 0.01)
    }

    func testSustainedSilenceBreaksARun() {
        var capture = IntonationCapture()
        for _ in 0..<5 { capture.ingest(note(.open, -2)) }
        for _ in 0..<(IntonationCapture.quietGraceFrames + 1) { capture.ingest(nothing) }
        capture.ingest(note(.open, -2))
        XCTAssertNil(capture.open, "past the grace, the run starts over")
    }

    /// An outlier costs one extra frame of evidence, never a restart: the
    /// lock waits for `stableFrames` inliers around the run's median, and
    /// the recorded value is the median of the inliers alone.
    func testAnOutlierDelaysTheLockByOneFrameAndLeavesNoTrace() {
        var capture = IntonationCapture()
        for cents in [-2.0, -1.8, -2.2, 6.0, -2.0, -1.9] {
            capture.ingest(note(.open, cents))
        }
        XCTAssertNil(capture.open, "five inliers are not yet a consensus")
        capture.ingest(note(.open, -2.1))
        XCTAssertEqual(capture.open ?? .nan, -2.0, accuracy: 0.1)
    }

    /// A picked bass note: wobbly attack, wild frames scattered through a
    /// decaying pluck — the run collects evidence wherever it lands, and
    /// the outliers are discarded rather than given a veto.
    func testAScatteredPluckStillLocks() {
        var capture = IntonationCapture()
        let pluck = [6.0, -2.0, -1.8, 7.0, -2.2, -2.0, -8.0, -1.9, -2.1]
        for cents in pluck { capture.ingest(note(.open, cents)) }
        XCTAssertEqual(capture.open ?? .nan, -2.0, accuracy: 0.15)
    }

    func testASlotSwitchStartsANewRun() {
        var capture = IntonationCapture()
        for _ in 0..<5 { capture.ingest(note(.open, -2)) }
        for _ in 0..<6 { capture.ingest(note(.octave, 6)) }
        XCTAssertNil(capture.open, "five open frames never completed a run")
        XCTAssertEqual(capture.octave ?? .nan, 6, accuracy: 0.01)
    }

    /// A re-play after a saddle adjustment: the pause between plucks
    /// outlives the quiet grace, so the old evidence is gone and the new
    /// run speaks alone.
    func testTheLatestStableRunWins() {
        var capture = IntonationCapture()
        for _ in 0..<6 { capture.ingest(note(.octave, 6)) }
        for _ in 0..<(IntonationCapture.quietGraceFrames + 1) { capture.ingest(nothing) }
        for _ in 0..<6 { capture.ingest(note(.octave, 3)) }
        XCTAssertEqual(capture.octave ?? .nan, 3, accuracy: 0.01)
    }

    func testDeltaIsOctaveAgainstOpenPromise() {
        var capture = IntonationCapture()
        XCTAssertNil(capture.delta)
        for _ in 0..<6 { capture.ingest(note(.open, -2)) }
        XCTAssertNil(capture.delta, "one sample is not a comparison")
        capture.ingest(nothing)
        for _ in 0..<6 { capture.ingest(note(.octave, 6)) }
        XCTAssertEqual(capture.delta ?? .nan, 8, accuracy: 0.01)
    }

    func testResetForgetsEverything() {
        var capture = IntonationCapture()
        for _ in 0..<6 { capture.ingest(note(.open, -2)) }
        capture.reset()
        XCTAssertNil(capture.open)
        XCTAssertNil(capture.delta)
    }
}
