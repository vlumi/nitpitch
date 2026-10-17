import XCTest

@testable import NitpitchCore

/// A double stop must survive a device that can't keep up.
///
/// Reading two strings at once is the SPECTRAL engine's job alone — MPM
/// finds one period and a double stop has none — and spectral measures
/// frequency from the phase advance between CONSECUTIVE windows. So when a
/// slow device makes the capture drop frames, what survives has to stay
/// consecutive, or the pair stops reading entirely.
///
/// Field-found on an A12 iPhone (XR, b19): bowing a violin's D and G, only
/// G read, and the weaker of the two lost most. Before b18 nothing was ever
/// dropped — the backlog trim was dead code — so this is the cost of making
/// it real, and these pin the shape that keeps both.
final class DoubleStopUnderLoadTests: XCTestCase {
    private func violinPair(dGain: Double, hops: Int) -> [Float] {
        let targets = Instrument.violin.notes.map { $0.frequency() }
        let count = signalLength(hops: hops)
        let bowed: [Double] = [0.5, 1.0, 0.7, 0.4, 0.2, 0.1]
        let g = tone(targets[0], count: count, harmonics: bowed, peakLevel: 0.45)
        let d = tone(targets[1], count: count, harmonics: bowed, peakLevel: 0.45 * dGain)
        return zip(g, d).map { $0 + $1 }
    }

    /// The assembler's promise: what it hands back is consecutive, even
    /// when it had to discard — an odd tail would be a window whose
    /// predecessor was just dropped, which measures nothing.
    func testDroppingKeepsWindowsInConsecutivePairs() {
        var assembler = HopAssembler(windowSize: 8, hopSize: 4, maxInFlight: 6)
        // Eight windows at once, nothing finished: more than the cap.
        let batch = assembler.append((0..<(8 + 7 * 4)).map(Float.init))
        XCTAssertEqual(
            batch.windows.count % 3, 0,
            "what survives is whole runs of three — two to reach a measurement, "
                + "a third so the confirmation rule can agree with it")
        XCTAssertTrue(batch.gapBefore, "and the discard is announced")
        for (first, second) in zip(batch.windows, batch.windows.dropFirst()) {
            // Consecutive windows overlap by (windowSize - hopSize).
            XCTAssertEqual(
                Array(first.suffix(4)), Array(second.prefix(4)),
                "each window continues the one before it")
        }
    }

    /// The field case: both strings keep reading when the device drops
    /// frames. The pre-fix code reset the phase pair on every discard, and
    /// the weaker string went dark (G 8/12, D 4/12 at an imbalanced bow).
    func testBothStringsSurviveDroppedFrames() {
        let targets = Instrument.violin.notes.map { $0.frequency() }
        let hops = 24
        // A real bow rarely balances: the quieter string is the one that
        // used to lose, so it is the one worth asserting.
        let signal = violinPair(dGain: 0.35, hops: hops)
        let bank = DetectorBank(
            sampleRate: sampleRate, targets: targets,
            bands: Instrument.violin.stringBands(), tuning: .default)

        // Drive the REAL assembler under a consumer that can't keep up:
        // it never reports windows finished, so every batch overruns the
        // cap and the drop policy decides what survives. That policy is
        // what this test is about, so nothing here may hand-wave it.
        var assembler = HopAssembler()
        var lit = (g: 0, d: 0)
        var cursor = 0
        while cursor + Detection.hopSize <= signal.count {
            let chunk = Array(signal[cursor..<(cursor + Detection.hopSize)])
            cursor += Detection.hopSize
            let batch = assembler.append(chunk)
            guard !batch.windows.isEmpty else { continue }
            // The consumer's gap handler, exactly as the view models wire it.
            if batch.gapBefore { bank.interrupted() }
            for window in batch.windows {
                let results = bank.analyze(window)
                if results[0].frequency != nil { lit.g += 1 }
                if results[1].frequency != nil { lit.d += 1 }
            }
            // Deliberately NOT calling `finished` — this is the device
            // that fell behind.
        }
        XCTAssertGreaterThan(lit.d, 0, "the quieter string still reads when frames are dropped")
        XCTAssertGreaterThan(lit.g, 0, "and so does the louder one")
    }
}
