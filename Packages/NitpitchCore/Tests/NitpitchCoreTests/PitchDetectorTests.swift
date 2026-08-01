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
        // Every frequency the app claims to support, pure tone.
        for hz in [41.2, 55.0, 98.0, 196.0, 293.66, 440.0, 659.26, 1200.0, 2000.0] {
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
}
