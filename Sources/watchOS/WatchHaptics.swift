import Foundation
import NitpitchCore
import WatchKit

/// Plays a `HapticBeat.Cue` as timed wrist taps. The cue changes every
/// analysis frame (~20/s) while any allowed tap is slower than that, so the
/// clock must NOT reset on update — a per-frame reset would starve the
/// cadence entirely. Instead each tap schedules the next one from whatever
/// the cue says at that moment: the beat slows and quickens mid-flight, the
/// way the audible one does.
@MainActor
final class WatchHaptics {
    private var cue: HapticBeat.Cue?
    private var timer: Timer?

    /// The latest word from the analysis frame. Nil stops the beat cold;
    /// the first cue after silence taps immediately — the beat starts now.
    func update(_ cue: HapticBeat.Cue?) {
        let wasSilent = self.cue == nil
        self.cue = cue
        if cue == nil {
            timer?.invalidate()
            timer = nil
        } else if wasSilent {
            tap()
        }
    }

    func stop() { update(nil) }

    private func tap() {
        guard let cue else {
            timer = nil
            return
        }
        // One pattern, always: the taps carry distance (the cadence);
        // direction is the glance's job — see `HapticBeat`.
        WKInterfaceDevice.current().play(.click)
        timer?.invalidate()
        let next = Timer(timeInterval: 1 / cue.ratePerSecond, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.tap() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

}
