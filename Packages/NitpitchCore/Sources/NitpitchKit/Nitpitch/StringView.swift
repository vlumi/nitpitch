import NitpitchCore
import SwiftUI

/// One string, full screen: the full dial, the string's target as the
/// readout, and everything the microphone hears measured against that target.
///
/// This is the coarse-tuning home (ROADMAP § 1). Being bound to one string,
/// it has no "which dial" ambiguity — so unlike a grid cell it listens to the
/// *whole instrument's range*, and a peg slipped three semitones reads as
/// "−300¢, keep going" instead of nothing. The flip side is intentional too:
/// everything it hears *is* this string, by definition — play a neighbour and
/// the dial pins, because the view answers "how far is this from D" and
/// nothing else. It never follows the sound to another string; swiping or the
/// arrows are the only way to move, so the screen can't yank away mid-turn on
/// a peg.
struct StringView: View {
    @ObservedObject var store: InstrumentStore
    @ObservedObject var settings: Settings
    @ObservedObject var detection: DetectionSettings

    @StateObject private var single: SingleStringTuner
    @State private var index: Int
    /// Finger-following displacement of the dial pane while a swipe is in
    /// flight — zero whenever the pane is at rest.
    @State private var dragOffset: CGFloat = 0
    /// The pane row's measured width: the slide distance of one page.
    @State private var paneWidth: CGFloat = 400

    private let initial: InstrumentInstance

    init(
        instance: InstrumentInstance, index: Int, store: InstrumentStore,
        audio: AudioSessionController, settings: Settings, detection: DetectionSettings
    ) {
        self.store = store
        self.settings = settings
        self.detection = detection
        self.initial = instance
        _index = State(initialValue: index)
        _single = StateObject(
            wrappedValue: SingleStringTuner(
                instrument: instance.instrument, index: index, audio: audio,
                reference: instance.reference, tuning: detection.tuning))
    }

    private var instance: InstrumentInstance {
        store.instance(id: initial.id) ?? initial
    }

    private var instrument: Instrument { instance.instrument }

    var body: some View {
        VStack(spacing: 16) {
            LevelMeter(level: single.inputLevel)
                .frame(width: 72, height: 4)
                .padding(.top, 6)
            dialCarousel
            stringSwitcher
            ReferencePitchStepper(
                reference: Binding(
                    get: { instance.reference },
                    set: { store.setReference(id: instance.id, $0) }),
                naming: settings.naming
            )
            .disabled(instance.isLocked)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, alignment: .center)
        .navigationTitle(instance.nameText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { lockButton }
        }
        // No identifier on the container: applied here it stamps every child
        // element and clobbers their own ids (string.target went missing).
        .task { single.attach() }
        .onDisappear { single.detach() }
        .onChangeCompat(of: instance) { _ in
            single.apply(instance: instance, index: index, tuning: detection.tuning)
        }
        .onChangeCompat(of: detection.tuning) { tuning in
            single.retune(tuning)
        }
        // Swiping is the same move as the arrows, but with the gallery's
        // physics: the pane rides the finger, the neighbour is revealed
        // beside it, and the release either commits with a swing or snaps
        // back. A high-priority gesture would fight the scroll-free layout
        // for nothing; plain is enough.
        .gesture(swipeGesture)
    }

    /// The dial pane as one page of a gallery. Only the current string is
    /// live — there's one detector, aimed at one target — so the neighbour
    /// rides in as a still pane (its dial, its target, no reading) and comes
    /// alive the instant it lands, when the detector retargets.
    private var dialCarousel: some View {
        ZStack {
            StringDialPane(
                tuner: single.tuner,
                naming: settings.naming,
                isLocked: instance.isLocked,
                canStepTarget: { delta in canStepTarget(delta) },
                stepTarget: { delta in stepTarget(delta) }
            )
            .offset(x: dragOffset)
            // One rule covers every phase: the ghost is always the
            // neighbour the offset points toward, one page away. During the
            // drag that's where you're heading; during the swing-in after a
            // commit the *old* pane occupies exactly this slot, so the
            // handover is seamless.
            if dragOffset != 0, let ghost = ghostIndex {
                GhostDialPane(note: instrument.notes[ghost], naming: settings.naming)
                    .offset(x: dragOffset + (dragOffset < 0 ? paneWidth : -paneWidth))
            }
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            paneWidth = max(1, width)
        }
    }

    /// The string the current offset is sliding toward, if there is one.
    private var ghostIndex: Int? {
        let candidate = index + (dragOffset < 0 ? 1 : -1)
        return instrument.notes.indices.contains(candidate) ? candidate : nil
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Latch onto a horizontal intent; once panning, keep
                // following even if the finger wanders vertically.
                guard
                    dragOffset != 0
                        || abs(value.translation.width) > abs(value.translation.height)
                else { return }
                let raw = value.translation.width
                // Rubber-band past the outermost string: movement with
                // resistance says "there's nothing there" better than
                // refusing to move.
                dragOffset = canStep(raw < 0 ? 1 : -1) ? raw : raw * 0.25
            }
            .onEnded { value in
                let raw = value.translation.width
                let delta = raw < 0 ? 1 : -1
                // A committed swipe is distance OR a flick — the predicted
                // end catches a short, fast gesture.
                let commits =
                    canStep(delta)
                    && (abs(raw) > paneWidth / 3
                        || abs(value.predictedEndTranslation.width) > paneWidth * 0.6)
                guard commits else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                    return
                }
                // Commit first, unanimated: the new current pane takes over
                // the ghost's slot and the old pane becomes the ghost, in
                // place. Then the swing home animates from exactly there —
                // the async hop lets that intermediate state render once, so
                // the spring starts from it rather than from wherever the
                // finger began.
                step(delta)
                dragOffset += CGFloat(delta) * paneWidth
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// The same ambient padlock as the grid's — the lock follows the
    /// instrument, so it should look the same wherever the instrument is.
    private var lockButton: some View {
        Button {
            store.setLocked(id: instance.id, !instance.isLocked)
        } label: {
            Image(systemName: instance.isLocked ? "lock.fill" : "lock.open")
                .foregroundStyle(
                    instance.isLocked ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .accessibilityIdentifier("string.lock")
        .accessibilityLabel(
            instance.isLocked
                ? Text("Unlock", bundle: .module) : Text("Lock", bundle: .module))
    }

    /// ◀ dots ▶ — where you are among the strings, and the way sideways.
    private var stringSwitcher: some View {
        HStack(spacing: 24) {
            arrow(systemName: "chevron.left", id: "string.prev", by: -1)
            HStack(spacing: 7) {
                ForEach(instrument.notes.indices, id: \.self) { position in
                    Circle()
                        .fill(
                            position == index
                                ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.25)
                        )
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            arrow(systemName: "chevron.right", id: "string.next", by: 1)
        }
    }

    private func arrow(systemName: String, id: String, by delta: Int) -> some View {
        Button {
            step(delta)
        } label: {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 56, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!canStep(delta))
        .accessibilityIdentifier(id)
        .accessibilityLabel(
            delta < 0
                ? Text("Previous string", bundle: .module)
                : Text("Next string", bundle: .module))
    }

    private func canStep(_ delta: Int) -> Bool {
        instrument.notes.indices.contains(index + delta)
    }

    private func step(_ delta: Int) {
        guard canStep(delta) else { return }
        index += delta
        single.apply(instance: instance, index: index, tuning: detection.tuning)
    }

    /// The target stepper: nudge D2 down to C2, and the tuning relabels
    /// itself Custom because the pitches no longer match anything named.
    private func canStepTarget(_ delta: Int) -> Bool {
        guard instance.strings.indices.contains(index) else { return false }
        return InstrumentStore.editableMIDIRange.contains(instance.strings[index] + delta)
    }

    private func stepTarget(_ delta: Int) {
        guard canStepTarget(delta) else { return }
        store.setString(id: instance.id, index: index, midi: instance.strings[index] + delta)
        // The store change comes back through onChange(of: instance) → apply.
    }
}

/// A neighbouring string's pane while it slides in: the dial at rest and the
/// target it will aim for — no reading, because nothing is listening for it
/// yet. Mirrors `StringDialPane`'s geometry exactly (the stepper slots are
/// blank stand-ins) so the live pane can take its place without a shift.
private struct GhostDialPane: View {
    let note: Note
    let naming: NoteNaming

    var body: some View {
        TunerDial(cents: 0, inTune: false, isReading: false) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 40, height: 40)
                    NoteNameLabel(
                        note: note, naming: naming, fontSize: 46,
                        order: .localizedFirst
                    )
                    .frame(width: 190)
                    Color.clear.frame(width: 40, height: 40)
                }
                Text(verbatim: "—")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(height: 46 * 1.15 + 4 + 20)
        }
        .accessibilityHidden(true)
    }
}

/// The dial and its readout, observing the string's model.
private struct StringDialPane: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming
    let isLocked: Bool
    let canStepTarget: (Int) -> Bool
    let stepTarget: (Int) -> Void

    var body: some View {
        TunerDial(cents: displayCents, inTune: isInTune, isReading: isReading) {
            readout
        }
    }

    /// The *target*, not the detection: this screen answers "how far is this
    /// from D", so D is the headline and the cents are the answer — and the
    /// steppers flanking it change what's being asked: nudge D2 down to C2
    /// and this string's target IS C2 (the tuning relabels itself Custom).
    /// The chromatic tuner shows what it heard; this shows what you're after.
    private var readout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                targetStep(systemName: "minus", id: "string.down", by: -1)
                NoteNameLabel(
                    note: tuner.target, naming: naming, fontSize: 46,
                    order: .localizedFirst
                )
                // A fixed slot, so the − and + don't wobble with the
                // width of whatever note name sits between them.
                .frame(width: 190)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("string.target")
                .accessibilityLabel(tuner.target.accessibleName(in: naming))
                targetStep(systemName: "plus", id: "string.up", by: 1)
            }
            Text(verbatim: centsLabel)
                .font(.title3.monospacedDigit())
                .foregroundStyle(
                    isInTune
                        ? AnyShapeStyle(Color.green)
                        : AnyShapeStyle(.secondary)
                )
                .accessibilityIdentifier("string.cents")
        }
        .frame(height: 46 * 1.15 + 4 + 20)
    }

    private func targetStep(systemName: String, id: String, by delta: Int) -> some View {
        Button {
            stepTarget(delta)
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!canStepTarget(delta) || isLocked)
        .accessibilityIdentifier(id)
        .accessibilityLabel(
            delta < 0
                ? Text("Lower target", bundle: .module)
                : Text("Raise target", bundle: .module))
    }

    private var centsLabel: String {
        guard case .reading(let cents, _) = tuner.state else { return "—" }
        let rounded = Int(cents.rounded())
        return rounded > 0 ? "+\(rounded)¢" : "\(rounded)¢"
    }

    private var displayCents: Double {
        if case .reading(let cents, _) = tuner.state { return cents }
        return 0
    }

    private var isInTune: Bool {
        if case .reading(let cents, _) = tuner.state {
            return TuningDisplay.isInTune(cents: cents)
        }
        return false
    }

    private var isReading: Bool {
        if case .reading = tuner.state { return true }
        return false
    }
}
