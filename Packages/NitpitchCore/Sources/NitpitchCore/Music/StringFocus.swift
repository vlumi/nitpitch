import Foundation

/// Which string owns the screen, for hands-free one-string-at-a-time tuning.
///
/// The display stays PINNED to one string, so a brush from a hand crossing
/// the strings cannot take it mid-adjustment. Focus moves for exactly three
/// reasons, in order of authority:
///
/// 1. **An explicit pick** (`select`) — the crown, a tap. Instant, always.
/// 2. **Deliberate play**: a NEIGHBOURING string sounding *sustained* for
///    `switchFrames`. Duration is the discriminator — a brush is brief, a
///    string plucked to be tuned rings. Neighbours only, because a distant
///    claim is usually another string's harmonic wearing the wrong band (a
///    guitar low E's 12th fret is the D band's pitch; a played B IS that
///    E's 3rd harmonic), and the 2:1 and 3:1 coincidences cannot land next
///    door when neighbours sit a fourth or fifth apart. Adjacency WRAPS,
///    so a verify pass walks from the top string back to the bottom; this
///    stays safe only while no instrument's extreme pair is an octave or
///    twelfth apart (guitar's E2/E4 double octave is the closest, and a
///    4th-harmonic reading cannot clear the level and prominence bars).
/// 3. **The settled advance**: once the focused string has held in tune
///    for `settledFrames`, the switching threshold drops to
///    `switchFramesSettled`, so the next string to speak takes the screen
///    almost at once. One policy, asymmetric by intent.
///
/// Pure state machine, one `ingest` per analysis frame (~21/s): everything
/// it knows arrives as arguments, which is what lets `StringFocusTests`
/// pin every rule above as a scripted sequence.
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

    /// The settled arithmetic lives in `SettleMeter`, shared with the
    /// grid's per-cell verdict.
    /// Frames a rival string must sustain to take focus while the focused
    /// string is still being worked on (~0.85 s — longer than any brush).
    public static let switchFrames = 18
    /// The same, once the focused string has settled (~0.25 s — you are
    /// moving on, the screen should already be there).
    public static let switchFramesSettled = 5

    /// A non-qualifying frame DECAYS a rival's streak rather than zeroing
    /// it, so a string reading intermittently (a bass A through a wrist
    /// microphone) can still accumulate. Decay must stay slow enough that
    /// a 2-frames-in-3 reader nets forward, and fast enough that a stopped
    /// rival drains to zero within a second.
    public static let rivalStreakDecay = 1

    /// The share of the focused string's recent peak strength a rival's
    /// reading must carry to count toward a switch. Duration alone is not
    /// enough: an unmuted neighbour rings sympathetically and sustains past
    /// the pluck that caused it. The separation this relies on is that a
    /// deliberately played string arrives near the peak while a ring sits
    /// well below it — one physical claim, used from both sides, since
    /// `ingest` draws the focused string's own working/ringing line here
    /// too.
    public static let rivalLevelShare = 0.6
    /// How the remembered peak fades per frame once the focused string goes
    /// quiet (half in ~6 s): long enough that a ring dies before the bar
    /// drops to its level, short enough that a quiet-but-deliberate player
    /// is never locked out.
    public static let peakDecayPerFrame = 0.995

    /// How much STRONGER than the focused string's current reading a rival
    /// must be, while that string still sounds, to count toward a switch.
    /// Strength is logarithmic (~40 dB per unit), so this is a ratio:
    /// 0.15 ≈ 6 dB. It exists because the peak bar alone cannot free the
    /// screen from a long ring through a line input, which stays tens of
    /// dB above the presence gate for seconds. The margin must stay above
    /// what a ring can reach and below deliberate play — and a double
    /// stop's matched partner must never clear it, or a bowed pair steals
    /// focus from itself.
    public static let rivalProminenceMargin = 0.15

    public private(set) var focusIndex: Int
    public var isSettled: Bool { settle.isSettled }

    private let stringCount: Int
    private var settle = SettleMeter()
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

        let focusedLevel = levels[focusIndex]
        if let focusedLevel { focusPeak = max(focusPeak, focusedLevel) }

        // Worked (sounding near its own recent peak) or merely ringing on.
        // The same share that separates a deliberate rival from a ring
        // draws this line.
        let isWorked =
            focusedLevel.map { $0 >= focusPeak * Self.rivalLevelShare } ?? false
        if !isWorked { focusPeak *= Self.peakDecayPerFrame }

        // A ring IS the focused string, so settling can finish landing
        // while it fades; silence is no evidence either way.
        if settle.ingest(inTune: focusedLevel != nil ? focusedInTune : nil) {
            return .settled
        }

        let bar = focusPeak * Self.rivalLevelShare
        let threshold = isSettled ? Self.switchFramesSettled : Self.switchFrames
        // Neighbours only, wrapping at the extremes (type doc, rule 2).
        // Two strings share a single neighbour, which must be counted once
        // or its streak grows at twice the honest pace; one string has no
        // rival at all.
        var rivals = [
            (focusIndex + stringCount - 1) % stringCount,
            (focusIndex + 1) % stringCount,
        ]
        if rivals[0] == rivals[1] { rivals.removeLast() }
        for index in rivals where index != focusIndex {
            // Two bars, both required: strong against the focused string's
            // recent PEAK, and — while that string still sounds — stronger
            // than it is NOW by `rivalProminenceMargin`.
            //
            // Non-qualifying frames RESET a rival while the focused string
            // is worked, so a brush alongside the note being tuned cannot
            // accumulate, but only DECAY it in the tail and in silence,
            // where an intermittent reading is not a retraction.
            let prominent =
                focusedLevel.map { level in
                    (levels[index] ?? 0) >= level + Self.rivalProminenceMargin
                } ?? true
            let qualifies = prominent && (levels[index].map { $0 >= bar } ?? false)
            rivalStreaks[index] =
                qualifies
                ? rivalStreaks[index] + 1
                : isWorked ? 0 : max(0, rivalStreaks[index] - Self.rivalStreakDecay)
            if rivalStreaks[index] >= threshold {
                focus(on: index)
                return .focused(index)
            }
        }
        return .none
    }

    private mutating func focus(on index: Int) {
        focusIndex = index
        settle.reset()
        rivalStreaks = Array(repeating: 0, count: stringCount)
        // The peak belongs to the string that made it.
        focusPeak = 0
    }
}
