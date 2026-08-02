import XCTest

@testable import NitpitchCore

/// The estimator's whole promise is polyphony: several known notes, one signal,
/// each measured to cent accuracy — which MPM structurally cannot do. Verified
/// the same way as `PitchDetector`: synthesized waveforms, no audio hardware.
final class HarmonicEstimatorTests: XCTestCase {
    private let sampleRate = 44100.0
    private let violin = Instrument.violin.notes.map { $0.frequency() }

    /// A harmonically rich tone the way a bowed string is: fundamental quieter
    /// than the 2nd partial.
    private func tone(
        _ hz: Double, count: Int, amp: Double = 1, phase0: Double = 0
    ) -> [Double] {
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

    /// Feed a continuous signal as `AudioInput` would: two windows, hop apart.
    private func primed(with signal: [Float]) -> HarmonicEstimator {
        let estimator = HarmonicEstimator(sampleRate: sampleRate)
        estimator.ingest(Array(signal[0..<Detection.windowSize]))
        estimator.ingest(
            Array(signal[Detection.hopSize..<(Detection.hopSize + Detection.windowSize)]))
        return estimator
    }

    private let signalLength = Detection.windowSize + Detection.hopSize

    private func cents(_ a: Double, _ b: Double) -> Double { 1200 * log2(a / b) }

    // MARK: - The polyphonic case, which is the whole point

    /// Two strings bowed at once — a violinist tuning by fifths. Each must be
    /// measured against its own target, sub-cent, from the one mixed signal.
    func testMeasuresBothNotesOfADoubleStop() {
        let pairs = [(0, 1), (1, 2), (2, 3)]  // G+D, D+A, A+E
        for (lo, hi) in pairs {
            let detunedLo = violin[lo] * pow(2, -8.0 / 1200)
            let detunedHi = violin[hi] * pow(2, 5.0 / 1200)
            let signal = mix([
                tone(detunedLo, count: signalLength),
                tone(detunedHi, count: signalLength, phase0: 1.1),
            ])
            let estimator = primed(with: signal)
            let others = violin.enumerated().filter { $0.offset != lo }.map(\.element)
            let othersHi = violin.enumerated().filter { $0.offset != hi }.map(\.element)

            guard let readLo = estimator.measure(target: violin[lo], others: others),
                let readHi = estimator.measure(target: violin[hi], others: othersHi)
            else {
                XCTFail("pair \(lo)+\(hi): a sounding string was not measured")
                continue
            }
            XCTAssertEqual(
                cents(readLo.frequency, violin[lo]), -8, accuracy: 1,
                "lower of pair \(lo)+\(hi)")
            XCTAssertEqual(
                cents(readHi.frequency, violin[hi]), 5, accuracy: 1,
                "upper of pair \(lo)+\(hi)")
        }
    }

    /// The bow rarely feeds both strings equally; at 4:1 the quiet string's
    /// partials are untouched, just smaller, and must still measure true.
    func testSurvivesUnequalBowPressure() {
        let g = violin[0] * pow(2, -12.0 / 1200)
        let signal = mix([
            tone(g, count: signalLength, amp: 0.25),
            tone(violin[1], count: signalLength, phase0: 1.1),
        ])
        let estimator = primed(with: signal)
        let others = Array(violin[1...])
        guard let read = estimator.measure(target: violin[0], others: others) else {
            return XCTFail("quiet G was not measured")
        }
        XCTAssertEqual(cents(read.frequency, violin[0]), -12, accuracy: 1)
    }

    /// Strength is signal-over-floor, not loudness: a clean tone reads full at
    /// any volume (the floor scales with it), and burying the same tone in
    /// noise is what drags it down. That's the property that separates a bowed
    /// string from junk scraped off a loud frame.
    func testStrengthFallsAsNoiseRises() {
        let others = Array(violin[1...])
        var strengths: [Double] = []
        for noiseAmount in [0.0, 0.02, 0.08] {
            let signal = mix([
                tone(violin[0], count: signalLength, amp: 0.4),
                noise(noiseAmount, count: signalLength),
            ])
            let estimator = primed(with: signal)
            guard let read = estimator.measure(target: violin[0], others: others) else {
                XCTFail("not measured at noise \(noiseAmount)")
                continue
            }
            XCTAssertTrue(
                (0...1).contains(read.strength), "strength out of range at \(noiseAmount)")
            strengths.append(read.strength)
        }
        XCTAssertEqual(
            strengths, strengths.sorted(by: >), "strength should fall as noise rises")
    }

    /// Deterministic gaussian-ish noise, matching the bank tests' helper.
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

    // MARK: - Presence: absent strings must go dark

    /// The estimator answers "what frequency is here" even at an empty bin, so
    /// the gate is what stops an unplayed string's dial from reading leakage.
    /// This is the exact failure that killed the MPM grid: play A, G lights.
    func testUnplayedStringsAreNotReported() {
        let signal = mix([tone(violin[2], count: signalLength)])  // A4 alone
        let estimator = primed(with: signal)
        for (index, target) in violin.enumerated() where index != 2 {
            let others = violin.enumerated().filter { $0.offset != index }.map(\.element)
            XCTAssertNil(
                estimator.measure(target: target, others: others),
                "string \(index) reported a reading while only A4 sounded")
        }
        // And the one that IS sounding still reads.
        let others = violin.enumerated().filter { $0.offset != 2 }.map(\.element)
        XCTAssertNotNil(estimator.measure(target: violin[2], others: others))
    }

    /// Silence reports nothing anywhere.
    func testSilenceMeasuresNothing() {
        let estimator = HarmonicEstimator(sampleRate: sampleRate)
        let silence = [Float](repeating: 0, count: Detection.windowSize)
        estimator.ingest(silence)
        estimator.ingest(silence)
        let others = Array(violin[1...])
        XCTAssertNil(estimator.measure(target: violin[0], others: others))
    }

    /// One window is not a measurement — phase needs a pair.
    func testDeclinesBeforeASecondWindow() {
        let signal = mix([tone(violin[2], count: signalLength)])
        let estimator = HarmonicEstimator(sampleRate: sampleRate)
        estimator.ingest(Array(signal[0..<Detection.windowSize]))
        let others = violin.enumerated().filter { $0.offset != 2 }.map(\.element)
        XCTAssertNil(estimator.measure(target: violin[2], others: others))
    }

    /// After `reset` the pair is broken; a stale previous window must not be
    /// compared against — a discontinuity reads as a confidently wrong pitch.
    func testResetRequiresRepriming() {
        let signal = mix([tone(violin[2], count: signalLength)])
        let estimator = primed(with: signal)
        estimator.reset()
        let others = violin.enumerated().filter { $0.offset != 2 }.map(\.element)
        XCTAssertNil(estimator.measure(target: violin[2], others: others))
    }

    // MARK: - Single notes, parity with the MPM path

    /// Each violin string alone, slightly detuned, measured sub-cent — the
    /// ordinary case has to be at least as good as it is polyphonically.
    func testEachStringAloneMeasuresSubCent() {
        for (index, target) in violin.enumerated() {
            for err in [-40.0, -8, 0, 5, 40] {
                let hz = target * pow(2, err / 1200)
                let estimator = primed(with: mix([tone(hz, count: signalLength)]))
                let others = violin.enumerated().filter { $0.offset != index }.map(\.element)
                guard let read = estimator.measure(target: target, others: others) else {
                    XCTFail("string \(index) at \(err)¢ not measured")
                    continue
                }
                XCTAssertEqual(
                    cents(read.frequency, target), err, accuracy: 0.5,
                    "string \(index) at \(err)¢")
            }
        }
    }

    /// Guitar's low E2 and high E4 are two octaves apart — the case where the
    /// MPM path saw a phantom E2 at −0¢ whenever E4 played. Here E2's dial has
    /// to stay dark: E2's unshared partials (odd ones) have no energy.
    func testGuitarHighEDoesNotLightLowE() {
        let guitar = Instrument.guitar.notes.map { $0.frequency() }
        let signal = mix([tone(guitar[5], count: signalLength)])  // high E4
        let estimator = primed(with: signal)
        let others = guitar.enumerated().filter { $0.offset != 0 }.map(\.element)
        XCTAssertNil(
            estimator.measure(target: guitar[0], others: others),
            "E2 reported a reading while only E4 sounded")
    }

    /// Beyond the search window the estimator declines rather than grabbing a
    /// neighbouring partial — a badly slack string is MPM's case, not this
    /// path's, and a wrong confident answer would be worse than none.
    func testFarOffPitchIsDeclinedNotMisread() {
        let g = violin[0] * pow(2, -300.0 / 1200)  // 3 semitones flat
        let estimator = primed(with: mix([tone(g, count: signalLength)]))
        let others = Array(violin[1...])
        if let read = estimator.measure(target: violin[0], others: others) {
            XCTFail("read \(read.frequency) Hz for a string 300¢ flat — should decline")
        }
    }
}
