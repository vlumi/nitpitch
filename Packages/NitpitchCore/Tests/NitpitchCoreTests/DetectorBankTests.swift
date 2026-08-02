import XCTest

@testable import NitpitchCore

/// The bank is where "for each found tone, only one dial lights" actually gets
/// enforced — the property the per-dial architecture couldn't have, tested for
/// both engines against the cases observed on a real violin.
final class DetectorBankTests: XCTestCase {
    private let sampleRate = 44100.0

    private func tone(_ hz: Double, count: Int, amp: Double = 1, phase0: Double = 0) -> [Double] {
        let harmonics = [0.3, 1.0, 0.8, 0.5, 0.3, 0.2]
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            var s = 0.0
            for (k, a) in harmonics.enumerated() {
                let h = Double(k + 1)
                s += a * sin(2 * .pi * hz * h * t + phase0 * h)
            }
            return s * amp
        }
    }

    private func mix(_ parts: [[Double]]) -> [Float] {
        guard let first = parts.first else { return [] }
        var out = [Double](repeating: 0, count: first.count)
        for p in parts { for i in out.indices { out[i] += p[i] } }
        let peak = out.map(abs).max() ?? 1
        return out.map { Float($0 / max(peak, 1e-12) * 0.8) }
    }

    private func violinBank(engine: DetectionTuning.Engine) -> DetectorBank {
        let violin = Instrument.violin
        return DetectorBank(
            sampleRate: sampleRate,
            targets: violin.notes.map { $0.frequency() },
            bands: violin.stringBands(),
            tuning: DetectionTuning(engine: engine))
    }

    /// Run a continuous signal through as `AudioInput` would: consecutive
    /// windows a hop apart. Returns the last window's results — by then both
    /// engines are primed.
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

    private func lit(_ results: [DetectionResult]) -> Set<Int> {
        Set(results.enumerated().compactMap { $0.element.frequency != nil ? $0.offset : nil })
    }

    // MARK: - The reported bug, per engine

    /// "Play A, G lights up" — the real-violin observation. Under MPM the G
    /// detector genuinely finds A's subharmonic; the filter must eat it.
    func testPlayingAMakesOnlyALight() {
        for engine in DetectionTuning.Engine.allCases {
            let bank = violinBank(engine: engine)
            let results = analyze(bank, signal: mix([tone(440, count: signalLength)]))
            XCTAssertEqual(lit(results), [2], "\(engine): wrong dials lit")
            XCTAssertEqual(results[2].frequency ?? 0, 440, accuracy: 1, "\(engine)")
        }
    }

    /// "Both G and D light up on E, about 200¢ off" — the other real-violin
    /// observation: E's subharmonics at ÷2 and ÷3.
    func testPlayingEMakesOnlyELight() {
        let e5 = Instrument.violin.notes[3].frequency()
        for engine in DetectionTuning.Engine.allCases {
            let bank = violinBank(engine: engine)
            let results = analyze(bank, signal: mix([tone(e5, count: signalLength)]))
            XCTAssertEqual(lit(results), [3], "\(engine): wrong dials lit")
        }
    }

    /// A slack string is the case the wide bands exist for, and the filter must
    /// not eat it: far from target, but nothing above claims its frequency.
    func testSlackStringStillReadsUnderMPM() {
        let g = Instrument.violin.notes[0].frequency() * pow(2, -300.0 / 1200)
        let bank = violinBank(engine: .mpm)
        let results = analyze(bank, signal: mix([tone(g, count: signalLength)]))
        XCTAssertEqual(lit(results), [0])
        XCTAssertEqual(
            1200 * log2((results[0].frequency ?? 1) / Instrument.violin.notes[0].frequency()),
            -300, accuracy: 5)
    }

    // MARK: - What only the spectral engine can do

    /// Two strings bowed at once — how violinists actually tune. MPM cannot
    /// resolve this; the spectral engine must light both dials, each with its
    /// own deviation.
    func testDoubleStopLightsBothDialsUnderSpectral() {
        let violin = Instrument.violin.notes.map { $0.frequency() }
        let a = violin[2] * pow(2, -8.0 / 1200)
        let e = violin[3] * pow(2, 5.0 / 1200)
        let bank = violinBank(engine: .spectral)
        let results = analyze(
            bank,
            signal: mix([
                tone(a, count: signalLength), tone(e, count: signalLength, phase0: 1.1),
            ]))
        XCTAssertEqual(lit(results), [2, 3])
        XCTAssertEqual(1200 * log2((results[2].frequency ?? 1) / violin[2]), -8, accuracy: 1)
        XCTAssertEqual(1200 * log2((results[3].frequency ?? 1) / violin[3]), 5, accuracy: 1)
    }

    // MARK: - Reconfiguration

    /// Switching engines mid-stream must work — it's a segmented control on
    /// the debug screen, flipped while the instrument sounds.
    func testEngineSwitchesLive() {
        let bank = violinBank(engine: .mpm)
        let signal = mix([tone(440, count: signalLength)])
        XCTAssertEqual(lit(analyze(bank, signal: signal)), [2])
        bank.retune(DetectionTuning(engine: .spectral))
        XCTAssertEqual(lit(analyze(bank, signal: signal)), [2])
        bank.retune(DetectionTuning(engine: .mpm))
        XCTAssertEqual(lit(analyze(bank, signal: signal)), [2])
    }

    /// The reference moving retargets every string; a 442 A at 442 reads 0.
    func testConfigureFollowsTheReference() {
        let bank = violinBank(engine: .mpm)
        let at442 = ReferencePitch(hz: 442)
        bank.configure(
            targets: Instrument.violin.notes.map { $0.frequency(reference: at442) },
            bands: Instrument.violin.stringBands(reference: at442),
            tuning: .default)
        let results = analyze(bank, signal: mix([tone(442, count: signalLength)]))
        XCTAssertEqual(lit(results), [2])
        XCTAssertEqual(results[2].frequency ?? 0, 442, accuracy: 1)
    }

    /// After an interruption the spectral engine must re-prime rather than
    /// compare phases across the gap.
    func testInterruptionResetsTheSpectralPair() {
        let bank = violinBank(engine: .spectral)
        let signal = mix([tone(440, count: signalLength)])
        XCTAssertEqual(lit(analyze(bank, signal: signal)), [2])
        bank.interrupted()
        // One window after the gap: no pair yet, so nothing may read.
        let first = bank.analyze(Array(signal[0..<Detection.windowSize]))
        XCTAssertEqual(lit(first), [])
        // The next window re-primes it.
        let second = bank.analyze(
            Array(signal[Detection.hopSize..<(Detection.hopSize + Detection.windowSize)]))
        XCTAssertEqual(lit(second), [2])
    }
}
