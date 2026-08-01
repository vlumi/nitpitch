import Accelerate
import Foundation

/// Pitch detection by the McLeod Pitch Method (MPM): a normalized square
/// difference function (NSDF) over the frame, then peak-picking with parabolic
/// interpolation.
///
/// Why MPM rather than an FFT peak: bowed and plucked strings put more energy in
/// harmonics than in the fundamental, so the tallest FFT bin is routinely the
/// 2nd or 3rd harmonic — an octave error, the classic tuner bug. The NSDF is
/// normalized so the *fundamental* period gives the highest peak regardless of
/// harmonic content, and `Detection.peakPickThreshold` biases ties toward the
/// lower frequency. Cent-level resolution comes from interpolating the peak,
/// not from FFT bin width, so a 4096-sample window resolves well under a cent
/// without a multi-second buffer.
///
/// The type is a class holding preallocated scratch buffers: it runs on every
/// hop (~21×/second) and must not allocate in the audio path.
public final class PitchDetector {
    private let sampleRate: Double
    private let windowSize: Int
    /// Lag bounds derived from the searched band — outside these the NSDF isn't
    /// even evaluated, which both saves work and removes whole classes of
    /// spurious peaks (DC drift at long lags, hiss at short ones).
    private let minLag: Int
    private let maxLag: Int

    private var nsdf: [Double]
    private var windowed: [Double]
    /// `windowed` followed by `maxLag + 1` zeros. vDSP_convD reads
    /// `filterLength + resultLength - 1` samples from the signal, so correlating
    /// out to `maxLag` needs that much padding or it reads past the buffer and
    /// returns garbage for the longest lags (the low notes).
    private var padded: [Double]
    private var correlation: [Double]

    public init(
        sampleRate: Double,
        windowSize: Int = Detection.windowSize,
        band: ClosedRange<Double> = Detection.fullBand
    ) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        // Lag and frequency are inverse: the highest frequency is the shortest
        // lag. Two samples of headroom below the band's shortest lag, because
        // the scan below needs to see the peak's rising side to recognize it —
        // starting exactly at the peak makes the fundamental invisible and the
        // first peak found is then its octave. Clamp to at least 2 so parabolic
        // interpolation always has a neighbour on each side.
        self.minLag = max(2, Int(sampleRate / band.upperBound) - 2)
        // The NSDF is only meaningful out to half the window (beyond that too
        // few samples overlap for the correlation to mean anything).
        self.maxLag = min(windowSize / 2, Int(sampleRate / band.lowerBound))
        self.nsdf = [Double](repeating: 0, count: windowSize / 2 + 1)
        self.windowed = [Double](repeating: 0, count: windowSize)
        self.padded = [Double](repeating: 0, count: windowSize + self.maxLag + 1)
        self.correlation = [Double](repeating: 0, count: self.maxLag + 1)
    }

    /// Analyse one frame. `samples` must be exactly `windowSize` long.
    public func analyze(_ samples: [Float]) -> DetectionResult {
        guard samples.count == windowSize, maxLag > minLag else { return .silent }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(windowSize))
        // Reject silence before doing any real work — most frames between notes
        // are this, and the NSDF of near-zero input is numerically meaningless.
        guard rms > Detection.silenceRMS else {
            return DetectionResult(frequency: nil, clarity: 0, rms: Double(rms))
        }

        vDSP_vspdp(samples, 1, &windowed, 1, vDSP_Length(windowSize))
        // Remove DC before correlating: a bias offset adds a constant to every
        // lag, flattening the NSDF and depressing clarity.
        var mean = 0.0
        vDSP_meanvD(windowed, 1, &mean, vDSP_Length(windowSize))
        var negMean = -mean
        vDSP_vsaddD(windowed, 1, &negMean, &windowed, 1, vDSP_Length(windowSize))

        computeNSDF()

        guard let (lag, value) = pickPeak() else {
            return DetectionResult(frequency: nil, clarity: 0, rms: Double(rms))
        }
        guard value >= Detection.clarityThreshold else {
            return DetectionResult(frequency: nil, clarity: value, rms: Double(rms))
        }
        return DetectionResult(
            frequency: sampleRate / lag, clarity: value, rms: Double(rms))
    }

    /// The normalized square difference function, per McLeod & Wyvill:
    ///
    ///     nsdf(τ) = 2·r(τ) / m(τ)
    ///
    /// where `r(τ)` is the autocorrelation at lag τ and `m(τ)` the sum of
    /// squares of both overlapping halves. The normalization is the whole point:
    /// it puts every peak on a 0...1 scale where 1 is perfect periodicity, so
    /// one absolute clarity threshold works across instruments and levels.
    private func computeNSDF() {
        let n = windowSize
        // Autocorrelation for every lag in one call. vDSP_convD slides the
        // filter (the un-padded frame) along the signal, so with the signal
        // zero-padded by maxLag the k-th output is exactly
        // Σ x[i]·x[i+k] — the autocorrelation. Without the padding it reads
        // past the frame and the long lags come back as noise.
        for i in 0..<n { padded[i] = windowed[i] }
        for i in n..<padded.count { padded[i] = 0 }

        padded.withUnsafeBufferPointer { signal in
            windowed.withUnsafeBufferPointer { filter in
                correlation.withUnsafeMutableBufferPointer { out in
                    vDSP_convD(
                        signal.baseAddress!, 1, filter.baseAddress!, 1, out.baseAddress!, 1,
                        vDSP_Length(maxLag + 1), vDSP_Length(n))
                }
            }
        }

        // m(τ) via the standard recurrence: starting from 2·r(0) (all samples
        // counted twice), each step drops the two samples that fall out of the
        // overlap. O(maxLag) instead of O(n·maxLag).
        var m = 2 * correlation[0]
        nsdf[0] = m > 0 ? 1 : 0
        for tau in 1...maxLag {
            m -= windowed[tau - 1] * windowed[tau - 1]
            m -= windowed[n - tau] * windowed[n - tau]
            nsdf[tau] = m > 0 ? 2 * correlation[tau] / m : 0
        }
    }

    /// Pick the fundamental's peak.
    ///
    /// Walks the NSDF collecting the maximum of each positive-going region, then
    /// takes the FIRST — that is, shortest-lag — peak whose height clears
    /// `peakPickThreshold × globalMax`.
    ///
    /// Shortest-lag-that-qualifies is what resolves octave ambiguity. A periodic
    /// signal also repeats at every multiple of its period, so the NSDF peaks
    /// again at 2×, 3× the true lag, often just as high. Taking the tallest peak
    /// would pick one of those arbitrarily and report an octave (or two) too low;
    /// taking the earliest peak that comes *close enough* to the tallest picks
    /// the true period, which is the shortest one. The threshold being below 1.0
    /// is what makes "close enough" work when a later multiple edges it out.
    private func pickPeak() -> (lag: Double, value: Double)? {
        var bestInRegion = -1
        var globalMax = 0.0
        var candidates: [Int] = []

        var tau = minLag
        // Skip the initial descent from nsdf(0) = 1 — that slope is the frame
        // correlating with itself, not a period. Advance only while the function
        // is still falling, so a peak that begins right at minLag is kept; a
        // blanket "skip everything positive" would swallow the fundamental
        // whenever the searched band starts near it, leaving the octave as the
        // first candidate.
        while tau < maxLag, nsdf[tau + 1] < nsdf[tau] { tau += 1 }

        while tau < maxLag {
            if nsdf[tau] > 0 {
                if bestInRegion < 0 || nsdf[tau] > nsdf[bestInRegion] { bestInRegion = tau }
            } else if bestInRegion >= 0 {
                // Region closed at the zero crossing — record its maximum.
                candidates.append(bestInRegion)
                globalMax = max(globalMax, nsdf[bestInRegion])
                bestInRegion = -1
            }
            tau += 1
        }
        if bestInRegion >= 0 {
            candidates.append(bestInRegion)
            globalMax = max(globalMax, nsdf[bestInRegion])
        }
        guard globalMax > 0 else { return nil }

        let cutoff = globalMax * Detection.peakPickThreshold
        guard let chosen = candidates.first(where: { nsdf[$0] >= cutoff }) else { return nil }
        return interpolate(around: chosen)
    }

    /// Fit a parabola through the peak and its two neighbours to find the true
    /// maximum between samples.
    ///
    /// Without this the estimate is quantized to integer lags, which at violin
    /// E5 (659 Hz, lag ≈ 67) is a ~26-cent step — useless for tuning. With it,
    /// resolution is well under a cent across the range.
    private func interpolate(around tau: Int) -> (lag: Double, value: Double) {
        guard tau > 0, tau < maxLag else { return (Double(tau), nsdf[tau]) }
        let y0 = nsdf[tau - 1], y1 = nsdf[tau], y2 = nsdf[tau + 1]
        // Vertex of the parabola through (tau-1, y0), (tau, y1), (tau+1, y2).
        // The denominator is (y0 - 2·y1 + y2), negative at a maximum; inverting
        // its sign reflects the estimate about the sample and biases every
        // reading — badly at high frequencies, where half a lag is a large
        // fraction of the period.
        let denom = y0 - 2 * y1 + y2
        // Degenerate (flat or a perfectly symmetric plateau): keep the integer lag.
        guard abs(denom) > .ulpOfOne else { return (Double(tau), y1) }
        let shift = 0.5 * (y0 - y2) / denom
        return (Double(tau) + shift, y1 - 0.25 * (y0 - y2) * shift)
    }
}
