import Foundation
import NitpitchCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The string view's hands-free ear: a whole-instrument bank listening
/// beside the screen's own single-string tuner, feeding `StringFocus` — the
/// policy whose rules are pinned by tests in Core — so the screen follows
/// the string being PLAYED instead of waiting for a swipe.
///
/// Always on, exactly as on the watch: the policy IS the string view's
/// founding rule ("the screen can't yank away mid-turn on a peg") — work on
/// the focused string resets every rival, so only sustained play elsewhere,
/// or a settled string, moves the screen. It shipped behind an opt-in
/// toggle first, a belt worn with suspenders that field use retired.
@MainActor
final class FollowFocus: ObservableObject {
    /// Where the policy says the screen should be. The view observes this
    /// and steps its own index — SwiftUI state flows through observation,
    /// not stored view-struct captures.
    @Published private(set) var focusIndex = 0
    /// The focused string has held in tune long enough to call done — the
    /// readout wears it as green, the same vocabulary as the watch's name.
    @Published private(set) var isSettled = false

    /// The level of a note the intonation analyzer attributes to the focused
    /// string — nil when it hears none. The string's own octave (the
    /// intonation check's second note) lands in a NEIGHBOUR's band by pitch
    /// (violin G's octave sits in A's), and was walking the screen away
    /// mid-measurement; a frame the analyzer claims is this string's open or
    /// octave IS the focused string sounding, whatever band the bank filed
    /// it under. The watch learned this rule on a bass 12th fret.
    var focusedVoice: (() -> Double?)?

    private let audio: AudioSessionController
    private var subscription: AudioSessionController.Subscription?
    private var bank: DetectorBank?
    private var focus = StringFocus(stringCount: 1)
    private var targets: [Double] = []

    init(audio: AudioSessionController) {
        self.audio = audio
    }

    var isRunning: Bool { subscription != nil }

    /// Start (or retune) the ear for this instance, focused at `index`.
    /// Called again whenever the instance's reference/temperament or the
    /// detection tuning changes — the targets move with them.
    func begin(instance: InstrumentInstance, index: Int, tuning: DetectionTuning) {
        end()
        let instrument = instance.instrument
        let offsets = instance.appliedTemperament.offsets(for: instrument.strings)
        targets = zip(instrument.notes, offsets).map { note, offset in
            note.frequency(reference: instance.reference) * pow(2, offset / 1200)
        }
        focus = StringFocus(stringCount: targets.count, initialIndex: index)
        focusIndex = index
        let bank = DetectorBank(
            sampleRate: audio.sampleRate,
            targets: targets,
            bands: instrument.stringBands(reference: instance.reference),
            tuning: tuning)
        self.bank = bank
        subscription = audio.subscribe { [weak self, bank] window in
            // Analysis queue; only the results hop to main.
            let results = bank.analyze(window)
            Task { @MainActor [weak self] in self?.consume(results) }
        }
    }

    func end() {
        subscription?.cancel()
        subscription = nil
        bank = nil
    }

    /// A swipe, an arrow, a scrub: the user's own move is authoritative and
    /// must reset the policy, or a half-grown rival streak would carry over
    /// into the string they explicitly chose.
    func select(_ index: Int) {
        focus.select(index)
        if focusIndex != index { focusIndex = index }
        if isSettled { isSettled = false }
    }

    private func consume(_ results: [DetectionResult]) {
        guard results.count == targets.count else { return }
        var levels = results.map { $0.frequency != nil ? $0.level : nil }
        if let voice = focusedVoice?() {
            levels[focus.focusIndex] = max(levels[focus.focusIndex] ?? 0, voice)
        }
        var inTune: Bool?
        if let hz = results[focus.focusIndex].frequency {
            inTune = TuningDisplay.isInTune(
                cents: PitchMath.cents(from: targets[focus.focusIndex], to: hz))
        }
        switch focus.ingest(levels: levels, focusedInTune: inTune) {
        case .focused(let index):
            focusIndex = index
        case .settled:
            // The same success tap the wrist gives; the Mac has nothing to
            // buzz and wears the green alone.
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        case .none:
            break
        }
        if isSettled != focus.isSettled { isSettled = focus.isSettled }
    }
}
