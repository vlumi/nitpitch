import Accelerate
import Foundation

/// All of one instrument's per-string detection, behind one call: a window in,
/// one result per string out.
///
/// This exists because the strings can't be judged independently. Every
/// detector sees the same full-spectrum signal — a band restricts which lags
/// are *searched*, not what's *heard* — so one played note shows up in several
/// detectors at once and something has to compare them against each other
/// (`SubharmonicFilter`). And the spectral engine inverts the shape entirely:
/// one FFT shared by every string. Both need a single place that owns the whole
/// frame, which per-dial subscriptions structurally cannot be.
///
/// Thread-safety: `analyze` runs on the audio analysis queue while `retune` and
/// `configure` arrive from the main actor, so everything is under one lock.
/// The DSP holds it for the duration of a frame (~1 ms); a slider tick waiting
/// that long is imperceptible.
public final class DetectorBank: @unchecked Sendable {
    private let lock = NSLock()
    private let sampleRate: Double
    private var targets: [Double]
    private var bands: [ClosedRange<Double>]
    private var tuning: DetectionTuning
    private var detectors: [PitchDetector]
    /// Created on first spectral use, then kept — the FFT setup and buffers
    /// are worth reusing, and an idle estimator costs nothing.
    private var estimator: HarmonicEstimator?

    /// `targets` and `bands` are parallel: one frequency and one band per
    /// string, as `Instrument.notes` and `Instrument.stringBands` hand out.
    public init(
        sampleRate: Double,
        targets: [Double],
        bands: [ClosedRange<Double>],
        tuning: DetectionTuning = .default
    ) {
        self.sampleRate = sampleRate
        self.targets = targets
        self.bands = bands
        self.tuning = tuning
        self.detectors = bands.map {
            PitchDetector(sampleRate: sampleRate, band: $0, tuning: tuning)
        }
    }

    /// One analysis window in, one result per string out, in string order.
    ///
    /// A result with a nil frequency means "this string isn't sounding" — which
    /// under MPM can mean its reading was recognized as another string's
    /// subharmonic and suppressed.
    public func analyze(_ window: [Float]) -> [DetectionResult] {
        lock.lock()
        defer { lock.unlock() }
        switch tuning.engine {
        case .mpm: return analyzeMPM(window)
        case .spectral: return analyzeSpectral(window)
        }
    }

    /// Change thresholds or engine. Bands stay, so detectors keep their
    /// buffers — this is the slider-drag path and must stay cheap.
    public func retune(_ tuning: DetectionTuning) {
        lock.lock()
        defer { lock.unlock() }
        self.tuning = tuning
        for detector in detectors { detector.tuning = tuning }
    }

    /// New targets or bands — the reference moved, or the band width did.
    /// Rebuilds the detectors, since a band is baked into their lag bounds.
    public func configure(
        targets: [Double], bands: [ClosedRange<Double>], tuning: DetectionTuning
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.targets = targets
        self.bands = bands
        self.tuning = tuning
        self.detectors = bands.map {
            PitchDetector(sampleRate: sampleRate, band: $0, tuning: tuning)
        }
        estimator?.reset()
    }

    /// Capture stopped and restarted — the spectral engine's phase pair spans
    /// the gap otherwise and its first reading back is confidently wrong.
    public func interrupted() {
        lock.lock()
        defer { lock.unlock() }
        estimator?.reset()
    }

    // MARK: - MPM: N detectors, then arbitration

    /// The chromatic screen's level curve: a short log-ish ramp, because RMS is
    /// tiny for quiet playing and a linear meter would sit near zero for
    /// everything but a loud bow.
    private func displayLevel(rms: Double) -> Double {
        min(1, sqrt(rms) * 3)
    }

    private func analyzeMPM(_ window: [Float]) -> [DetectionResult] {
        let raw = detectors.map { $0.analyze(window) }
        // Which readings are shadows of another string's reading — the "play A,
        // G lights up" bug. The filter keeps the highest of any octave chain.
        let candidates = raw.enumerated().compactMap { index, result in
            result.frequency.map { SubharmonicFilter.Candidate(id: index, frequency: $0) }
        }
        let real = Set(SubharmonicFilter.real(among: candidates).map(\.id))
        return raw.enumerated().map { index, result in
            guard result.frequency != nil else { return result }
            guard real.contains(index) else {
                // Suppressed: keep the clarity so the diagnostics screen can
                // still show *why* the dial is dark.
                return DetectionResult(frequency: nil, clarity: result.clarity, rms: result.rms)
            }
            // MPM analyses the whole frame, so the frame's level is the best
            // per-string strength on offer.
            return DetectionResult(
                frequency: result.frequency, clarity: result.clarity, rms: result.rms,
                level: displayLevel(rms: result.rms))
        }
    }

    // MARK: - Spectral: one FFT, every string measured from it

    private func analyzeSpectral(_ window: [Float]) -> [DetectionResult] {
        var rms: Float = 0
        vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))
        // The same silence gate MPM applies before any work: without it, a
        // quiet room's background is "measured" and every dial twitches at
        // noise. This is also what makes the debug screen's silence slider
        // mean the same thing on both engines.
        guard rms > tuning.silenceRMS else {
            // A skipped frame still breaks the phase pair — the next loud
            // window must not be compared against a window from before the
            // quiet spell.
            estimator?.reset()
            return targets.map { _ in DetectionResult(frequency: nil, clarity: 0, rms: Double(rms))
            }
        }

        let estimator =
            self.estimator
            ?? {
                let created = HarmonicEstimator(sampleRate: sampleRate)
                self.estimator = created
                return created
            }()
        estimator.ingest(window)

        return targets.indices.map { index in
            let others = targets.indices.filter { $0 != index }.map { targets[$0] }
            guard
                let reading = estimator.measure(target: targets[index], others: others)
            else {
                return DetectionResult(frequency: nil, clarity: 0, rms: Double(rms))
            }
            // The strength gate: a bowed string reads at or near full on the
            // signal bar; what the estimator scrapes off a loud frame's noise
            // sits below half. The silence gate can't separate those — while
            // anything plays, the frame is loud — but per-string strength can.
            // The dropped reading keeps its level so the diagnostics screen
            // shows the near miss.
            guard reading.strength >= tuning.spectralStrengthGate else {
                return DetectionResult(
                    frequency: nil, clarity: reading.agreement, rms: Double(rms),
                    level: reading.strength)
            }
            return DetectionResult(
                frequency: reading.frequency, clarity: reading.agreement, rms: Double(rms),
                level: reading.strength)
        }
    }
}
