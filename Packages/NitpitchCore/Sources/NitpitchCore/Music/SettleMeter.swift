import Foundation

/// The "is the STRING tuned?" verdict, as arithmetic — a different question
/// from the needle's "what pitch is sounding this instant?".
///
/// The needle stays honest per frame: bow pressure genuinely bends the
/// pitch, and smoothing that away would display a pitch that isn't
/// sounding. But the tuner's real question is about the aggregate — does
/// the reading HOLD the band — and that is answered here: in-tune frames
/// build the verdict, absence of evidence (silence, a missed reading)
/// decays it gently, and an out-of-tune excursion costs it heavily without
/// erasing it. Once given, the verdict survives wobble: only sustained
/// off-the-mark reading — what backing off a peg actually produces — takes
/// it back.
///
/// Shared by every surface that calls a string done: the focus policy's
/// settled state (`StringFocus`), and the grid's per-cell verdict.
public struct SettleMeter: Equatable, Sendable {
    /// Net frames of in-tune evidence before the verdict lands (~1.5 s of
    /// clean reading at the ~21.5 Hz frame rate; wobble stretches it).
    public static let settledFrames = 32
    /// Consecutive out-of-tune readings before a settled string is
    /// un-called (~0.4 s): backing the peg off is sustained evidence, a
    /// bow wobble is a frame or two — the green must outlive its own
    /// announcement.
    public static let unsettleFrames = 8
    /// What one out-of-tune reading costs the building verdict. A reset was
    /// too harsh for a bowed string: uneven bow pressure bends the pitch
    /// past the band for a frame or two, over and over, and every excursion
    /// restarted the count from zero (field-found on a violin). Four means
    /// in-tune evidence must outnumber wobble four to one to net forward —
    /// a genuinely borderline string, half in and half out, never settles.
    public static let outOfTuneDecay = 4

    public private(set) var isSettled = false

    private var inTuneStreak = 0
    private var outOfTuneStreak = 0

    public init() {}

    /// One frame's evidence: a confirmed reading in or out of the band, or
    /// nil for no verdict at all (silence, a missed frame, a note
    /// attributed to the string without a tuning reading). Returns true
    /// exactly when this frame settles the string — the announcement, once
    /// per genuine settling, never on a hover around the threshold.
    public mutating func ingest(inTune: Bool?) -> Bool {
        switch inTune {
        case true?:
            outOfTuneStreak = 0
            // Capped so "settled and still playing" never banks surplus
            // evidence: after a genuine un-settle the verdict must be
            // re-earned from zero, not resumed from a hoard.
            inTuneStreak = min(Self.settledFrames, inTuneStreak + 1)
            if inTuneStreak >= Self.settledFrames, !isSettled {
                isSettled = true
                return true
            }
        case false?:
            inTuneStreak = max(0, inTuneStreak - Self.outOfTuneDecay)
            outOfTuneStreak += 1
            if outOfTuneStreak >= Self.unsettleFrames { isSettled = false }
        case nil:
            // Absence of evidence: both streaks decay rather than reset —
            // the same mercy the focus policy's rival streaks needed on a
            // bass reading intermittently through a small microphone.
            inTuneStreak = max(0, inTuneStreak - 1)
            outOfTuneStreak = max(0, outOfTuneStreak - 1)
        }
        return false
    }

    /// Fresh work: the target moved, or the screen did.
    public mutating func reset() {
        isSettled = false
        inTuneStreak = 0
        outOfTuneStreak = 0
    }
}
