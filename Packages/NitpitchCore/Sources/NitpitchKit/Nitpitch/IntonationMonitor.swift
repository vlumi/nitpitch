import Foundation
import NitpitchCore

/// The intonation mode's screen-facing state: the live needle and the two
/// captured samples, published for the pane and the readout row.
///
/// Its own observable island, like `InputLevel`: frames arrive ~21×/second,
/// and only the views that render intonation should re-render for them —
/// publishing on the object that anchors the whole string view would fight
/// the swipe animation for nothing.
@MainActor
final class IntonationMonitor: ObservableObject {
    /// What the needle is following right now.
    struct Live: Equatable {
        let slot: IntonationSlot
        /// Display-smoothed cents against the slot's own target.
        let cents: Double
        let clarity: Double
        /// Meter drive behind the reading, quantized to twentieths like
        /// every other published level.
        let level: Double
    }

    @Published private(set) var live: Live?
    /// The captured samples, quantized to tenths — sub-cent flutter in a
    /// refreshing run isn't worth a re-render, let alone reading.
    @Published private(set) var open: Double?
    @Published private(set) var octave: Double?
    @Published private(set) var delta: Double?

    private var capture = IntonationCapture()
    private var smoother = ReadingSmoother()
    private var lastSlot: IntonationSlot?
    /// Frames with nothing sounding; after enough of them the needle clears
    /// rather than freezing on a stale reading — same rule as the tuners.
    private var quietFrames = 0
    private static let quietFramesBeforeClear = 8

    func ingest(_ frame: IntonationAnalyzer.Frame) {
        capture.ingest(frame)
        publishSamples()

        switch frame.sounding {
        case .nothing:
            quietFrames += 1
            if quietFrames >= Self.quietFramesBeforeClear, live != nil {
                smoother.reset()
                lastSlot = nil
                live = nil
            }
        case .note(let slot, let cents, let clarity):
            quietFrames = 0
            // The smoother must not glide across the slot boundary — open
            // and octave are different notes, not one note moving.
            if slot != lastSlot {
                smoother.reset()
                lastSlot = slot
            }
            let smoothed = (smoother.update(cents: cents) * 10).rounded() / 10
            let next = Live(
                slot: slot, cents: smoothed, clarity: clarity,
                level: (frame.level * 20).rounded() / 20)
            if next != live { live = next }
        }
    }

    /// Forget everything — the target moved, or the mode was left.
    func reset() {
        capture.reset()
        smoother.reset()
        lastSlot = nil
        quietFrames = 0
        live = nil
        open = nil
        octave = nil
        delta = nil
    }

    private func publishSamples() {
        let tenth = { (value: Double) in (value * 10).rounded() / 10 }
        let nextOpen = capture.open.map(tenth)
        let nextOctave = capture.octave.map(tenth)
        let nextDelta = capture.delta.map(tenth)
        if nextOpen != open { open = nextOpen }
        if nextOctave != octave { octave = nextOctave }
        if nextDelta != delta { delta = nextDelta }
    }
}
