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

    @StateObject private var strings: StringTuners
    /// How many dials across. Defaults to the string count and is adjustable
    /// on the screen — how big is a preference, not a constant.
    @State private var columns: Int
    @State private var isShowingDebug = false
    @State private var isSavingPreset = false
    @State private var presetName = ""
    /// A save waiting on the "replace?" confirmation: the preset it would
    /// overwrite, and whether the reference rides along.
    @State private var pendingReplace: (preset: Preset, includeReference: Bool)?
    @State private var isManagingPresets = false

    /// The instance as constructed, for while the store catches up and as the
    /// identity to look the live value up by.
    private let initial: InstrumentInstance

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
            // The payload choice IS the save button (ROADMAP § 1): a preset
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
                        checked: matches && loadedPreset == nil,
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
                            checked: loadedPreset?.id == preset.id,
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

    /// What the pill says: the preset you picked while you're on it, the
    /// tuning identity otherwise. Drift clears the claim (see
    /// `loadedPresetID`), so the fallback from "test" to "Custom" is honest
    /// rather than a bookkeeping suffix.
    private var pillText: Text {
        if let loaded = loadedPreset {
            return Text(verbatim: loaded.name)
        }
        return tuningText(instance.tuningName ?? "Custom")
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

    /// Catalog names are localizable; a user's custom tuning has no name to
    /// translate, and "Custom" is the catalog's word for that.
    private func tuningText(_ name: String) -> Text {
        Text(LocalizedStringKey(name), bundle: .module)
    }

    /// The user's name verbatim, with the reference riding along when the
    /// preset carries one — the label says what loading will do.
    private func presetLabel(_ preset: Preset) -> Text {
        if let reference = preset.reference {
            return Text(verbatim: "\(preset.name) · A=\(Int(reference.hz))")
        }
        return Text(verbatim: preset.name)
    }

    /// The preset the instance is *on*: last loaded, values still intact, and
    /// still existing — a dangling id after a deletion counts as none.
    private var loadedPreset: Preset? {
        guard let id = instance.loadedPresetID else { return nil }
        return presets.presets(fitting: instance).first { $0.id == id }
    }

    /// Whether loading this preset would change nothing — the equals mark.
    private func valuesMatch(_ preset: Preset) -> Bool {
        instance.strings == preset.strings
            && (preset.referenceHz == nil || preset.referenceHz == instance.referenceHz)
    }

    @ViewBuilder
    private func menuRow(_ label: Text, checked: Bool, matching: Bool) -> some View {
        if checked {
            Label {
                label
            } icon: {
                Image(systemName: "checkmark")
            }
        } else if matching {
            Label {
                label
            } icon: {
                Image(systemName: "equal")
            }
        } else {
            label
        }
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
