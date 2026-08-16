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
    /// Frames a rival string must sustain to take focus while the focused
    /// string is still being worked on (~0.85 s — longer than any brush).
    public static let switchFrames = 18
    /// The same, once the focused string has settled (~0.25 s — you are
    /// moving on, the screen should already be there).
    public static let switchFramesSettled = 5

    public private(set) var focusIndex: Int
    public private(set) var isSettled = false

    private let stringCount: Int
    private var inTuneStreak = 0
    /// Consecutive sounding frames per rival string.
    private var rivalStreaks: [Int]

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

    /// One analysis frame: which strings sound (the per-string bank's
    /// confirmed readings), and whether the focused string's reading is in
    /// tune — nil when it isn't sounding. Returns what the screen should
    /// announce.
    public mutating func ingest(sounding: [Bool], focusedInTune: Bool?) -> Event {
        guard sounding.count == stringCount else { return .none }

        // The focused string speaking is the user working: rivals reset —
        // a brush ALONGSIDE the note being tuned is the most common brush
        // of all, and it must never accumulate toward a switch.
        if sounding[focusIndex] {
            for index in rivalStreaks.indices where index != focusIndex {
                rivalStreaks[index] = 0
            }
            if focusedInTune == true {
                inTuneStreak += 1
                if inTuneStreak == Self.settledFrames {
                    isSettled = true
                    return .settled
                }
            } else {
                inTuneStreak = 0
                // Back off the tuning peg and "done" is no longer true.
                isSettled = false
            }
            return .none
        }

        // Silence on the focused string: streaks of rivals grow, the
        // in-tune streak survives briefly (isSettled already latched).
        inTuneStreak = 0
        let threshold = isSettled ? Self.switchFramesSettled : Self.switchFrames
        for index in rivalStreaks.indices where index != focusIndex {
            rivalStreaks[index] = sounding[index] ? rivalStreaks[index] + 1 : 0
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
        rivalStreaks = Array(repeating: 0, count: stringCount)
    }
}
