import XCTest

@testable import NitpitchCore

/// The bank's side of the parity contract, and the sentinel above the
/// bands — the grid's plumbing, same synthesized diet.
final class IntonationBankTests: XCTestCase {
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
