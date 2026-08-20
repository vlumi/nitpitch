import Foundation

/// Which string owns the screen, for hands-free one-string-at-a-time tuning.
///
/// The display stays PINNED to one string — a tuner that jumps to whatever
/// sounded last is useless mid-adjustment, when a hand crossing the strings
/// brushes a neighbour every few seconds. Focus moves for exactly three
/// reasons, in order of authority:
///
/// 1. **An explicit pick** (`select`) — the crown, a tap. Instant, always.
/// 2. **Deliberate play**: a DIFFERENT string sounding *sustained* — a brush
///    is brief by nature, a string plucked to be tuned rings. Duration is
///    the honest discriminator, so the rival must hold for `switchFrames`.
/// 3. **The settled advance** — the hands-free heart: once the focused
///    string has held in tune for `settledFrames`, it is marked done, and
///    the switching threshold drops to `switchFramesSettled`: moving on is
///    now the expected act, so the next string to speak takes the screen
///    almost immediately. One policy, asymmetric by intent.
///
/// Pure state machine, one `ingest` per analysis frame (~21/s): everything
/// it knows arrives as arguments, so every rule above is pinned by scripted
/// sequences in `StringFocusTests`.
public struct StringFocus: Sendable {
    /// What just happened, for the screen and the wrist (haptics): a focus
    /// change is a click, settling is a success tap.
    public enum Event: Equatable, Sendable {
        case none
        /// Focus moved here — by inference; `select` reports nothing, the
        /// user's own act needs no echo.
        case focused(Int)
        /// The focused string has held in tune long enough to call done.
        case settled
    }

    /// Frames of continuous in-tune reading before the focused string counts
    /// as done (~1.5 s at the ~21.5 Hz frame rate).
    public static let settledFrames = 32
    /// Consecutive out-of-tune READINGS before a settled string is un-called
    /// (~0.4 s). Backing the peg off is sustained evidence; the single
    /// wobble frame a decaying pluck throws right after the settle haptic is
    /// not — the green must outlive the announcement it just made
    /// (field-found on a bass: the wrist buzzed success and never showed
    /// green, the verdict dying the very next frame).
    public static let unsettleFrames = 8
    /// Frames a rival string must sustain to take focus while the focused
    /// string is still being worked on (~0.85 s — longer than any brush).
    public static let switchFrames = 18
    /// The same, once the focused string has settled (~0.25 s — you are
    /// moving on, the screen should already be there).
    public static let switchFramesSettled = 5

    /// A non-qualifying frame DECAYS a rival's streak instead of resetting
    /// it: a marginal low string (a bass A through a wrist microphone)
    /// reads intermittently, and a single missed frame was zeroing an
    /// almost-complete streak — the string could never take the screen
    /// (field-found). Gentle by design: even a 2-frames-in-3 reader must
    /// still NET forward. A ring never accumulates anyway (it fails the
    /// level bar every frame), and a stopped rival drains back to zero in
    /// under a second.
    public static let rivalStreakDecay = 1

    /// The share of the focused string's recent peak strength a rival's
    /// reading must carry to count toward a switch. Duration alone is not
    /// enough: on a bass with the other strings unmuted, plucking E rings D
    /// sympathetically — a genuine, sustained reading that outlives the
    /// pluck and was stealing the screen (field-found). A deliberately
    /// played string arrives at comparable strength; a sympathetic ring is
    /// well below it.
    public static let rivalLevelShare = 0.6
    /// How the remembered peak fades per frame once the focused string goes
    /// quiet (half in ~6 s): long enough that a ring dies before the bar
    /// drops to its level, short enough that a quiet-but-deliberate player
    /// is never locked out.
    public static let peakDecayPerFrame = 0.995

    public private(set) var focusIndex: Int
    public private(set) var isSettled = false

    private let stringCount: Int
    private var inTuneStreak = 0
    private var outOfTuneStreak = 0
    /// Consecutive qualifying frames per rival string.
    private var rivalStreaks: [Int]
    /// The focused string's recent peak strength — the bar rivals are
    /// measured against, fading while the focused string is silent.
    private var focusPeak = 0.0

    public init(stringCount: Int, initialIndex: Int = 0) {
        self.stringCount = max(1, stringCount)
        self.focusIndex = initialIndex.clamped(to: 0...(self.stringCount - 1))
        self.rivalStreaks = Array(repeating: 0, count: self.stringCount)
    }

    /// The explicit pick: instant, and a fresh start — the new string is
    /// un-settled work whatever its state was a moment ago.
    public mutating func select(_ index: Int) {
        guard (0..<stringCount).contains(index) else { return }
        focus(on: index)
    }

    /// One analysis frame: each string's reading strength (nil when it
    /// isn't sounding — the per-string bank's confirmed readings), and
    /// whether the focused string's reading is in tune — nil when it isn't
    /// sounding. Returns what the screen should announce.
    public mutating func ingest(levels: [Double?], focusedInTune: Bool?) -> Event {
        guard levels.count == stringCount else { return .none }

        // The focused string speaking is the user working: rivals reset —
        // a brush ALONGSIDE the note being tuned is the most common brush
        // of all, and it must never accumulate toward a switch.
        if let focusedLevel = levels[focusIndex] {
            focusPeak = max(focusPeak, focusedLevel)
            for index in rivalStreaks.indices where index != focusIndex {
                rivalStreaks[index] = 0
            }
            switch focusedInTune {
            case true?:
                outOfTuneStreak = 0
                inTuneStreak += 1
                if inTuneStreak >= Self.settledFrames, !isSettled {
                    isSettled = true
                    return .settled
                }
            case false?:
                // A confirmed reading OFF the mark is real evidence both
                // ways: the settle streak restarts, and enough of it in a
                // row un-calls "done" — backing off the peg is sustained,
                // a decay wobble is a frame or two.
                inTuneStreak = 0
                outOfTuneStreak += 1
                if outOfTuneStreak >= Self.unsettleFrames { isSettled = false }
            case nil:
                // Sounding with no verdict — a gate flutter, the intonation
                // analyzer vouching for the string's own octave: absence of
                // evidence. The streak decays instead of restarting, the
                // same mercy the rival streaks needed on a bass reading
                // intermittently through a small microphone.
                inTuneStreak = max(0, inTuneStreak - 1)
            }
            return .none
        }

        // Silence on the focused string: streaks of QUALIFYING rivals grow
        // (strong enough against the fading peak to be deliberate play, not
        // a sympathetic ring), the in-tune streak decays as above, and
        // isSettled holds — quiet is not un-tuning.
        inTuneStreak = max(0, inTuneStreak - 1)
        outOfTuneStreak = 0
        focusPeak *= Self.peakDecayPerFrame
        let bar = focusPeak * Self.rivalLevelShare
        let threshold = isSettled ? Self.switchFramesSettled : Self.switchFrames
        for index in rivalStreaks.indices where index != focusIndex {
            let qualifies = levels[index].map { $0 >= bar } ?? false
            rivalStreaks[index] =
                qualifies
                ? rivalStreaks[index] + 1
                : max(0, rivalStreaks[index] - Self.rivalStreakDecay)
            if rivalStreaks[index] >= threshold {
                focus(on: index)
                return .focused(index)
            }
        }
        return .none
    }

    private mutating func focus(on index: Int) {
        focusIndex = index
        isSettled = false
        inTuneStreak = 0
        outOfTuneStreak = 0
        rivalStreaks = Array(repeating: 0, count: stringCount)
        // The new string starts with its own story: the old peak belongs
        // to the string that made it.
        focusPeak = 0
    }
}
