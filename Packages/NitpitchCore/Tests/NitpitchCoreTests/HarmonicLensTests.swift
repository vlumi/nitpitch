import XCTest

@testable import NitpitchCore

/// The harmonic lens: a 7th-fret-style harmonic — a note at 3·f with no
/// low partial of f — folds back to its own string's error, labelled,
/// WITHOUT relaxing the anchor rule. Its guards are each a real impostor:
/// shared slots (the fourths' 4:3, the fifths' 3:2), unanchored leftover
/// constellations, and the note a fifth above whose even partials sit in
/// the lens's own slots.
final class HarmonicLensTests: XCTestCase {
    private let sampleRate = 44100.0

    /// A note at `hz` with its OWN harmonic series — which is what touching
    /// a node produces: the k-th harmonic rings at k·f with partials at
    /// multiples of k·f and nothing at f.
    private func tone(_ hz: Double, count: Int, phase0: Double = 0) -> [Double] {
        let harmonics = [0.3, 1.0, 0.8, 0.5, 0.3, 0.2]
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            var s = 0.0
            for (k, a) in harmonics.enumerated() {
                let h = Double(k + 1)
                s += a * sin(2 * .pi * hz * h * t + phase0 * h)
            }
            return s
        }
    }

    private func mix(_ parts: [[Double]]) -> [Float] {
        guard let first = parts.first else { return [] }
        var out = [Double](repeating: 0, count: first.count)
        for p in parts { for i in out.indices { out[i] += p[i] } }
        let peak = out.map(abs).max() ?? 1
        return out.map { Float($0 / max(peak, 1e-12) * 0.8) }
    }

    private func bank(
        for instrument: Instrument, engine: DetectionTuning.Engine = .spectral
    ) -> DetectorBank {
        DetectorBank(
            sampleRate: sampleRate,
            targets: instrument.notes.map { $0.frequency() },
            bands: instrument.stringBands(),
            tuning: DetectionTuning(engine: engine))
    }

    private func analyze(_ bank: DetectorBank, signal: [Float]) -> [DetectionResult] {
        var results: [DetectionResult] = []
        var offset = 0
        while offset + Detection.windowSize <= signal.count {
            results = bank.analyze(Array(signal[offset..<(offset + Detection.windowSize)]))
            offset += Detection.hopSize
        }
        return results
    }

    private var signalLength: Int { Detection.windowSize + Detection.hopSize * 2 }

    private func cents(_ hz: Double, against target: Double) -> Double {
        PitchMath.cents(from: target, to: hz)
    }

    /// A bass low E's 7th-fret-style harmonic (3·f, 5¢ sharp) reads as the
    /// E STRING 5¢ sharp — folded, labelled, and claimed by no other dial.
    func testThirdHarmonicFoldsToItsString() {
        let bass = Instrument.bassGuitar
        let lowE = bass.notes[0].frequency()
        let bank = bank(for: bass)
        let signal = mix([tone(3 * lowE * pow(2, 5.0 / 1200), count: signalLength)])

        let results = analyze(bank, signal: signal)
        guard let hz = results[0].frequency else {
            return XCTFail("the E dial did not read its 3rd harmonic")
        }
        XCTAssertEqual(cents(hz, against: lowE), 5, accuracy: 1)
        XCTAssertEqual(results[0].harmonic, 3)
        for index in 1..<results.count {
            XCTAssertNil(results[index].frequency, "string \(index) claimed the harmonic")
        }
    }

    /// The impostor the half-lens check exists for: a NOTE at 1.5·f — the
    /// fifth above, nothing exotic — has even partials sitting exactly in
    /// the lens's slots, anchored. On a single-target bank (the string
    /// view's shape, no neighbours to collide with) the lens must refuse
    /// it: an A played against a lone D target is ~+700¢, never "in tune
    /// 3rd harmonic".
    func testAFifthAboveIsNotTheThirdHarmonic() {
        let d4 = Instrument.violin.notes[1].frequency()
        let bank = DetectorBank(
            sampleRate: sampleRate,
            targets: [d4],
            bands: [55.0...2100.0],
            tuning: DetectionTuning(engine: .spectral))
        let signal = mix([tone(440, count: signalLength)])

        let results = analyze(bank, signal: signal)
        if let hz = results[0].frequency {
            XCTAssertGreaterThan(
                abs(cents(hz, against: d4)), 100,
                "a fifth above must never read near the target")
        }
        XCTAssertNotEqual(results[0].harmonic, 3, "the impostor took the lens")
    }

    /// The guard that makes the lenses shippable: a guitar's open B sits at
    /// low E's 3·f, and the lens slot it would anchor through is shared
    /// with the B string's own — so the lens refuses. Under the shipped
    /// hybrid, MPM reads the B in its own band and the note lands where it
    /// belongs. (Spectrally the open B is blind on a 6-string — its low
    /// slots are all shared — which is exactly why the hybrid exists.)
    func testGuitarOpenBIsNotLowEsThirdHarmonic() {
        let guitar = Instrument.guitar
        let b3 = guitar.notes[4].frequency()
        let bank = bank(for: guitar, engine: .hybrid)
        let signal = mix([tone(b3, count: signalLength)])

        let results = analyze(bank, signal: signal)
        XCTAssertNil(results[0].frequency, "low E claimed the open B")
        XCTAssertNotNil(results[4].frequency, "the B string should read its own note")
        XCTAssertEqual(results[4].harmonic, 1)
    }

    /// The fifths' pathology, kept honest: a violin D's 3rd harmonic IS the
    /// A string's octave (3:2 — the very coincidence fifths tune by), so
    /// EVERY low slot either string could claim it through is shared
    /// evidence. The grid's answer is silence — no dial lights for a note
    /// that two strings explain equally — never a false label. (The
    /// A-octave read still exists where it belongs: the intonation layer
    /// measures one target with no neighbours to collide with.)
    func testViolinSharedHarmonicClaimsNoDial() {
        let violin = Instrument.violin
        let a4 = violin.notes[2].frequency()
        let bank = bank(for: violin)
        let signal = mix([tone(2 * a4, count: signalLength)])

        let results = analyze(bank, signal: signal)
        XCTAssertNil(results[1].frequency, "the D dial claimed A's octave")
        XCTAssertNil(results[2].frequency, "shared evidence must not light A either")
    }

    /// The open string and the plain octave keep their numbers: 1 and 2 —
    /// the lenses never run when the plain measure already answered. (On
    /// the G string, whose even slots stay unshared; A's are the fifths'
    /// pathology above.)
    func testOpenAndOctaveKeepTheirHarmonicNumbers() {
        let violin = Instrument.violin
        let g3 = violin.notes[0].frequency()

        let open = analyze(
            bank(for: violin), signal: mix([tone(g3, count: signalLength)]))
        XCTAssertEqual(open[0].harmonic, 1)

        // The octave: even partials only, which the plain measure accepts
        // (anchor 2) and fingerprints — no lens involved.
        let octaveTone = (0..<signalLength).map { i -> Double in
            let t = Double(i) / sampleRate
            return sin(2 * .pi * 2 * g3 * t) + 0.4 * sin(2 * .pi * 4 * g3 * t)
        }
        let octave = analyze(bank(for: violin), signal: mix([octaveTone]))
        XCTAssertEqual(octave[0].harmonic, 2)
        XCTAssertTrue(octave[0].evenPartialsOnly)
    }
}
