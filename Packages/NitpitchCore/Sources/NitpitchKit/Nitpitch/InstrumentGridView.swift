import NitpitchCore
import SwiftUI

/// One dial per string, so tuning an instrument is measurement against known
/// targets rather than "what note is this".
///
/// Each dial watches its own narrow band — split at the midpoints between
/// neighbouring strings — so playing the G string lights the G dial and
/// nothing else. All of them read the same microphone through
/// `AudioSessionController`.
///
/// The screen shows an instrument *you own* (`InstrumentInstance`): its name
/// in the title, its tuning in the header menu, its reference in the footer —
/// all autosaved through the store, waiting as you left them. The padlock
/// freezes the lot; locked controls are doors (they never mutate and never
/// ignore a touch — they offer the unlock).
struct InstrumentGridView: View {
    let audio: AudioSessionController
    @ObservedObject var store: InstrumentStore
    @ObservedObject var settings: Settings
    @ObservedObject var detection: DetectionSettings

    @StateObject private var strings: StringTuners
    /// How many dials across. Defaults to the string count and is adjustable
    /// on the screen — how big is a preference, not a constant.
    @State private var columns: Int
    @State private var isShowingDebug = false
    @State private var isShowingLockDialog = false

    /// The instance as constructed, for while the store catches up and as the
    /// identity to look the live value up by.
    private let initial: InstrumentInstance

    init(
        instance: InstrumentInstance, store: InstrumentStore,
        audio: AudioSessionController, settings: Settings, detection: DetectionSettings
    ) {
        self.audio = audio
        self.store = store
        self.settings = settings
        self.detection = detection
        self.initial = instance
        _strings = StateObject(
            wrappedValue: StringTuners(
                instrument: instance.instrument, audio: audio,
                reference: instance.reference, tuning: detection.tuning))
        _columns = State(initialValue: Self.defaultColumns(strings: instance.strings.count))
    }

    /// The live instance — the store's copy, since tuning and reference can
    /// change right on this screen.
    private var instance: InstrumentInstance {
        store.instance(id: initial.id) ?? initial
    }

    var body: some View {
        ScrollView {
            // Whether the app can hear anything at all — the same meter, size
            // and axis as the chromatic screen's. The per-string bars can't
            // answer this: they're zero both in a quiet room and when sound is
            // coming in that isn't near any string's target.
            LevelMeter(level: strings.inputLevel)
                .frame(width: 72, height: 4)
                .padding(.top, 6)
            // Lazy so cost tracks the viewport rather than the string count —
            // which keeps "only track what's on screen" reachable later, and
            // lets an arbitrary tuning scale.
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(Array(strings.tuners.enumerated()), id: \.offset) { index, tuner in
                    // A cell is a link into its string's full-screen view —
                    // the grid shows all of them, the string view holds one.
                    NavigationLink(value: TunerRoute.string(instance.id, index)) {
                        StringCell(tuner: tuner, naming: settings.naming)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("grid.cell.\(index)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle(instance.nameText)
        .toolbar {
            ToolbarItem(placement: .principal) { tuningMenu }
            ToolbarItem(placement: .primaryAction) { layoutMenu }
        }
        .accessibilityIdentifier("grid.strings")
        .task { strings.attachAll() }
        .onDisappear { strings.detachAll() }
        // The instance owns its state; whenever the store's copy moves —
        // tuning switched, reference stepped, here or anywhere — the dials
        // retarget.
        .onChangeCompat(of: instance) { _ in reconfigure() }
        // Two separate paths on purpose. A band change has to rebuild the
        // detectors — the band is baked into their lag bounds — while a
        // threshold change must not, or dragging a slider would reset the
        // smoothing on every tick and the dial would jump for reasons that have
        // nothing to do with the threshold under test.
        .onChangeCompat(of: detection.tuning.maxSemitonesFromString) { _ in
            reconfigure()
        }
        .onChangeCompat(of: detection.tuning) { tuning in
            strings.retune(tuning)
        }
        .sheet(isPresented: $isShowingDebug) {
            DetectorDebugView(
                detection: detection, strings: strings, naming: settings.naming)
        }
        .lockDoorDialog(isPresented: $isShowingLockDialog) {
            store.setLocked(id: instance.id, false)
        }
    }

    private func reconfigure() {
        strings.configure(
            instrument: instance.instrument, reference: instance.reference,
            tuning: detection.tuning)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    /// The reference belongs on this screen: it's what every dial is measured
    /// against, and it's adjusted in the moment. It's the *instance's*
    /// reference — this instrument stays at 442 without dragging the rest of
    /// the app there.
    private var footer: some View {
        ReferencePitchStepper(
            reference: Binding(
                get: { instance.reference },
                set: { store.setReference(id: instance.id, $0) }),
            naming: settings.naming
        )
        .lockedDoor(instance.isLocked, isPresenting: $isShowingLockDialog)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    /// The tuning, front and centre — "Drop D" is what this screen is *for*,
    /// so it's the header control rather than a buried setting. Only tunings
    /// that fit this instrument's strings are offered at all: a mismatched
    /// count is a type error, not a runtime surprise.
    private var tuningMenu: some View {
        Menu {
            ForEach(fittingTunings, id: \.self) { tuning in
                Button {
                    store.setTuning(id: instance.id, strings: tuning.strings)
                } label: {
                    if tuning.strings == instance.strings {
                        Label {
                            tuningText(tuning.name ?? "Custom")
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        tuningText(tuning.name ?? "Custom")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if instance.isLocked {
                    Image(systemName: "lock.fill").font(.caption2)
                }
                tuningText(instance.tuningName ?? "Custom")
                    .font(.callout.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .lockedDoor(instance.isLocked, isPresenting: $isShowingLockDialog)
        .accessibilityIdentifier("grid.tuning")
    }

    /// Catalog names are localizable; a user's custom tuning has no name to
    /// translate, and "Custom" is the catalog's word for that.
    private func tuningText(_ name: String) -> Text {
        Text(LocalizedStringKey(name), bundle: .module)
    }

    private var fittingTunings: [Tuning] {
        guard let template = instance.template else { return [] }
        return template.knownTunings.filter { $0.strings.count == instance.strings.count }
    }

    private var layoutMenu: some View {
        Menu {
            Picker(selection: $columns) {
                ForEach(1...3, id: \.self) { count in
                    Text("\(count) across", bundle: .module).tag(count)
                }
            } label: {
                Text("Columns", bundle: .module)
            }

            Divider()

            Button {
                if instance.isLocked {
                    isShowingLockDialog = true
                } else {
                    store.setLocked(id: instance.id, true)
                }
            } label: {
                Label {
                    instance.isLocked
                        ? Text("Unlock", bundle: .module) : Text("Lock", bundle: .module)
                } icon: {
                    Image(systemName: instance.isLocked ? "lock.open" : "lock")
                }
            }
            .accessibilityIdentifier("grid.lock")

            if LaunchStores.isDebug {
                Divider()
                Button {
                    isShowingDebug = true
                } label: {
                    Label {
                        Text(verbatim: "Detector…")
                    } icon: {
                        Image(systemName: "waveform.badge.magnifyingglass")
                    }
                }
                .accessibilityIdentifier("grid.debug")
            }
        } label: {
            // A badge while anything is off its shipped value, so a surprising
            // reading is never mistaken for how the app actually behaves.
            Image(
                systemName: detection.isModified
                    ? "square.grid.2x2.fill" : "square.grid.2x2"
            )
            .foregroundStyle(detection.isModified ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
        }
        .accessibilityIdentifier("grid.columns")
        .accessibilityLabel(Text("Columns", bundle: .module))
    }

    /// Few strings want fewer, wider cells; many want more across so the grid
    /// doesn't run off the screen.
    private static func defaultColumns(strings: Int) -> Int {
        strings > 4 ? 3 : 2
    }
}

/// One cell, observing its own string's model.
private struct StringCell: View {
    @ObservedObject var tuner: StringTunerViewModel
    let naming: NoteNaming

    var body: some View {
        CompactDial(name: tuner.target.name(in: naming), cents: cents, level: tuner.level)
    }

    private var cents: Double? {
        if case .reading(let cents, _) = tuner.state { return cents }
        return nil
    }
}

extension View {
    /// The doors rule for a locked instrument's controls: never mutating,
    /// never ignoring a touch. The control keeps its looks, loses its
    /// function, and any tap on it raises the unlock offer instead — so the
    /// novice discovers the way forward with the only gesture anyone tries
    /// first, and a stray tap on a music stand dies at a dialog.
    @ViewBuilder
    func lockedDoor(_ isLocked: Bool, isPresenting: Binding<Bool>) -> some View {
        if isLocked {
            self
                .disabled(true)
                .overlay(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isPresenting.wrappedValue = true }
                )
        } else {
            self
        }
    }

    /// The unlock offer every door opens onto.
    func lockDoorDialog(isPresented: Binding<Bool>, unlock: @escaping () -> Void) -> some View {
        alert(
            Text("This instrument is locked", bundle: .module),
            isPresented: isPresented
        ) {
            Button(action: unlock) {
                Text("Unlock", bundle: .module)
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text("Unlock to make changes?", bundle: .module)
        }
    }
}
