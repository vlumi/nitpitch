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
    /// Watches the range *above* the top string's band, and is never shown.
    ///
    /// It exists to make the subharmonic filter work for notes no dial owns.
    /// A pitch above every band — a stopped note, a wild sharp top string —
    /// is invisible to the string detectors, but its periodicity shows up in
    /// their bands at ÷2 and ÷3, and those shadows sit in a 3:2 ratio the
    /// filter can't fault: neither divides the other. A5 is the vicious case:
    /// its shadows land at A −0¢ and D −2¢, two dials reading plausibly in
    /// tune for strings that aren't sounding. The sentinel hands the filter
    /// the true fundamental, which divides both shadows and kills them.
    private var sentinel: PitchDetector?
    /// Created on first spectral use, then kept — the FFT setup and buffers
    /// are worth reusing, and an idle estimator costs nothing.
    private var estimator: HarmonicEstimator?
    /// Consecutive reading frames per string, for the confirmation rule: a
    /// dial that wasn't lit needs `tuning.confirmationFrames` agreeing frames
    /// before it lights, so a single-frame coincidence never reaches the
    /// screen.
    private var streaks: [Int]

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
        self.sentinel = Self.makeSentinel(sampleRate: sampleRate, bands: bands, tuning: tuning)
        self.streaks = Array(repeating: 0, count: targets.count)
    }

    /// The sentinel's band: from the top of the highest string's band to the
    /// top of everything searchable. Nil when there's no room left above.
    private static func makeSentinel(
        sampleRate: Double, bands: [ClosedRange<Double>], tuning: DetectionTuning
    ) -> PitchDetector? {
        guard let top = bands.map(\.upperBound).max(),
            top < Detection.fullBand.upperBound * 0.95
        else { return nil }
        return PitchDetector(
            sampleRate: sampleRate,
            band: top...Detection.fullBand.upperBound,
            tuning: tuning)
    }

    /// One analysis window in, one result per string out, in string order.
    ///
    /// A result with a nil frequency means "this string isn't sounding" — which
    /// under MPM can mean its reading was recognized as another string's
    /// subharmonic and suppressed.
    public func analyze(_ window: [Float]) -> [DetectionResult] {
        analyzeWithAbove(window).strings
    }

    /// `analyze`, plus what sounded ABOVE every band: the sentinel's
    /// reading, which normally exists only to kill subharmonic shadows and
    /// is never shown. The intonation layer is its second honest consumer —
    /// the upper strings' octaves live exactly there, above every band by
    /// construction (a band tops out a few semitones past its string).
    /// MPM frames only; the spectral engine has no detector up there.
    public func analyzeWithAbove(
        _ window: [Float]
    ) -> (strings: [DetectionResult], above: DetectionResult?) {
        lock.lock()
        defer { lock.unlock() }
        let outcome: (results: [DetectionResult], above: DetectionResult?)
        switch tuning.engine {
        case .mpm: outcome = analyzeMPM(window)
        case .spectral: outcome = (analyzeSpectral(window), nil)
        case .hybrid: outcome = analyzeHybrid(window)
        }
        return (confirmed(outcome.results), outcome.above)
    }

    /// The confirmation rule. A reading only reaches the screen once it has
    /// held for `confirmationFrames` consecutive frames; until then it's
    /// reported dark, keeping its clarity and level for the diagnostics
    /// screen. One hop of lag at first light-up, none while tracking.
    private func confirmed(_ results: [DetectionResult]) -> [DetectionResult] {
        results.enumerated().map { index, result in
            if result.frequency != nil {
                streaks[index] += 1
            } else {
                streaks[index] = 0
            }
            guard streaks[index] < tuning.confirmationFrames, result.frequency != nil else {
                return result
            }
            return DetectionResult(
                frequency: nil, clarity: result.clarity, rms: result.rms, level: result.level)
        }
    }

    /// Change thresholds or engine. Bands stay, so detectors keep their
    /// buffers — this is the slider-drag path and must stay cheap.
    public func retune(_ tuning: DetectionTuning) {
        lock.lock()
        defer { lock.unlock() }
        self.tuning = tuning
        for detector in detectors { detector.tuning = tuning }
        sentinel?.tuning = tuning
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
        self.sentinel = Self.makeSentinel(sampleRate: sampleRate, bands: bands, tuning: tuning)
        self.streaks = Array(repeating: 0, count: targets.count)
        estimator?.reset()
    }

    /// Capture stopped and restarted — the spectral engine's phase pair spans
    /// the gap otherwise and its first reading back is confidently wrong.
    public func interrupted() {
        lock.lock()
        defer { lock.unlock() }
        estimator?.reset()
        // A gap is a fresh start for confirmation too.
        streaks = Array(repeating: 0, count: targets.count)
    }

    // MARK: - Hybrid: spectral wins the frame; MPM only when it's silent

    /// Frame-level, not per string: during a double stop MPM invents ghosts on
    /// the unplayed strings (both real notes defeat it and only a subharmonic
    /// remains, with nothing higher for the filter to kill it with), so mixing
    /// the two engines within one frame would reinsert exactly the readings
    /// spectral exists to prevent. If spectral heard *anything*, its frame
    /// stands; MPM speaks only when spectral was silent — the slack-string and
    /// missing-fundamental territory where MPM is the right tool.
    private func analyzeHybrid(_ window: [Float]) -> ([DetectionResult], DetectionResult?) {
        let spectral = analyzeSpectral(window)
        if spectral.contains(where: { $0.frequency != nil }) {
            // Spectral won the frame — but it has no detector above the
            // bands, so the sentinel still answers for that territory.
            // Without this, the top strings' octaves starve on exactly the
            // instruments where spectral is healthy: a guitar always has
            // SOMETHING ringing for spectral to read, so MPM frames — the
            // sentinel's only other outing — barely happen, and B4/E5 live
            // above every band with no other route. MPM's own clarity gate
            // does the vetting up there: a real note at 2f fits its period
            // cleanly, while an open string's mere 2nd harmonic is vetoed
            // by the odd partials it drags along.
            let above = sentinel?.analyze(window)
            return (spectral, above?.frequency != nil ? above : nil)
        }
        return analyzeMPM(window)
    }

    // MARK: - MPM: N detectors, then arbitration

    private func analyzeMPM(_ window: [Float]) -> ([DetectionResult], DetectionResult?) {
        let raw = detectors.map { $0.analyze(window) }
        // Which readings are shadows of another string's reading — the "play A,
        // G lights up" bug. The filter keeps the highest of any octave chain.
        var candidates = raw.enumerated().compactMap { index, result in
            result.frequency.map { SubharmonicFilter.Candidate(id: index, frequency: $0) }
        }
        // The sentinel joins the comparison — so a note above every band still
        // kills the shadows it casts into them — but never lights a dial; its
        // id maps to no string. Its reading rides out separately for the one
        // consumer allowed to care (`analyzeWithAbove`).
        let sentinelResult = sentinel?.analyze(window)
        if let above = sentinelResult?.frequency {
            candidates.append(SubharmonicFilter.Candidate(id: -1, frequency: above))
        }
        let real = Set(SubharmonicFilter.real(among: candidates).map(\.id))
        let above = real.contains(-1) ? sentinelResult : nil
        let strings = raw.enumerated().map { index, result in
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
                level: result.displayLevel)
        }
        return (strings, above)
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
                level: reading.strength, evenPartialsOnly: reading.evenPartialsOnly)
        }
    }
}
