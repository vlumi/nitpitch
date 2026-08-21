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

    /// The 3rd harmonic sits at 3·f = +1902¢. MPM reports it as exactly
    /// that — a note at 3f IS a note, and the harmonic FOLDING lives only
    /// in the spectral path (the lens; see `DetectorBank`), so an
    /// MPM-carried frame reached the dial as "the open string, nineteen
    /// hundred cents sharp" (field-found: every string, most of the time,
    /// while touching the 7th-fret node — a real harmonic is quieter and
    /// less clean than a bowed note, so spectral often reads nothing and
    /// the hybrid falls through to MPM).
    ///
    /// Folded here rather than in the bank, for the same reason the octave
    /// is: the bank answers "what is sounding", and only this screen knows
    /// that everything it hears is meant to BE this one string. The window
    /// is tight — a harmonic is a physical ratio, not a tuning error — and
    /// deliberately tighter than the octave's: the guitar's own 3:1
    /// coincidences (E2's 3f IS the open B) mean a wide window would
    /// swallow a neighbour being played.
    static let thirdHarmonicCents = 1902.0
    static let thirdHarmonicWindowCents = 60.0

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
        // A 3rd harmonic MPM found: fold it onto the string, the way the
        // spectral lens would have. The error IS the string's own — the
        // partial sits at 3·f, so its deviation from 3·f is f's from f.
        if let folded = thirdHarmonicFolded(result, target: target) {
            return (folded, frame)
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

    /// The same reading with its frequency divided back onto the string,
    /// when it sits at the 3rd harmonic — nil when it doesn't. Labelled
    /// `harmonic: 3` so the readout says WHY it reads D3 while the ear
    /// hears A4, exactly as the spectral lens's own frames do.
    private static func thirdHarmonicFolded(
        _ result: DetectionResult, target: Double
    ) -> DetectionResult? {
        guard let hz = result.frequency, target > 0 else { return nil }
        let cents = 1200 * log2(hz / target)
        guard abs(cents - thirdHarmonicCents) <= thirdHarmonicWindowCents else {
            return nil
        }
        return DetectionResult(
            frequency: hz / 3, clarity: result.clarity, rms: result.rms,
            level: result.level, evenPartialsOnly: false, harmonic: 3)
    }

    /// The dial's share of an octave frame: no reading — this screen's
    /// promise is "how far is the OPEN string" — but the frame's clarity
    /// and level kept for the diagnostics screen.
    private static func silenced(_ result: DetectionResult) -> DetectionResult {
        DetectionResult(frequency: nil, clarity: result.clarity, rms: result.rms)
    }
}
