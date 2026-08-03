import XCTest

@testable import NitpitchCore

/// The detector is a pure function over a Float buffer, so it can be verified
/// against synthesized waveforms with no audio hardware — which is the whole
/// reason the DSP lives in NitpitchCore rather than NitpitchKit.
final class PitchDetectorTests: XCTestCase {
    private let sampleRate = 44100.0

    /// A sine at `hz`, optionally with harmonics — `harmonics` gives the
    /// amplitude of each partial starting at the fundamental.
    private func tone(
        _ hz: Double, harmonics: [Double] = [1.0], count: Int = Detection.windowSize,
        phase: Double = 0
    ) -> [Float] {
        (0..<count).map { i in
            let t = Double(i) / sampleRate
            var sample = 0.0
            for (index, amplitude) in harmonics.enumerated() {
                sample += amplitude * sin(2 * .pi * hz * Double(index + 1) * t + phase)
            }
            return Float(sample)
        }
    }

    private func detect(_ samples: [Float], band: ClosedRange<Double> = Detection.fullBand)
        -> DetectionResult
    {
        PitchDetector(sampleRate: sampleRate, band: band).analyze(samples)
    }

    func testDetectsPureSineAcrossTheFullRange() {
        // Every frequency the app claims to support, pure tone — including
        // 5-string bass B0 (30.9) and bass drop D (36.7) at the bottom.
        for hz in [30.87, 36.71, 41.2, 55.0, 98.0, 196.0, 293.66, 440.0, 659.26, 1200.0, 2000.0] {
            let result = detect(tone(hz))
            let found = try? XCTUnwrap(result.frequency)
            XCTAssertNotNil(found, "no detection at \(hz) Hz")
            guard let found else { continue }
            // Within one cent.
            let cents = abs(1200 * log2(found / hz))
            XCTAssertLessThan(cents, 1.0, "\(hz) Hz detected as \(found) Hz (\(cents) cents off)")
        }
    }

    func testAccuracyIsSubCentForViolinOpenStrings() {
        // The app's core promise: tuning accuracy on the four violin strings.
        for note in Instrument.violin.notes {
            let hz = note.frequency()
            let result = detect(tone(hz), band: Instrument.violin.band())
            guard let found = result.frequency else {
                XCTFail("no detection for \(note.fullName)")
                continue
            }
            let cents = abs(1200 * log2(found / hz))
            XCTAssertLessThan(cents, 0.5, "\(note.fullName): off by \(cents) cents")
        }
    }

    func testHarmonicRichToneDoesNotProduceOctaveError() {
        // A bowed string puts more energy in the harmonics than the
        // fundamental — the case where FFT peak-picking reports 2× or 3×.
        // Fundamental deliberately quieter than its partials.
        let hz = 196.0  // violin G3
        let result = detect(tone(hz, harmonics: [0.3, 1.0, 0.8, 0.5, 0.3]))
        guard let found = result.frequency else { return XCTFail("no detection") }
        let cents = abs(1200 * log2(found / hz))
        XCTAssertLessThan(cents, 2.0, "detected \(found) Hz — expected \(hz) (octave error?)")
    }

    func testMissingFundamentalStillReadsAsTheFundamental() {
        // Small speakers and some pickups roll off the fundamental entirely;
        // the pitch a listener hears is still the missing fundamental.
        let hz = 82.4  // guitar low E
        let result = detect(tone(hz, harmonics: [0.0, 1.0, 0.7, 0.4]))
        guard let found = result.frequency else { return XCTFail("no detection") }
        let cents = abs(1200 * log2(found / hz))
        XCTAssertLessThan(cents, 5.0, "detected \(found) Hz — expected \(hz)")
    }

    func testSilenceIsRejected() {
        let result = detect([Float](repeating: 0, count: Detection.windowSize))
        XCTAssertNil(result.frequency)
        XCTAssertEqual(result.clarity, 0)
    }

    func testWhiteNoiseIsRejectedByClarityGate() {
        // Aperiodic input must not produce a confident reading — this is the
        // gate that keeps bow noise and room sound off the display.
        var rng = SystemRandomNumberGenerator()
        let noise = (0..<Detection.windowSize).map { _ in
            Float.random(in: -1...1, using: &rng)
        }
        let result = detect(noise)
        XCTAssertNil(result.frequency, "noise produced a reading at clarity \(result.clarity)")
    }

    func testClarityIsHighForCleanToneAndReportedForRejected() {
        let clean = detect(tone(440))
        XCTAssertGreaterThan(clean.clarity, Detection.clarityThreshold)
        XCTAssertGreaterThan(clean.rms, Double(Detection.silenceRMS))
    }

    func testPhaseDoesNotAffectTheEstimate() {
        // Autocorrelation is phase-invariant; a frame boundary landing anywhere
        // in the cycle must give the same answer.
        for phase in stride(from: 0.0, to: 2 * .pi, by: .pi / 4) {
            let result = detect(tone(440, phase: phase))
            guard let found = result.frequency else {
                XCTFail("no detection at phase \(phase)")
                continue
            }
            XCTAssertEqual(found, 440, accuracy: 1.0)
        }
    }

    func testWrongFrameLengthIsRejectedRatherThanCrashing() {
        XCTAssertNil(detect([Float](repeating: 0.5, count: 100)).frequency)
    }

    func testDetunedStringReadsAsFlat() {
        // The actual use: an A string 12 cents flat should be found, and resolve
        // to A4-flat rather than to some other note.
        let hz = 440 * pow(2, -12.0 / 1200)
        guard let found = detect(tone(hz)).frequency else { return XCTFail("no detection") }
        let reading = PitchReading(frequency: found)
        XCTAssertEqual(reading.note.fullName, "A4")
        XCTAssertEqual(reading.cents, -12, accuracy: 1.0)
    }

    // MARK: - Narrow bands, one detector per string

    /// With a dial per string each detector searches a narrow band, and a
    /// result outside it means one string's dial showing a pitch that string
    /// never owned. Found in practice: playing A4 into violin's four detectors,
    /// the D4 detector reported 197 Hz and the E5 detector 315 Hz — both far
    /// below their own bands. `minLag`'s deliberate headroom, plus parabolic
    /// interpolation on top, can walk a peak past the edge.
    func testNeverReportsAPitchOutsideTheSearchedBand() {
        let bands = Instrument.violin.stringBands()
        // Sweep well past the bands themselves, so every detector is offered
        // plenty it must refuse.
        for band in bands {
            var hz = 60.0
            while hz < 1400 {
                let result = detect(tone(hz, harmonics: [0.3, 1.0, 0.8, 0.5, 0.3]), band: band)
                if let found = result.frequency {
                    XCTAssertTrue(
                        band.contains(found),
                        "band \(band) reported \(found) Hz for a \(hz) Hz tone")
                }
                hz *= 1.03
            }
        }
    }

    /// The NSDF is bounded by ±1, so clarity above 1 is meaningless — and worse
    /// than meaningless, since a value above the threshold *by construction*
    /// sails through the gate that exists to reject junk. The E5 detector was
    /// returning 1.286. Slightly negative is fine and expected: a frame with no
    /// periodicity in band anticorrelates, and the gate rejects it anyway.
    func testClarityNeverExceedsOne() {
        for band in Instrument.violin.stringBands() {
            var hz = 60.0
            while hz < 1400 {
                let clarity = detect(
                    tone(hz, harmonics: [0.3, 1.0, 0.8, 0.5, 0.3]), band: band
                ).clarity
                XCTAssertLessThanOrEqual(
                    clarity, 1, "clarity \(clarity) above 1 for \(hz) Hz in \(band)")
                hz *= 1.03
            }
        }
    }

    /// Each string's own note must survive its own narrow band — the fixes
    /// above reject results, so they need a test that they don't reject the
    /// right ones.
    func testEachStringIsStillFoundInItsOwnNarrowBand() {
        for instrument in Instrument.all where !instrument.strings.isEmpty {
            for (note, band) in zip(instrument.notes, instrument.stringBands()) {
                let hz = note.frequency()
                let result = detect(tone(hz, harmonics: [0.3, 1.0, 0.8, 0.5, 0.3]), band: band)
                guard let found = result.frequency else {
                    XCTFail("\(instrument.name) \(note.fullName): not found in its own band")
                    continue
                }
                XCTAssertEqual(
                    1200 * log2(found / hz), 0, accuracy: 5,
                    "\(instrument.name) \(note.fullName) read \(found) Hz")
            }
        }
    }

    // MARK: - Tunable thresholds

    /// The debug screen's knobs have to actually reach the detector, or it
    /// measures nothing.
    func testTuningThresholdsTakeEffect() {
        // A signal too noisy to clear the shipped clarity gate.
        var samples = tone(220, harmonics: [1.0, 0.5])
        var seed = UInt64(12345)
        for i in samples.indices {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            samples[i] += Float(Double(seed >> 40) / Double(1 << 24) - 0.5) * 1.2
        }

        let strict = PitchDetector(
            sampleRate: sampleRate, tuning: DetectionTuning(clarityThreshold: 0.99))
        let lax = PitchDetector(
            sampleRate: sampleRate, tuning: DetectionTuning(clarityThreshold: 0.5))
        XCTAssertNil(strict.analyze(samples).frequency, "0.99 should reject a noisy frame")
        XCTAssertNotNil(lax.analyze(samples).frequency, "0.5 should accept it")
    }

    /// Retuning a live detector is how the sliders work — the grid keeps its
    /// detectors and their smoothing rather than rebuilding on every tick.
    func testTuningCanBeChangedOnALiveDetector() {
        let detector = PitchDetector(sampleRate: sampleRate)
        let quiet = tone(440).map { $0 * 0.002 }
        XCTAssertNotNil(detector.analyze(quiet).frequency)
        detector.tuning.silenceRMS = 0.01
        XCTAssertNil(detector.analyze(quiet).frequency, "raised silence gate should reject it")
    }
}
