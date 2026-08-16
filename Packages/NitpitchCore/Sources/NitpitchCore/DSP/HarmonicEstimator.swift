import Accelerate
import Foundation

/// Measures how far each of several *known* notes is from its target, all from
/// one signal — including several sounding at once.
///
/// This is the polyphonic path MPM cannot be: `PitchDetector` finds *the*
/// period of a frame, and two simultaneous notes don't have one. But a tuner
/// with a dial per string doesn't need discovery at all — every target is known
/// from `Instrument.strings` — so the problem collapses from "what pitches are
/// here" to "how far is the energy near each expected harmonic from where it
/// should be". That's measurement, and measurement works fine on a mixture.
///
/// How: one FFT per window, and each partial's exact frequency from its **phase
/// advance** since the previous window. A bin says where a partial is to
/// ±(bin width/2) ≈ 65¢ at violin G — useless. The phase of that bin advances
/// by 2π·f·hop/rate between windows, so comparing two windows pins f to a tiny
/// fraction of a bin: sub-cent, from the same 4096-sample window MPM uses.
///
/// Per note, the estimate is the magnitude-weighted mean of its partials,
/// *skipping partials shared with another target*: in a fifth the lower note's
/// 3rd harmonic IS the upper's 2nd, and a shared partial measures the mixture,
/// not either note. Both notes keep enough unshared partials for sub-cent
/// accuracy (verified down to a 4:1 amplitude imbalance between strings).
///
/// A measurement always answers, even at an empty bin — it would happily report
/// the "frequency" of leakage and noise. Presence is therefore gated before a
/// reading is returned: real partials tower over the floor and agree with each
/// other to a few cents; leakage is buried and scattered.
///
/// Like `PitchDetector`, a class holding preallocated buffers: it runs on every
/// hop and must not allocate in the audio path.
public final class HarmonicEstimator {
    /// One note's measurement.
    public struct Reading: Equatable, Sendable {
        /// The note's estimated fundamental, in hertz.
        public let frequency: Double
        /// How well the partials agree, 0...1 — the spectral analogue of MPM's
        /// clarity, and gated the same way.
        public let agreement: Double
        /// How many partials the estimate used.
        public let partials: Int
        /// How far the strongest partial stands above the presence gate, 0...1
        /// on a log scale (0 = barely admitted, 1 = 40 dB above the gate).
        /// This is per *string*, not per frame: with two strings sounding, each
        /// reading reports its own string's strength.
        public let strength: Double
        /// Whether every partial behind the estimate sat at an even multiple
        /// of the target. That's the fingerprint of the note an octave UP:
        /// a string sounding at 2f has partials at 2f, 4f, 6f — exclusively
        /// the target's even slots — while the open string itself always
        /// brings odd evidence (3f and 5f survive even where a microphone
        /// rolls the fundamental off). Intonation checking is built on this
        /// parity: one target, and the octave recognized by what's missing.
        public let evenPartialsOnly: Bool
    }

    /// How many harmonics of each target to measure. Beyond the 6th there's
    /// rarely enough energy to help, and each extra harmonic is another chance
    /// to collide with a neighbour's.
    public static let harmonics = 6

    /// How far from its expected position a partial is searched for, in cents.
    /// Wide enough to track a string being tuned toward its target; narrow
    /// enough that a neighbouring semitone (100¢) never falls in the window.
    public static let searchCents = 60.0

    /// Two partials closer than this belong to both notes and serve neither.
    public static let collisionCents = 60.0

    /// A partial must rise this far above the spectrum's median magnitude to
    /// count as present. Real partials sit orders of magnitude above the floor;
    /// Hann leakage from another string's partials is at least ~30 dB down.
    public static let presenceFloor = 20.0

    /// The most the used partials may disagree, in cents, before the "note" is
    /// judged to be leakage rather than a sounding string. Real partials of one
    /// string agree to a couple of cents; junk scatters.
    public static let agreementCents = 10.0

    /// A reading must include a partial at or below this harmonic order. This
    /// is the guard against a neighbour's *high* harmonic masquerading in one
    /// of this string's upper slots — on a violin, G's 11th harmonic (2156 Hz)
    /// sits 35¢ from A's 5th (2200 Hz), inside the search window — because a
    /// foreign harmonic never brings a fundamental with it. A real string
    /// always sounds its own bottom.
    public static let maxAnchorHarmonic = 2

    /// Partials weaker than this fraction of the string's strongest partial
    /// are treated as absent. A partial that "corroborates" at a thousandth of
    /// the energy is a noise peak that happened to land right, not evidence.
    public static let minPartialShare = 0.05

    private let sampleRate: Double
    private let windowSize: Int
    private let hopSize: Int
    private let binHz: Double
    private let dft: vDSP_DFT_SetupD

    private var window: [Double]
    private var inReal: [Double]
    private let inImag: [Double]
    private var outReal: [Double]
    private var outImag: [Double]
    private var magnitude: [Double]
    /// Scratch for the median sort, so the audio path never allocates.
    private var sortScratch: [Double]
    private var phase: [Double]
    private var previousPhase: [Double]
    /// Median magnitude of the current spectrum — the floor presence is judged
    /// against. Recomputed per window.
    private var floor = 0.0
    /// Phase is a *difference* between windows, so the first window after a
    /// reset has nothing to compare against and `measure` must decline.
    private var windowsIngested = 0

    public init(
        sampleRate: Double,
        windowSize: Int = Detection.windowSize,
        hopSize: Int = Detection.hopSize
    ) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.hopSize = hopSize
        self.binHz = sampleRate / Double(windowSize)
        self.dft = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(windowSize), .FORWARD)!
        self.window = [Double](repeating: 0, count: windowSize)
        vDSP_hann_windowD(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
        self.inReal = [Double](repeating: 0, count: windowSize)
        self.inImag = [Double](repeating: 0, count: windowSize)
        self.outReal = [Double](repeating: 0, count: windowSize)
        self.outImag = [Double](repeating: 0, count: windowSize)
        self.magnitude = [Double](repeating: 0, count: windowSize / 2)
        self.sortScratch = [Double](repeating: 0, count: windowSize / 2)
        self.phase = [Double](repeating: 0, count: windowSize / 2)
        self.previousPhase = [Double](repeating: 0, count: windowSize / 2)
    }

    deinit {
        vDSP_DFT_DestroySetupD(dft)
    }

    /// Take in one analysis window. Consecutive windows must be `hopSize`
    /// apart — which is exactly how `AudioInput` delivers them — because the
    /// phase measurement is the *difference* between this window and the last.
    ///
    /// `measure` answers against the most recent pair; the first window after
    /// a reset has no pair yet, so `measure` returns nil until the second.
    public func ingest(_ samples: [Float]) {
        guard samples.count == windowSize else { return }
        swap(&phase, &previousPhase)

        vDSP_vspdp(samples, 1, &inReal, 1, vDSP_Length(windowSize))
        vDSP_vmulD(inReal, 1, window, 1, &inReal, 1, vDSP_Length(windowSize))
        vDSP_DFT_ExecuteD(dft, inReal, inImag, &outReal, &outImag)

        let half = windowSize / 2
        for b in 0..<half {
            magnitude[b] = sqrt(outReal[b] * outReal[b] + outImag[b] * outImag[b])
            phase[b] = atan2(outImag[b], outReal[b])
        }
        // The median as the noise floor: partials are a handful of tall bins,
        // so they can't drag the median the way they would a mean.
        sortScratch.withUnsafeMutableBufferPointer { scratch in
            magnitude.withUnsafeBufferPointer { source in
                scratch.baseAddress!.update(from: source.baseAddress!, count: half)
            }
            vDSP_vsortD(scratch.baseAddress!, vDSP_Length(half), 1)
        }
        floor = max(sortScratch[half / 2], .leastNormalMagnitude)
        windowsIngested += 1
    }

    /// Forget the previous window, e.g. after a gap in capture — comparing
    /// phases across a discontinuity would produce a confidently wrong answer.
    public func reset() {
        windowsIngested = 0
        floor = 0
    }

    /// Measure the note expected at `target` Hz, ignoring partials it shares
    /// with `others` (the remaining strings' targets). Nil when the note isn't
    /// judged to be sounding — an absent string must go dark, not report the
    /// leakage at its empty bins.
    public func measure(target: Double, others: [Double]) -> Reading? {
        guard windowsIngested >= 2, floor > 0, target > 0 else { return nil }

        var orders: [Int] = []
        var estimates: [Double] = []
        var weights: [Double] = []
        for k in 1...Self.harmonics {
            let expected = target * Double(k)
            guard expected < sampleRate / 2 * 0.9 else { break }
            if collides(expected, with: others) { continue }
            guard let (hz, mag) = partial(near: expected) else { continue }
            orders.append(k)
            estimates.append(hz / Double(k))
            weights.append(mag)
        }
        // Partials far weaker than the string's strongest aren't corroboration
        // — they're noise peaks that happened to land right.
        if let maxWeight = weights.max() {
            let cutoff = maxWeight * Self.minPartialShare
            let kept = weights.indices.filter { weights[$0] >= cutoff }
            orders = kept.map { orders[$0] }
            estimates = kept.map { estimates[$0] }
            weights = kept.map { weights[$0] }
        }
        // One partial can't corroborate itself; anything real has at least
        // two. And a reading must be anchored low: a real string sounds its
        // own bottom, while a neighbour's high harmonic masquerading in an
        // upper slot brings no fundamental with it.
        guard estimates.count >= 2, let lowest = orders.min(),
            lowest <= Self.maxAnchorHarmonic
        else { return nil }

        let total = weights.reduce(0, +)
        let mean = zip(estimates, weights).map(*).reduce(0, +) / total
        // Agreement: how tightly the partials cluster around their mean, in
        // cents. Real partials of one string agree to a couple of cents.
        let spread = estimates.map { abs(PitchMath.cents(from: mean, to: $0)) }.max() ?? 0
        guard spread <= Self.agreementCents else { return nil }

        // Strength: decades above the presence gate, so a reading that barely
        // scraped in shows weak and a bowed string shows strong. The *sum* of
        // the used partials rather than the tallest one: a low string spreads
        // its energy across several moderate partials (violin G especially),
        // and judging it by its best single partial made its bar flicker at
        // the gate while a real note was sounding. Two decades (40 dB) of
        // headroom is full.
        let gate = floor * Self.presenceFloor
        let strength = min(1, max(0, log10(total / gate) / 2))

        return Reading(
            frequency: mean,
            agreement: max(0, 1 - spread / Self.agreementCents),
            partials: estimates.count,
            strength: strength,
            evenPartialsOnly: orders.allSatisfy { $0.isMultiple(of: 2) })
    }

    /// Whether a partial at `hz` sits on any harmonic of any other target.
    private func collides(_ hz: Double, with others: [Double]) -> Bool {
        for other in others where other > 0 {
            for m in 1...Self.harmonics
            where abs(PitchMath.cents(from: other * Double(m), to: hz)) < Self.collisionCents {
                return true
            }
        }
        return false
    }

    /// The strongest present partial within `searchCents` of `expected`, its
    /// frequency pinned by phase advance. Nil when nothing there clears the
    /// presence floor.
    private func partial(near expected: Double) -> (hz: Double, mag: Double)? {
        let half = windowSize / 2
        let low = expected * pow(2, -Self.searchCents / 1200)
        let high = expected * pow(2, Self.searchCents / 1200)
        var lowBin = Int(low / binHz)
        var highBin = Int((high / binHz).rounded(.up))
        // Always at least the expected bin and a neighbour each side, or a low
        // fundamental's whole search range can round into a single bin.
        let centre = Int((expected / binHz).rounded())
        lowBin = min(lowBin, centre - 1)
        highBin = max(highBin, centre + 1)
        guard lowBin >= 1, highBin < half - 1 else { return nil }

        var best = lowBin
        for b in lowBin...highBin where magnitude[b] > magnitude[best] { best = b }
        let mag = magnitude[best]
        guard mag > floor * Self.presenceFloor else { return nil }

        // Phase advance since the previous window, unwrapped around the bin's
        // own expected advance. The residual says how far the true frequency
        // is from the bin centre — this is the sub-bin precision.
        let binFreq = Double(best) * binHz
        let expectedAdvance = 2 * .pi * binFreq * Double(hopSize) / sampleRate
        var delta = phase[best] - previousPhase[best] - expectedAdvance
        delta = (delta + .pi).truncatingRemainder(dividingBy: 2 * .pi)
        if delta < 0 { delta += 2 * .pi }
        delta -= .pi
        let hz = binFreq + delta * sampleRate / (2 * .pi * Double(hopSize))
        // The phase can only disambiguate half a hop's worth of cycles; a
        // residual putting the answer outside the searched range means the bin
        // held something else.
        guard hz >= low * 0.99, hz <= high * 1.01 else { return nil }
        return (hz, mag)
    }
}
