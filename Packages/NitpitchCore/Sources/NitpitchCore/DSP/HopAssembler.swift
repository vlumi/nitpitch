import Foundation

/// Turns the capture callback's arbitrary-length sample chunks into the
/// analysis windows the detectors want — `windowSize` long, `hopSize`
/// apart, hop-CONSECUTIVE — and keeps a slow consumer from drowning.
///
/// The consecutiveness is load-bearing: the spectral engine reads frequency
/// from the phase advance between one window and the next, so two windows
/// that are not exactly one hop apart measure garbage with full confidence.
/// That is why dropping is a first-class event here rather than a silent
/// trim: whenever samples or windows are discarded, the next batch handed
/// out carries `gapBefore`, and the consumer resets its phase pairs
/// (`DetectorBank.interrupted`) before reading on.
///
/// Why drop at all: analysis runs on its own serial queue, and a device that
/// falls behind real time — an old iPad under a heavy screen — would
/// otherwise queue windows without bound, so readings lag the instrument by
/// more every second and never recover. A tuner wants the LATEST reading;
/// `maxInFlight` caps how many windows may await analysis, and beyond it new
/// windows are discarded (counted in `droppedWindows`, shown on the debug
/// screen) rather than queued.
///
/// Not thread-safe on its own: the capture source calls `append` from the
/// audio thread and `finished` from the analysis queue, under its own lock.
public struct HopAssembler {
    /// One call's yield: the windows to analyze, in order, and whether
    /// anything was discarded since the previous yield.
    public struct Batch: Equatable, Sendable {
        public let windows: [[Float]]
        public let gapBefore: Bool
        public static let empty = Batch(windows: [], gapBefore: false)
    }

    /// Six windows in flight is ~280 ms of lag at most before dropping
    /// begins — two full runs (see `keepWindowsInRunsOf`). Two was tighter
    /// and wrong: the cap is the budget a kept RUN is taken from, and a cap
    /// below one run means every burst discards everything, which is what
    /// took a double stop down to one string on an A12. The lag is the
    /// price of reading at all on a device that falls behind, and a dial
    /// hides it better than it hides a string that never lights.
    public static let defaultMaxInFlight = 6

    /// What a kept RUN of windows must contain to light a dial, and why
    /// it is three rather than two.
    ///
    /// The spectral engine — the only one that reads two strings at once,
    /// MPM being monophonic — measures frequency from the phase advance
    /// between CONSECUTIVE windows, so after a discontinuity the first
    /// window only rebuilds the reference and the second is the first that
    /// can measure. On top of that sits the confirmation rule: a dial
    /// lights after two AGREEING frames, never one. Two measurements means
    /// three consecutive windows, and a run of two can never light
    /// anything — it yields a single measurement that confirmation
    /// correctly swallows.
    ///
    /// Field-found on an A12 iPhone (XR): bowing a violin's D and G, only
    /// G read. Before b18 nothing was ever dropped (the backlog trim was
    /// dead code), so this is the cost of making dropping real.
    static let keepWindowsInRunsOf = 3

    public private(set) var droppedWindows = 0

    private let windowSize: Int
    private let hopSize: Int
    private let maxInFlight: Int
    private var pending: [Float] = []
    private var inFlight = 0
    private var gapPending = false

    public init(
        windowSize: Int = Detection.windowSize, hopSize: Int = Detection.hopSize,
        maxInFlight: Int = HopAssembler.defaultMaxInFlight
    ) {
        precondition(hopSize > 0 && hopSize <= windowSize, "a hop must fit in its window")
        self.windowSize = windowSize
        self.hopSize = hopSize
        self.maxInFlight = max(1, maxInFlight)
    }

    /// Take a chunk of converted samples; get back every whole window it
    /// completes. Windows beyond the in-flight cap are dropped, not queued.
    public mutating func append(_ samples: [Float]) -> Batch {
        pending.append(contentsOf: samples)
        var windows: [[Float]] = []
        while pending.count >= windowSize {
            windows.append(Array(pending.prefix(windowSize)))
            pending.removeFirst(hopSize)
        }
        guard !windows.isEmpty else { return .empty }

        var room = max(0, maxInFlight - inFlight)
        if windows.count > room {
            // Keep the NEWEST: a tuner shows what is sounding now, and the
            // discarded windows were the oldest news in the batch. But keep
            // an EVEN number of them, so what survives is a consecutive
            // PAIR the spectral engine can actually measure across — an odd
            // tail would be a window whose predecessor we just discarded,
            // which costs a phase reset and reads nothing.
            room -= room % Self.keepWindowsInRunsOf
            droppedWindows += windows.count - room
            windows = Array(windows.suffix(room))
            gapPending = true
        }
        guard !windows.isEmpty else { return .empty }
        inFlight += windows.count
        defer { gapPending = false }
        return Batch(windows: windows, gapBefore: gapPending)
    }

    /// The consumer is done with `count` windows — room for more.
    public mutating func finished(_ count: Int) {
        inFlight = max(0, inFlight - count)
    }

    /// Capture stopped: forget the partial window and anything in flight.
    /// The next window after a restart is a fresh start for phase anyway
    /// (the consumer calls `interrupted()` on its own on stop/start).
    public mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        inFlight = 0
        gapPending = false
    }
}
