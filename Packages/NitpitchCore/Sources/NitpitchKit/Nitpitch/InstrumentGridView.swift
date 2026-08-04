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
/// all autosaved through the store, waiting as you left them. The padlock is
/// a fixed toolbar toggle that freezes the lot: locked controls are simply
/// disabled, the lock itself is the one obvious way back, and nothing pops up
/// to explain — the closed lock over dimmed controls IS the explanation.
struct InstrumentGridView: View {
    let audio: AudioSessionController
    @ObservedObject var store: InstrumentStore
    @ObservedObject var presets: PresetStore
    @ObservedObject var settings: Settings
    @ObservedObject var detection: DetectionSettings

    @StateObject var strings: StringTuners
    /// How many dials across. Defaults to the string count and is adjustable
    /// on the screen — how big is a preference, not a constant.
    @State var columns: Int
    @State var isShowingDebug = false
    @State var isSavingPreset = false
    @State var presetName = ""
    /// A save waiting on the "replace?" confirmation: the preset it would
    /// overwrite, and whether the reference rides along.
    @State var pendingReplace: (preset: Preset, includeReference: Bool)?
    @State var isManagingPresets = false

    /// The instance as constructed, for while the store catches up and as the
    /// identity to look the live value up by.
    let initial: InstrumentInstance

    init(
        instance: InstrumentInstance, store: InstrumentStore, presets: PresetStore,
        audio: AudioSessionController, settings: Settings, detection: DetectionSettings
    ) {
        self.audio = audio
        self.store = store
        self.presets = presets
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
    var instance: InstrumentInstance {
        store.instance(id: initial.id) ?? initial
    }

    var body: some View {
        // The shape chooses the presentation (AGENTS.md): a wide viewport
        // shows the strings as strings — horizontal strips, the light dots
        // carrying the tuning — because that's what wide dial cells were
        // already degenerating into, with a vestigial arc rattling inside.
        // Tall shows the dial grid, its content scaled to the cells.
        GeometryReader { geo in
            ScrollView {
                // Spacing accounted to the point: the chrome constants below
                // and in `dialLayout` must add up to exactly the viewport, or
                // the leftover materializes as a scrollbar over a screen that
                // visibly fits (the implicit content stack's default spacing
                // did exactly that).
                VStack(spacing: 0) {
                    // Whether the app can hear anything at all — the same
                    // meter, size and axis as the chromatic screen's. The
                    // per-string bars can't answer this: they're zero both in
                    // a quiet room and when sound is coming in that isn't
                    // near any string's target.
                    ObservedLevelMeter(level: strings.inputLevel)
                        .padding(.top, 6)
                    gridOrStrips(for: geo.size)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle(instance.nameText)
        // Pinned large on purpose: with .automatic, rotating to landscape
        // collapses the large title and it STAYS collapsed back in portrait
        // (until a scroll) — the viewport quietly gains ~50pt, and the auto
        // layout honestly picks a different column count for it. An SE's
        // guitar flipped 2 columns → strips → 1 column on a rotation
        // round-trip; same screen, three layouts.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) { tuningMenu }
            ToolbarItem(placement: .primaryAction) { lockButton }
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
        .sheet(isPresented: $isManagingPresets) {
            PresetManager(presets: presets, templateID: instance.templateID)
        }
        .alert(Text("Save preset", bundle: .module), isPresented: $isSavingPreset) {
            TextField(text: $presetName) { Text("Name", bundle: .module) }
            // The payload choice IS the save button (AGENTS.md): a preset
            // carries only what it was saved with, decided right here.
            Button {
                attemptSave(includeReference: false)
            } label: {
                Text("Tuning only", bundle: .module)
            }
            Button {
                attemptSave(includeReference: true)
            } label: {
                Text("Tuning and reference", bundle: .module)
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        }
        .alert(
            Text("Replace preset", bundle: .module),
            isPresented: Binding(
                get: { pendingReplace != nil },
                set: { if !$0 { pendingReplace = nil } })
        ) {
            Button(role: .destructive) {
                if let pending = pendingReplace,
                    let saved = presets.save(
                        instance, named: presetName,
                        includeReference: pending.includeReference)
                {
                    store.presetApplied(id: instance.id, presetID: saved.id)
                }
                pendingReplace = nil
            } label: {
                Text("Replace", bundle: .module)
            }
            Button(role: .cancel) {
                pendingReplace = nil
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text(
                "\u{201C}\(pendingReplace?.preset.name ?? "")\u{201D} already exists.",
                bundle: .module)
        }
    }

    /// The presentation for this viewport — strips when wide, dials
    /// otherwise.
    @ViewBuilder
    private func gridOrStrips(for size: CGSize) -> some View {
        if showStrips(for: size) {
            strips(for: size)
        } else {
            let layout = dialLayout(for: size)
            dialGrid(columns: layout.columns, cellScale: layout.scale)
                // Cards hug their content instead of stretching into acres —
                // the emptiness lives outside the cards — but loosely enough
                // that a single column can still use the width it was
                // visibly given.
                .frame(maxWidth: CGFloat(layout.columns) * (330 * layout.scale + 12) + 32)
                .frame(maxWidth: .infinity, alignment: .center)
                // When width caps the scale so the grid can't fill the
                // height, the slack frames the grid on the Mac instead of
                // pooling at the bottom; phones read scrolling content from
                // the top. Claims every point below the meter — the footer
                // inset is already outside the viewport — so no slack is
                // left where the centering can't reach it.
                .frame(
                    minHeight: max(0, size.height - Self.meterChrome),
                    alignment: verticalCentering)
        }
    }

    /// Save, or ask first when the name would overwrite — updating a preset
    /// is a deliberate save, never an accident.
    private func attemptSave(includeReference: Bool) {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = presets.existing(named: trimmed, templateID: instance.templateID) {
            pendingReplace = (existing, includeReference)
        } else if let saved = presets.save(
            instance, named: trimmed, includeReference: includeReference)
        {
            // "This setup is called Gig" — so the claim follows the save:
            // the pill and the checkmark move to it immediately.
            store.presetApplied(id: instance.id, presetID: saved.id)
        }
    }

    private func reconfigure() {
        strings.configure(
            instrument: instance.instrument, reference: instance.reference,
            tuning: detection.tuning)
    }

    /// On iOS the device's shape decides — rotation is a gesture. On the Mac
    /// it's a deliberate toggle: dragging a window edge is not a request to
    /// change metaphors (found immediately in use after shipping the
    /// shape-only rule).
    private func showStrips(for size: CGSize) -> Bool {
        #if os(macOS)
        return settings.stripsOnMac
        #else
        return size.width > size.height * 1.3
        #endif
    }

    /// On the Mac the window is continuously resizable, so a fixed column
    /// count fights it — columns follow the width there. iOS keeps the
    /// picker: discrete devices, deliberate density choice.
    private func effectiveColumns(for width: CGFloat) -> Int {
        #if os(macOS)
        return max(1, min(4, Int(width / 300)))
        #else
        return columns
        #endif
    }

    /// Tuner order as displayed: low string first.
    var displayedTuners: [(index: Int, tuner: StringTunerViewModel)] {
        strings.tuners.enumerated().map { ($0.offset, $0.element) }
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
        .disabled(instance.isLocked)
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
            // Two marks with two meanings. The CHECK is identity: the row you
            // picked — the loaded preset, or the tuning when nothing loaded.
            // The EQUALS asserts an action, not object equality: "loading
            // this would change nothing". For a tuning-only preset that stays
            // exactly true whatever the reference is — it says nothing about
            // the reference, and its label (no "· A=442" suffix) already
            // declares that scope. Without the split, a preset saved from
            // Standard and Standard itself both showed checked — true, but
            // reading as a contradiction.
            ForEach(fittingTunings, id: \.self) { tuning in
                let matches = tuning.strings == instance.strings
                Button {
                    store.setTuning(id: instance.id, strings: tuning.strings)
                } label: {
                    menuRow(
                        tuningText(tuning.name ?? "Custom"),
                        checked: matches && claimIsFree,
                        matching: matches)
                }
            }

            let fitting = presets.presets(fitting: instance)
            if !fitting.isEmpty {
                Divider()
                ForEach(fitting) { preset in
                    Button {
                        presets.load(preset, onto: instance, in: store)
                    } label: {
                        menuRow(
                            presetLabel(preset),
                            checked: loadedPreset?.id == preset.id && valuesMatch(preset),
                            matching: valuesMatch(preset))
                    }
                }
            }

            Divider()
            Button {
                presetName = ""
                isSavingPreset = true
            } label: {
                Label {
                    Text("Save as preset…", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            if !fitting.isEmpty {
                Button {
                    isManagingPresets = true
                } label: {
                    Label {
                        Text("Edit presets…", bundle: .module)
                    } icon: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                pillText
                    .font(.callout.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(instance.isLocked)
        .accessibilityIdentifier("grid.tuning")
    }

    /// What the pill says: the preset you picked — with "(edited)" once a
    /// granular edit drifts from its payload — or the tuning identity when
    /// nothing is claimed. Only an explicit menu pick replaces the claim;
    /// without the suffix, stepping one string of "T-bird" made the pill
    /// announce "Drop D", a catalog tuning nobody picked.
    private var pillText: Text {
        guard let loaded = loadedPreset else {
            return tuningText(instance.tuningName ?? "Custom")
        }
        if valuesMatch(loaded) {
            return Text(verbatim: loaded.name)
        }
        return Text("\(loaded.name) (edited)", bundle: .module)
    }

    /// The padlock, ambient and fixed: one glance says whether this
    /// instrument's setup is frozen, one tap flips it. Closed and prominent
    /// when locked, open and quiet when not — the same glyph pair every
    /// platform uses for exactly this.
    private var lockButton: some View {
        Button {
            store.setLocked(id: instance.id, !instance.isLocked)
        } label: {
            Image(systemName: instance.isLocked ? "lock.fill" : "lock.open")
                .foregroundStyle(
                    instance.isLocked ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .accessibilityIdentifier("grid.lock")
        .accessibilityLabel(
            instance.isLocked
                ? Text("Unlock", bundle: .module) : Text("Lock", bundle: .module))
    }

    private var layoutMenu: some View {
        Menu {
            Picker(selection: $columns) {
                // Auto is the default and must stay reachable — without this
                // row, picking a fixed count was a one-way door.
                Text("Auto", bundle: .module).tag(0)
                ForEach(1...3, id: \.self) { count in
                    Text("\(count) across", bundle: .module).tag(count)
                }
            } label: {
                Text("Columns", bundle: .module)
            }

            // The Mac's way into the strips: its window doesn't rotate, so
            // the metaphor is a deliberate choice here, not a shape. A view
            // switch, not a preference — which is why it lives in the layout
            // menu while the strip *order* lives in Settings.
            #if os(macOS)
            Divider()
            Toggle(isOn: $settings.stripsOnMac) {
                Text("Strings as strips", bundle: .module)
            }
            #endif

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

    /// Zero means Auto: the fill algorithm chooses (see `dialLayout`). The
    /// picker offers fixed counts for anyone who wants denser or looser.
    private static func defaultColumns(strings: Int) -> Int {
        0
    }
}
