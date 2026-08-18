import Foundation
import NitpitchCore
import SwiftUI

/// The string view's hands-free ear: a whole-instrument bank listening
/// beside the screen's own single-string tuner, feeding `StringFocus` — the
/// policy whose rules are pinned by tests in Core — so the screen can follow
/// the string being PLAYED instead of waiting for a swipe.
///
/// Runs only while the Follow toggle is on: the string view's founding rule
/// ("the screen can't yank away mid-turn on a peg") stays the default, and
/// the policy itself is the anti-yank mechanism when following — work on the
/// focused string resets every rival, so only sustained play elsewhere, or a
/// settled string, moves the screen.
@MainActor
final class FollowFocus: ObservableObject {
    /// Where the policy says the screen should be. The view observes this
    /// and steps its own index — SwiftUI state flows through observation,
    /// not stored view-struct captures.
    @Published private(set) var focusIndex = 0

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
    }

    private func consume(_ results: [DetectionResult]) {
        guard results.count == targets.count else { return }
        let levels = results.map { $0.frequency != nil ? $0.level : nil }
        var inTune: Bool?
        if let hz = results[focus.focusIndex].frequency {
            inTune = TuningDisplay.isInTune(
                cents: PitchMath.cents(from: targets[focus.focusIndex], to: hz))
        }
        if case .focused(let index) = focus.ingest(
            levels: levels, focusedInTune: inTune)
        {
            focusIndex = index
        }
    }
}

/// The switcher row's hands-free toggle (the map apps' follow-me arrow,
/// borrowed for the same meaning). Off by default — the string view's
/// founding rule that the screen never yanks away mid-turn stays until
/// asked; on, `StringFocus` IS that rule's keeper. A tap gesture, not a
/// Button, for the same swipe-starvation reason as the arrows beside it.
struct FollowToggle: View {
    @Binding var isFollowing: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Image(systemName: isFollowing ? "location.fill" : "location")
            .font(.title3.weight(.semibold))
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .foregroundStyle(
                isFollowing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
            )
            .onTapGesture {
                isFollowing.toggle()
                onChange(isFollowing)
            }
            .accessibilityIdentifier("string.follow")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Follow the playing", bundle: .module))
            .accessibilityValue(
                isFollowing ? Text("On", bundle: .module) : Text("Off", bundle: .module))
    }
}
