import XCTest

@testable import NitpitchCore

/// Sympathetic-ring rejection for DIAL LIGHTING.
///
/// A violin's strings are a fifth apart, so a played string's partials land
/// in its neighbours' bands: G's 2nd harmonic IS A's band (200¢ flat of A),
/// G's 3rd and D's 2nd both land in E's. Those are real, measurable,
/// perfectly periodic signals — the bank is not wrong to find them — but a
/// dial lit by a neighbour's harmonic tells the player nothing true.
///
/// The hard constraint: a genuinely bowed DOUBLE STOP puts both strings at
/// comparable strength, and the interval feature depends on both dials
/// reading. Any rule that suppresses rings must leave that untouched.
final class RingRejectionTests: XCTestCase {
    private let violin = Instrument.all.first { $0.id == "violin" }!

    /// Windows as `AudioInput` delivers them, through the grid's own bank.
    private func lit(_ signal: [Float], hops: Int = 20) -> [Int: Int] {
        let bank = DetectorBank(
            sampleRate: sampleRate,
            targets: violin.notes.map { $0.frequency() },
            bands: violin.stringBands(),
            tuning: .default)
        var tally: [Int: Int] = [:]
        var hop = 0
        while hop * Detection.hopSize + Detection.windowSize <= signal.count, hop < hops {
            let start = hop * Detection.hopSize
            for (i, r) in bank.analyze(
                Array(signal[start..<(start + Detection.windowSize)])
            ).enumerated() where r.frequency != nil {
                tally[i, default: 0] += 1
            }
            hop += 1
        }
        return tally
    }

    /// Two tones summed, each with its own level.
    private func bowed(_ voices: [(hz: Double, level: Double)], count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for v in voices {
            let t = tone(v.hz, count: count, peakLevel: v.level)
            for i in 0..<count { out[i] += t[i] }
        }
        return out
    }

    // MARK: - The limitation, measured

    /// KNOWN LIMITATION, investigated 2026-08-22 and deliberately not
    /// guarded — the numbers are here so the next attempt starts from them
    /// rather than from the same wrong premise.
    ///
    /// Bowing G and D sets the open A and E ringing, and their dials light.
    /// The roadmap's candidate fix was "suppress a reading a lower string's
    /// partial explains", by analogy with `SubharmonicFilter`. That premise
    /// is wrong: a violin's strings are a FIFTH apart, so no neighbour is an
    /// integer harmonic of another (G→A is 2.245×, a ninth). The ring is not
    /// a partial landing in a band — it is the A string genuinely vibrating
    /// at its own pitch, excited through the bridge. Nothing about the
    /// reading marks it.
    ///
    /// Energy was the next candidate, and it fails on real numbers. Summed
    /// partial energy (`HarmonicEstimator` internals, measured here):
    ///
    ///   ring         A/G = 0.035     (A excited by G bowed at 0.06)
    ///   ring         D/G = 0.137
    ///   double stop  A/G = 0.073     (A deliberately bowed at 0.15)
    ///   double stop  A/G = 0.145     (A at 0.30)
    ///
    /// The ring at 0.137 and the deliberate double stop at 0.073
    /// INTERLEAVE, so no threshold separates them — at a single instant the
    /// two situations are physically identical, and only the player knows
    /// which is which.
    ///
    /// What does differ is TIME: a ring has no attack of its own, rising and
    /// falling with the string that excites it. An onset-based rule could
    /// use that, but it would misfire on a SLOW BOW INTO a double stop —
    /// where the second string rises gradually, correlated with the first —
    /// which is standard violin technique and the case this app exists for.
    /// Field severity on b16 (iPhone): D+G legible, both values readable,
    /// only E flashing occasionally. High cost, core-use-case risk, low
    /// observed severity: not worth it yet.
    ///
    /// If it is ever attempted, `testAGenuineDoubleStopStillLightsBothDials`
    /// and the light-double-stop numbers above are what it has to beat.

    /// The limitation, asserted as it stands today so a future fix has to
    /// change this test on purpose rather than by accident: bowing G and D
    /// DOES light the A and E dials. See the analysis above for why neither
    /// a ratio rule nor an energy threshold can separate this from a
    /// deliberate light double stop.
    func testRingingNeighboursStillLightTheirDialsToday() {
        let f = violin.notes.map { $0.frequency() }
        let tally = lit(
            bowed(
                [(f[0], 0.5), (f[1], 0.45), (f[2], 0.06), (f[3], 0.05)],
                count: 44100))
        XCTAssertGreaterThan(tally[0] ?? 0, 10, "G is bowed")
        XCTAssertGreaterThan(tally[1] ?? 0, 10, "D is bowed")
        XCTAssertGreaterThan(
            tally[2] ?? 0, 10,
            "A only rings, yet lights — the limitation, not a wish")
    }

    // MARK: - What must not break

    /// The double stop the interval feature is built on: both strings bowed,
    /// comparable strength. BOTH dials must read.
    func testAGenuineDoubleStopStillLightsBothDials() {
        let f = violin.notes.map { $0.frequency() }
        let signal = bowed([(f[1], 0.5), (f[2], 0.45)], count: 44100)
        let tally = lit(signal)
        XCTAssertGreaterThan(tally[1] ?? 0, 10, "D is bowed")
        XCTAssertGreaterThan(tally[2] ?? 0, 10, "A is bowed — the pair needs both")
    }

    /// One string alone, loud: its own dial and nothing else.
    func testASingleBowedStringLightsOnlyItsOwnDial() {
        let f = violin.notes.map { $0.frequency() }
        let tally = lit(bowed([(f[1], 0.6)], count: 44100))
        XCTAssertGreaterThan(tally[1] ?? 0, 10, "D reads")
        for other in [0, 2, 3] {
            XCTAssertLessThan(tally[other] ?? 0, 5, "string \(other) must stay dark")
        }
    }
}
