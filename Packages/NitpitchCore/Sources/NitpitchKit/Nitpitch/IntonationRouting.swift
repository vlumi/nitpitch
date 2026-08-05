import Foundation
import NitpitchCore

/// Decides, per frame, what the string screen's two tuners each get to see —
/// pure, so the rule is testable as arithmetic.
///
/// Two classifiers, because each catches what the other can't:
///
/// - **Parity** (the analyzer): spectral frames where the fretted octave
///   masquerades as the open string — the estimator accepts 2nd-harmonic
///   anchors by design, so the bank reads a fretted 12th as ≈0¢ on the open
///   target. Parity is the only thing that unmasks it.
/// - **Proximity** (here): frames where the *bank* found the octave itself —
///   MPM reading 2f whenever spectral failed its gates, which on a bass is
///   often (a 55 Hz fundamental spans one FFT bin). Parity is silent on
///   exactly those frames, because the analyzer's spectral gates failed
///   too — same math. Without this rule, every such frame slammed the main
///   dial to +1200.
///
/// Anything within the window of +1200¢ IS the octave on this screen: the
/// fretted 12th, the fingered octave, the natural harmonic, or the open
/// string's own second partial ringing through an MPM octave error — every
/// one of them is octave-slot information, and none of them is a string
/// someone tuned an octave sharp.
enum IntonationRouting {
    /// How far from +1200¢ a reading may sit and still be the octave. Wide
    /// enough for a badly set saddle and a slack-ish string; nothing
    /// legitimate lives between +150¢ and +1050¢ on a single-string screen
    /// except other strings, which pin the dial by design.
    static let octaveWindowCents = 150.0

    /// What the main dial ingests, and what the intonation monitor does.
    /// `dial` is the bank's result, silenced when the frame turned out to be
    /// the octave's business; `intonation` is the analyzer's frame, or a
    /// synthesized octave frame when proximity spoke and parity couldn't.
    static func route(
        result: DetectionResult, frame: IntonationAnalyzer.Frame?, target: Double
    ) -> (dial: DetectionResult, intonation: IntonationAnalyzer.Frame?) {
        if let frame, frame.soundsOctave {
            return (silenced(result), frame)
        }
        if let cents = octaveCents(in: result, target: target) {
            return (
                silenced(result),
                IntonationAnalyzer.Frame(
                    sounding: .note(
                        slot: .octave, cents: cents, clarity: result.clarity),
                    level: result.displayLevel)
            )
        }
        return (result, frame)
    }

    /// The reading's deviation from 2f, when the reading is the octave —
    /// nil when it isn't. The same scale the analyzer uses, so the two
    /// sources feed one smoother without a seam.
    private static func octaveCents(
        in result: DetectionResult, target: Double
    ) -> Double? {
        guard let hz = result.frequency, target > 0 else { return nil }
        let cents = 1200 * log2(hz / target)
        guard abs(cents - 1200) <= octaveWindowCents else { return nil }
        return cents - 1200
    }

    /// The dial's share of an octave frame: no reading — this screen's
    /// promise is "how far is the OPEN string" — but the frame's clarity
    /// and level kept for the diagnostics screen.
    private static func silenced(_ result: DetectionResult) -> DetectionResult {
        DetectionResult(frequency: nil, clarity: result.clarity, rms: result.rms)
    }
}
