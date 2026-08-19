import Foundation

/// Tuning constants for the detector, in one place so they can be reasoned
/// about together rather than scattered as literals.
public enum Detection {
    /// The widest band any instrument searches: from below a 5-string bass's
    /// B0 (30.9 Hz) — which also covers bass drop D at 36.7 Hz — up to well
    /// past a violin's stopped high notes. The floor is a detection-quality
    /// line, not a hard one: the 4096-sample window holds ~2.8 periods of
    /// 30 Hz, which MPM still resolves, but not much below that.
    public static let fullBand: ClosedRange<Double> = 30...2100

    /// MIDI notes whose frequency stays inside `fullBand` at any offered
    /// reference — the range string targets may occupy, shared by the target
    /// stepper's clamp and the string-count extension rule. The floor is B0
    /// (23 ≈ 30.9 Hz), a 5-string bass's low string.
    public static let targetMIDIRange = 23...95

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
    /// Display-ready strength of *this* reading, 0...1: how much signal stands
    /// behind the number. Zero whenever `frequency` is nil — no reading, no
    /// authority. The spectral engine fills it per string from that string's
    /// own partials; MPM has only the whole frame to go on.
    public let level: Double
    /// The estimate's parity fingerprint, carried up from
    /// `HarmonicEstimator.Reading`: every partial behind it sat at an even
    /// multiple of the target, which is what a note an OCTAVE UP looks like
    /// through this target's slots (the open string always brings odd
    /// evidence). Spectral frames only — MPM measures a period, not
    /// partials, and always reports false.
    public let evenPartialsOnly: Bool
    /// Which harmonic of the string best explains the sound: 1 for the open
    /// string, 2 for the octave (the parity fingerprint), 3/4 when a
    /// harmonic lens made the read (`DetectorBank`). The error is the
    /// string's either way — this exists so the display can say WHY it
    /// shows D2 while the ear hears D4.
    public let harmonic: Int

    public init(
        frequency: Double?, clarity: Double, rms: Double, level: Double = 0,
        evenPartialsOnly: Bool = false, harmonic: Int = 1
    ) {
        self.frequency = frequency
        self.clarity = clarity
        self.rms = rms
        self.level = level
        self.evenPartialsOnly = evenPartialsOnly
        self.harmonic = harmonic
    }

    public static let silent = DetectionResult(frequency: nil, clarity: 0, rms: 0)

    /// A frame the detector REJECTED: no frequency, no authority — only the
    /// clarity and level it was judged on, which the diagnostics screen
    /// still shows.
    public static func rejected(
        clarity: Double, rms: Double, level: Double = 0
    ) -> DetectionResult {
        DetectionResult(frequency: nil, clarity: clarity, rms: rms, level: level)
    }

    /// The frame's RMS as a 0...1 meter value — `Detection.displayLevel`.
    public var displayLevel: Double {
        Detection.displayLevel(rms: rms)
    }
}

extension Detection {
    /// An RMS as a 0...1 meter value: a short log-ish curve, because RMS is
    /// tiny for quiet playing and a linear meter would sit near zero for
    /// everything but a loud bow. The one curve every meter in the app
    /// uses, so they all agree about how loud "loud" looks.
    public static func displayLevel(rms: Double) -> Double {
        min(1, sqrt(rms) * 3)
    }
}
