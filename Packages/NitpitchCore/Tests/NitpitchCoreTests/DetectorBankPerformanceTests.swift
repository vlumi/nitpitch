import XCTest

@testable import NitpitchCore

/// The roadmap's open measurement, settled headlessly: per-hop analysis
/// cost for N live dials, against the 46 ms hop budget (2048 samples at
/// 44.1 kHz). Absolute numbers are machine-relative — an SE 3's A15 runs
/// roughly a third of a desktop M-series core — so the assertion bound is
/// generous and the printed numbers are the real product.
///
/// Run with `swift test -c release` for honest numbers: the debug build is
/// ~10× slower (3.2 vs 0.30 ms/hop for a violin on an M-series), and the
/// app ships release. Measured 2026-09 on an M-series: violin hybrid 0.30,
/// guitar 0.53, 8-string 0.85, chromatic full-band MPM 0.23 ms/hop — so
/// even a device ten times slower spends under a tenth of the hop on DSP.
/// If a screen feels slow, look at rendering and main-actor churn first.
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

    /// The heaviest real screens, not one bank in isolation. The string
    /// view runs THREE pipelines serially per hop (its own bank, the
    /// FollowFocus ear's bank, and the intonation analyzer while the check
    /// is on); and a frame spectral rejects falls through to MPM on every
    /// band plus the sentinel — the fallback is the expensive engine.
    func testTheRealScreenLoadsFitTheHop() {
        let reference = ReferencePitch.standard
        let guitar = Instrument.guitar
        let targets = guitar.notes.map { $0.frequency(reference: reference) }
        let hopBudget = Double(Detection.hopSize) / 44_100 * 1000

        // The string view on a guitar, a note sounding (spectral wins).
        let dialBank = DetectorBank(
            sampleRate: 44_100, targets: targets, bands: guitar.stringBands(), tuning: .default)
        let followBank = DetectorBank(
            sampleRate: 44_100, targets: targets, bands: guitar.stringBands(), tuning: .default)
        let analyzer = IntonationAnalyzer(sampleRate: 44_100, target: targets[0], tuning: .default)
        analyzer.setActive(true)
        let sounding = windows(hz: 110, hops: 24)
        for window in sounding {
            _ = dialBank.analyze(window)
            _ = followBank.analyze(window)
            _ = analyzer.analyze(window)
        }
        let passes = 5
        var start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<passes {
            for window in sounding {
                _ = dialBank.analyzeWithAbove(window)
                _ = followBank.analyze(window)
                _ = analyzer.analyze(window)
            }
        }
        let stringView =
            (CFAbsoluteTimeGetCurrent() - start) / Double(passes * sounding.count) * 1000

        // The MPM fallback: a loud frame spectral can't read (noise), so
        // every band's detector and the sentinel run — the worst hop.
        var state: UInt64 = 7
        let noisy: [[Float]] = (0..<24).map { _ in
            (0..<Detection.windowSize).map { _ in
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Float(Double(state >> 11) / Double(UInt64.max >> 11) * 0.6 - 0.3)
            }
        }
        let gridBank = DetectorBank(
            sampleRate: 44_100, targets: targets, bands: guitar.stringBands(), tuning: .default)
        for window in noisy { _ = gridBank.analyzeWithAbove(window) }
        start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<passes {
            for window in noisy { _ = gridBank.analyzeWithAbove(window) }
        }
        let fallback = (CFAbsoluteTimeGetCurrent() - start) / Double(passes * noisy.count) * 1000

        for (label, ms) in [
            ("string view, guitar, checking (2 banks + analyzer)", stringView),
            ("grid, guitar, MPM fallback on a noise frame", fallback),
        ] {
            print(String(format: "perf: %@ — %.2f ms/hop (budget %.1f ms)", label, ms, hopBudget))
            XCTAssertLessThan(ms, hopBudget / 2, label)
        }
    }
}
