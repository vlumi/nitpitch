import XCTest

@testable import NitpitchCore

/// The roadmap's open measurement, settled headlessly: per-hop analysis
/// cost for N live dials, against the 46 ms hop budget (2048 samples at
/// 44.1 kHz). Absolute numbers are machine-relative — an SE 3's A15 runs
/// roughly a third of a desktop M-series core — so the assertion bound is
/// generous and the printed numbers are the real product.
final class DetectorBankPerformanceTests: XCTestCase {
    private func tone(_ hz: Double, count: Int, offset: Int) -> [Float] {
        (0..<count).map { i in
            Float(sin(2 * .pi * hz * Double(i + offset) / 44_100))
        }
    }

    /// Sliding hop-consecutive windows, as the spectral engine requires.
    private func windows(hz: Double, hops: Int) -> [[Float]] {
        (0..<hops).map { hop in
            tone(hz, count: Detection.windowSize, offset: hop * Detection.hopSize)
        }
    }

    private func measurePerHop(bank: DetectorBank, windows: [[Float]]) -> Double {
        // Warm-up pass settles allocations and the FFT setup.
        for window in windows { _ = bank.analyze(window) }
        let passes = 5
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<passes {
            for window in windows { _ = bank.analyze(window) }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        return elapsed / Double(passes * windows.count) * 1000  // ms per hop
    }

    func testPerHopCostFitsTheHopWithMargin() {
        let reference = ReferencePitch.standard
        let slid = windows(hz: 110, hops: 24)

        var results: [(String, Double)] = []
        for instrument in [Instrument.violin, .guitar, .guitar8] {
            let bank = DetectorBank(
                sampleRate: 44_100,
                targets: instrument.notes.map { $0.frequency(reference: reference) },
                bands: instrument.stringBands(),
                tuning: .default)
            results.append(
                (
                    "\(instrument.name) (\(instrument.strings.count) dials, hybrid)",
                    measurePerHop(bank: bank, windows: slid)
                ))
        }
        // The chromatic case, approximated: one detector on the full band —
        // the longest lag search there is.
        let chromatic = DetectorBank(
            sampleRate: 44_100,
            targets: [110],
            bands: [Detection.fullBand],
            tuning: DetectionTuning(engine: .mpm))
        results.append(
            ("chromatic (1 dial, full band)", measurePerHop(bank: chromatic, windows: slid)))

        let hopBudget = Double(Detection.hopSize) / 44_100 * 1000
        for (label, ms) in results {
            print(String(format: "perf: %@ — %.2f ms/hop (budget %.1f ms)", label, ms, hopBudget))
            // Generous: even a device several times slower than this machine
            // must clear the hop with room. Failing this means the design's
            // "analysis is cheaper than real time" premise broke.
            XCTAssertLessThan(ms, hopBudget / 2, label)
        }
    }
}
