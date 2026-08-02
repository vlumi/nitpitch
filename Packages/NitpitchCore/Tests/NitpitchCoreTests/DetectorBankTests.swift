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

    /// Deterministic gaussian-ish noise: strength is signal-over-floor, and a
    /// synthetic signal with no noise floor reads full strength at any volume.
    private func noise(_ amount: Double, count: Int, seed: UInt64 = 7) -> [Double] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let u1 = Double(state >> 11) / Double(1 << 53)
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let u2 = Double(state >> 11) / Double(1 << 53)
            return sqrt(-2 * log(max(u1, 1e-12))) * cos(2 * .pi * u2) * amount
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

    /// The spectral path must skip quiet frames like MPM does — without the
    /// gate it "measures" the background of a quiet room and every dial
    /// twitches at noise (observed on a real microphone).
    func testSpectralIgnoresQuietFrames() {
        let bank = violinBank(engine: .spectral)
        let quiet = mix([tone(440, count: signalLength)]).map { $0 * 0.0005 }
        XCTAssertEqual(lit(analyze(bank, signal: quiet)), [])
    }

    /// And sound resuming after a quiet spell reads again — the gate breaks
    /// the phase pair, so this checks the re-priming too.
    func testSpectralRecoversAfterAQuietSpell() {
        let bank = violinBank(engine: .spectral)
        let signal = mix([tone(440, count: signalLength)])
        let quiet = signal.map { $0 * 0.0005 }
        _ = analyze(bank, signal: quiet)
        XCTAssertEqual(lit(analyze(bank, signal: signal)), [2])
    }

    /// A sounding string reports the strength behind its reading; the silent
    /// strings report none. This is what the cells' signal bars show.
    func testReadingsCarryPerStringLevel() {
        for engine in DetectionTuning.Engine.allCases {
            let bank = violinBank(engine: engine)
            let results = analyze(bank, signal: mix([tone(440, count: signalLength)]))
            XCTAssertGreaterThan(results[2].level, 0, "\(engine): sounding string has no level")
            for index in [0, 1, 3] {
                XCTAssertEqual(results[index].level, 0, "\(engine): silent string has level")
            }
        }
    }

    /// The strength gate speaks the signal bar's language: a reading whose bar
    /// falls short of the setting is dropped. Observed need: while one string
    /// plays, the frame is loud — the silence gate passes — and the estimator
    /// scrapes weak junk off other strings' bins. Real string near max, junk
    /// below half.
    ///
    /// Self-calibrating: measure the noisy tone's strength with the gate open,
    /// then close the gate just above it and require the reading to vanish.
    func testStrengthGateDropsWeakSpectralReadings() {
        // A tone with enough noise that its strength sits well below full
        // (measured: ~0.3 at this ratio) but still reads.
        let signal = mix([
            tone(440, count: signalLength, amp: 0.4),
            noise(0.05, count: signalLength),
        ])
        let bank = violinBank(engine: .spectral)
        bank.retune(DetectionTuning(engine: .spectral, spectralStrengthGate: 0))
        let open = analyze(bank, signal: signal)
        guard let strength = open.first(where: { $0.frequency != nil })?.level else {
            return XCTFail("the noisy tone should still read with the gate open")
        }
        XCTAssertLessThan(strength, 0.9, "noise should keep strength below full")

        bank.retune(
            DetectionTuning(engine: .spectral, spectralStrengthGate: min(0.9, strength + 0.02)))
        let gated = analyze(bank, signal: signal)
        XCTAssertEqual(lit(gated), [])
        // The near miss stays visible to the diagnostics screen.
        XCTAssertGreaterThan(gated.map(\.level).max() ?? 0, 0)
    }

    /// At the shipped default a solid tone must clear the gate comfortably —
    /// the gate exists to drop scraped junk, not honest playing.
    func testDefaultStrengthGatePassesAnHonestTone() {
        let bank = violinBank(engine: .spectral)
        let results = analyze(bank, signal: mix([tone(440, count: signalLength)]))
        XCTAssertEqual(lit(results), [2])
        XCTAssertGreaterThan(
            results[2].level, DetectionTuning.default.spectralStrengthGate,
            "an honest tone should sit well above the default gate")
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
