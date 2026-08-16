import Foundation

/// What the demo "plays": a looping sequence of held voices.
///
/// The score is the ONLY demo-specific knowledge in the app. It renders to an
/// audio signal and the real pipeline does the rest — so a score can't show
/// anything the microphone couldn't, which is the point.
public struct DemoScore: Equatable, Sendable {
    public struct Voice: Equatable, Sendable {
        /// MIDI note plus a cent offset, resolved against A=440 equal
        /// temperament — absolute pitch, deliberately independent of the
        /// app's reference setting, so a pose means the same thing whatever
        /// the staged screen sets.
        public let midi: Int
        public let cents: Double

        public var frequency: Double {
            PitchMath.frequency(midi: Double(midi) + cents / 100)
        }
    }

    public struct Step: Equatable, Sendable {
        public let voices: [Voice]
        /// nil = hold this step forever (it must be the last).
        public let duration: Double?
    }

    public let steps: [Step]

    /// What plays with no `-demo-pose`: a 3.2-second loop that keeps every
    /// live element of every screen fed — an open G a touch flat (a string
    /// dial, the strobe, an intonation OPEN sample), its octave (the
    /// intonation delta, the grid's octave layer, arriving through the real
    /// routing), then a D+A fifth with the upper voice 1.8¢ low (the
    /// interval chip beating at ~2/s). The UI tests that wait for those
    /// elements allow 5 seconds, and the worst case — entering a screen just
    /// as the element it needs stops sounding — must land a full capture
    /// (six stable frames, ~0.3 s) inside that; a longer loop flakes.
    ///
    /// The G phase is 0.9 s — one frame OVER `StringFocus.switchFrames`
    /// (~0.85 s), so the watch's hands-free focus visibly walks back to the
    /// G string each loop instead of sticking wherever the pair left it.
    public static let drift = parse("0.9:55@-1.6;0.8:67@5.8;1.6:62,69@-1.8")!

    /// `-demo-pose` syntax: steps separated by `;`, each `[seconds:]voices`,
    /// voices comma-separated as `midi[@cents]`.
    ///
    ///   "69@2"                  one A4, 2¢ sharp, held forever
    ///   "1:55@-1.6;67@5.8"      open G for a second, then its octave held
    ///
    /// A step without a duration holds forever and must be last; when every
    /// step has one, the sequence loops. Returns nil for anything it can't
    /// read completely — a screenshot session on a mistyped pose should
    /// refuse, not drift.
    public static func parse(_ pose: String) -> DemoScore? {
        var steps: [Step] = []
        let parts = pose.split(separator: ";")
        guard !parts.isEmpty else { return nil }
        for (index, part) in parts.enumerated() {
            var body = part.trimmingCharacters(in: .whitespaces)
            var duration: Double?
            if let colon = body.firstIndex(of: ":") {
                guard let seconds = Double(body[..<colon]), seconds > 0 else { return nil }
                duration = seconds
                body = String(body[body.index(after: colon)...])
            } else {
                guard index == parts.count - 1 else { return nil }
            }
            var voices: [Voice] = []
            for spec in body.split(separator: ",") {
                let fields = spec.split(separator: "@", omittingEmptySubsequences: false)
                guard fields.count <= 2, let midi = Int(fields[0]),
                    Detection.targetMIDIRange.contains(midi)
                else { return nil }
                let cents = fields.count == 2 ? Double(fields[1]) : 0
                guard let cents, abs(cents) <= 100 else { return nil }
                voices.append(Voice(midi: midi, cents: cents))
            }
            guard !voices.isEmpty, voices.count <= 2 else { return nil }
            steps.append(Step(voices: voices, duration: duration))
        }
        return DemoScore(steps: steps)
    }
}

/// Renders a `DemoScore` as a continuous sample stream — a stand-in
/// instrument, not a display driver.
///
/// Two properties the detectors depend on, kept deliberately:
/// - **Phase continuity.** Each voice accumulates one running phase and its
///   harmonics ride at integer multiples of it, so frequency changes are
///   chirps, never discontinuities — the spectral engine measures phase
///   advance BETWEEN windows, and a seam would read as garbage.
/// - **Harmonics at all.** Real strings put energy above the fundamental
///   (that's the octave-error problem the detector exists to solve), so the
///   voices do too, rather than handing the DSP a flattering pure sine.
public struct DemoSignal {
    private let score: DemoScore
    private let sampleRate: Double

    private var stepIndex = 0
    private var samplesIntoStep = 0
    private var clock = 0.0

    /// Two voice slots (a double stop is the most any score holds): running
    /// phase, smoothed amplitude, current frequency.
    private var theta = [0.0, 0.0]
    private var amplitude = [0.0, 0.0]
    private var frequency = [440.0, 440.0]

    /// Relative harmonic weights — fundamental-heavy but honest, and SIX of
    /// them, as many as the spectral engine measures: strings tuned in
    /// fifths share most of their low partials (D's 3rd is A's 2nd, D's 2nd
    /// is G's 3rd…) and shared partials are discarded as evidence, so a
    /// shorter voice leaves a violin's strings too few unshared partials to
    /// corroborate a reading. Real strings carry these; the stand-in must.
    private static let harmonics = [1.0, 0.5, 0.3, 0.18, 0.12, 0.08]
    /// Per-voice gain: two voices at full tremolo stay well under 1.
    private static let gain = 0.18
    /// Amplitude eases over ~20 ms so a voice entering or leaving is a small
    /// swell, not a click.
    private var amplitudeEase: Double { 1 - exp(-1 / (0.02 * sampleRate)) }

    public init(score: DemoScore, sampleRate: Double) {
        self.score = score
        self.sampleRate = sampleRate
    }

    public mutating func render(count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let ease = amplitudeEase
        for i in 0..<count {
            let step = score.steps[stepIndex]
            if let duration = step.duration,
                samplesIntoStep >= Int(duration * sampleRate)
            {
                stepIndex = (stepIndex + 1) % score.steps.count
                samplesIntoStep = 0
            }
            let voices = score.steps[stepIndex].voices

            // The meter breathes a little, like a held note does.
            let tremolo = 1 + 0.15 * sin(2 * .pi * 0.4 * clock)
            var sample = 0.0
            for slot in 0..<2 {
                let target = slot < voices.count ? Self.gain : 0.0
                if slot < voices.count { frequency[slot] = voices[slot].frequency }
                amplitude[slot] += (target - amplitude[slot]) * ease
                guard amplitude[slot] > 0.0001 else { continue }
                theta[slot] += 2 * .pi * frequency[slot] / sampleRate
                for (h, weight) in Self.harmonics.enumerated() {
                    sample += amplitude[slot] * weight * sin(Double(h + 1) * theta[slot])
                }
            }
            out[i] = Float(sample * tremolo)
            samplesIntoStep += 1
            clock += 1 / sampleRate
        }
        return out
    }
}
