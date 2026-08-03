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
            StringDialPane(
                tuner: single.tuner,
                naming: settings.naming,
                isLocked: instance.isLocked,
                canStepTarget: { delta in canStepTarget(delta) },
                stepTarget: { delta in stepTarget(delta) })
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
        // Swiping is the same move as the arrows. A high-priority gesture
        // would fight the scroll-free layout for nothing; plain is enough.
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height)
                else { return }
                step(value.translation.width < 0 ? 1 : -1)
            }
        )
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
                NoteNameLabel(note: tuner.target, naming: naming, fontSize: 46)
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

/// The string view's audio: one target, the whole instrument's band.
///
/// A sibling of `StringTuners` for the N = 1 case, with the crucial
/// difference in the *band*: the grid's cells split the range at midpoints so
/// dials can disambiguate, but a view bound to one string has nothing to
/// disambiguate against — so it hears everything the instrument can produce,
/// and the hybrid does the rest (spectral precision near target, MPM finding
/// a slack string from anywhere).
@MainActor
final class SingleStringTuner: ObservableObject {
    let tuner: StringTunerViewModel

    /// Overall input level for the meter, same curve and quantization as the
    /// grid's.
    @Published private(set) var inputLevel: Double = 0

    private var instrument: Instrument
    private let audio: AudioSessionController
    private let bank: DetectorBank
    private var subscription: AudioSessionController.Subscription?
    private var demo: Task<Void, Never>?
    private var reference: ReferencePitch
    /// Kept so retargeting doesn't quietly reset debug-tuned thresholds.
    private var tuning: DetectionTuning

    init(
        instrument: Instrument, index: Int, audio: AudioSessionController,
        reference: ReferencePitch, tuning: DetectionTuning = .default
    ) {
        self.instrument = instrument
        self.audio = audio
        self.reference = reference
        self.tuning = tuning
        let band = instrument.band(reference: reference)
        let note = instrument.notes[index]
        tuner = StringTunerViewModel(
            audio: audio, target: note, band: band, reference: reference)
        bank = DetectorBank(
            sampleRate: audio.sampleRate,
            targets: [note.frequency(reference: reference)],
            bands: [band],
            tuning: tuning)
    }

    func attach() {
        tuner.begin()
        if LaunchStores.isDemo {
            guard demo == nil else { return }
            demo = Task { await runDemoLevel() }
            return
        }
        guard subscription == nil else { return }
        subscription = audio.subscribe { [weak self, bank] window in
            // Analysis queue; only the result hops to main.
            let results = bank.analyze(window)
            Task { @MainActor [weak self] in
                guard let self, let result = results.first else { return }
                self.tuner.ingest(result)
                let level = (result.displayLevel * 20).rounded() / 20
                if level != self.inputLevel { self.inputLevel = level }
            }
        }
    }

    func detach() {
        subscription?.cancel()
        subscription = nil
        demo?.cancel()
        demo = nil
        inputLevel = 0
        bank.interrupted()
        tuner.end()
    }

    /// The one entry point for "aim here now": swiping to a neighbour, the
    /// reference moving, or the target itself being edited — all end up as a
    /// note, a band, and a reference to measure against.
    func apply(instance: InstrumentInstance, index: Int, tuning: DetectionTuning) {
        self.instrument = instance.instrument
        self.reference = instance.reference
        self.tuning = tuning
        guard instrument.notes.indices.contains(index) else { return }
        let note = instrument.notes[index]
        let band = instrument.band(reference: reference)
        bank.configure(
            targets: [note.frequency(reference: reference)],
            bands: [band],
            tuning: tuning)
        tuner.configure(band: band, reference: reference)
        if tuner.target != note {
            tuner.retarget(note)
        }
    }

    func retune(_ tuning: DetectionTuning) {
        self.tuning = tuning
        bank.retune(tuning)
    }

    private func runDemoLevel() async {
        var tick = 0.0
        while !Task.isCancelled {
            inputLevel = ((0.5 + 0.3 * sin(tick * 1.3)) * 20).rounded() / 20
            tick += 0.055
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
