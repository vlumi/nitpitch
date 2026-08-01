import Foundation

/// Tuning constants for the detector, in one place so they can be reasoned
/// about together rather than scattered as literals.
public enum Detection {
    /// The widest band any instrument searches: E1 (41 Hz, bass low string, with
    /// headroom below) up to well past a violin's stopped high notes.
    public static let fullBand: ClosedRange<Double> = 38...2100

    /// Analysis window, in samples, at 44.1 kHz.
    ///
    /// 4096 samples is ~93 ms — enough to hold about 4 periods of a bass low E
    /// (41 Hz) and many of a violin E5, which is what MPM needs for a stable
    /// estimate. Smaller windows track faster but get unreliable at the bottom
    /// of the range; this is the trade-off point that keeps one window usable
    /// for every supported instrument.
    public static let windowSize = 4096

    /// Hop between analyses, in samples: 50% overlap, so ~21 updates/second.
    /// Faster than the eye needs, which leaves room for the display smoothing.
    public static let hopSize = 2048

    /// Minimum normalized-autocorrelation peak to accept an estimate.
    ///
    /// Below this the frame is bow noise, a room reflection, or silence between
    /// notes. Gating on clarity rather than showing every frame is what stops
    /// the readout flickering nonsense — the UI shows "listening" instead.
    public static let clarityThreshold = 0.9

    /// The fraction of the highest NSDF peak a candidate must reach to be
    /// chosen instead. Below 1.0 so that when a lower-lag (higher-octave) peak
    /// merely ties the true fundamental's, the fundamental still wins — this is
    /// the octave-error guard that plain FFT peak-picking lacks.
    public static let peakPickThreshold = 0.9

    /// RMS below which the frame is treated as silence and skipped outright,
    /// before any DSP. Roughly -60 dBFS.
    public static let silenceRMS: Float = 0.001
}

/// One analysis result: a frequency estimate and how much to trust it.
public struct DetectionResult: Equatable, Sendable {
    /// Estimated fundamental in hertz, or nil when the frame was rejected.
    public let frequency: Double?
    /// Normalized peak height, 0...1 — the clarity/periodicity measure.
    public let clarity: Double
    /// Root-mean-square level of the frame, for a signal-strength meter.
    public let rms: Double

    public init(frequency: Double?, clarity: Double, rms: Double) {
        self.frequency = frequency
        self.clarity = clarity
        self.rms = rms
    }

    public static let silent = DetectionResult(frequency: nil, clarity: 0, rms: 0)
}
