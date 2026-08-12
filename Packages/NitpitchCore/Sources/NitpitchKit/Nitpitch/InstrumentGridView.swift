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
    /// overwrite, and which payloads ride along.
    struct PendingReplace {
        let preset: Preset
        let includeReference: Bool
        let includeTemperament: Bool
    }

    @State var pendingReplace: PendingReplace?
    @State var isManagingPresets = false
    /// The grid's own management flows — the chooser's swipe actions were
    /// findable by the initiated; the … menu is findable by everyone.
    @State var isRenamingInstrument = false
    @State var instrumentRenameText = ""
    @State var duplicating: Creation?
    @State var isEditingStrings = false
    /// The intonation check across every string — behind a toggle here,
    /// unlike the string view's ambient panel: the grid is a tuning surface
    /// first, and the octave layer is a chosen session. Screen state, not
    /// a setting: a measuring session belongs to the visit that ran it.
    @State var isIntonating = false
    @Environment(\.dismiss) var dismissGrid
    /// Replace this screen with another instrument's — the one just made
    /// from it. Nil where the caller owns no navigation.
    var onOpenCreated: ((String) -> Void)?

    /// The instance as constructed, for while the store catches up and as the
    /// identity to look the live value up by.
    let initial: InstrumentInstance

    init(
        instance: InstrumentInstance, store: InstrumentStore, presets: PresetStore,
        audio: AudioSessionController, settings: Settings, detection: DetectionSettings,
        onOpenCreated: ((String) -> Void)? = nil
    ) {
        self.onOpenCreated = onOpenCreated
        self.audio = audio
        self.store = store
        self.presets = presets
        self.settings = settings
        self.detection = detection
        self.initial = instance
        _strings = StateObject(
            wrappedValue: StringTuners(
                instrument: instance.instrument, audio: audio,
                reference: instance.reference,
                temperament: instance.appliedTemperament,
                tuning: detection.tuning))
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
        // BEFORE the footer joins: applied any later, the identifier stamps
        // the inset's own buttons — the reference speaker and the
        // temperament chip both read "grid.strings" to accessibility, ids
        // clobbered exactly as the string view's comment warns.
        .accessibilityIdentifier("grid.strings")
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
        .task {
            strings.attachAll()
            // Recency feeds "my instruments" ordering — opening counts.
            store.markUsed(id: initial.id)
        }
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
        .onChangeCompat(of: isIntonating) { on in
            strings.setIntonating(on)
        }
        .sheet(isPresented: $isShowingDebug) {
            DetectorDebugView(
                detection: detection, strings: strings, naming: settings.naming)
        }
        .sheet(isPresented: $isManagingPresets) {
            PresetManager(presets: presets, settings: settings, instance: instance)
        }
        .sheet(item: $duplicating) { creation in
            InstrumentCreator(
                store: store, settings: settings, template: creation.template,
                source: creation.source,
                onCreated: { created in
                    // Made from HERE — a duplicate, or the differently
                    // strung instrument "Change string count…" leads to —
                    // so this screen becomes that instrument. Staying on
                    // the old one leaves the result invisible, and going
                    // back to the list makes the user find it.
                    //
                    // Deferred a turn: the sheet is dismissing, and
                    // rewriting the navigation path while the screen that
                    // OWNS the sheet is being replaced loses the change.
                    Task { @MainActor in
                        onOpenCreated?(created.id)
                    }
                })
        }
        .sheet(isPresented: $isEditingStrings) {
            InstrumentEditor(
                store: store, presets: presets, settings: settings, instanceID: instance.id,
                onChangeStringCount: { edited in
                    guard let template = edited.template else { return }
                    duplicating = Creation(template: template, source: edited)
                })
        }
        .alert(
            Text("Rename", bundle: .module),
            isPresented: $isRenamingInstrument
        ) {
            TextField(text: $instrumentRenameText) { Text("Name", bundle: .module) }
                // Fresh identity per presentation — a reused alert TextField
                // keeps its first life's text and ignores the prefill.
                .id(instance.id + (isRenamingInstrument ? "1" : "0"))
            Button {
                store.rename(id: instance.id, to: instrumentRenameText)
            } label: {
                Text("Rename", bundle: .module)
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        }
        .sheet(isPresented: $isSavingPreset) {
            // The payload is chosen right where the save happens: pitches
            // always (they're what a preset IS), reference and temperament
            // each a checkbox — the alert's one-button-per-combination
            // pattern stopped scaling at the third dimension.
            PresetSaver(
                instance: instance, naming: settings.naming, onSave: savePreset)
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
                        includeReference: pending.includeReference,
                        includeTemperament: pending.includeTemperament)
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
            VStack(spacing: 0) {
                // The interval lane: one fixed place in every column count,
                // its height always reserved so a double stop starting or
                // stopping never reflows the dials mid-bow. Adjacent
                // STRINGS aren't reliably adjacent CELLS (a two-column
                // violin puts D and A on a diagonal), so the grid gets a
                // lane and the sounding pair gets a tinted edge; the strips
                // — where the pair genuinely shares a boundary — get the
                // chip on that boundary instead.
                IntervalLane(
                    interval: strings.interval,
                    notes: instance.instrument.notes,
                    naming: settings.naming)
                dialGrid(columns: layout.columns, cellScale: layout.scale)
                    // Cards hug their content instead of stretching into
                    // acres — the emptiness lives outside the cards — but
                    // loosely enough that a single column can still use the
                    // width it was visibly given.
                    .frame(
                        maxWidth: CGFloat(layout.columns) * (330 * layout.scale + 12) + 32
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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

    /// The sheet's choices arriving: remember the name (the replace confirm
    /// needs it) and attempt the save.
    private func savePreset(
        named name: String, includeReference: Bool, includeTemperament: Bool
    ) {
        presetName = name
        attemptSave(includeReference: includeReference, includeTemperament: includeTemperament)
    }

    /// Save, or ask first when the name would overwrite — updating a preset
    /// is a deliberate save, never an accident.
    private func attemptSave(includeReference: Bool, includeTemperament: Bool) {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = presets.existing(named: trimmed, templateID: instance.templateID) {
            pendingReplace = PendingReplace(
                preset: existing, includeReference: includeReference,
                includeTemperament: includeTemperament)
        } else if let saved = presets.save(
            instance, named: trimmed, includeReference: includeReference,
            includeTemperament: includeTemperament)
        {
            // "This setup is called Gig" — so the claim follows the save:
            // the pill and the checkmark move to it immediately.
            store.presetApplied(id: instance.id, presetID: saved.id)
        }
    }

    private func reconfigure() {
        strings.configure(
            instrument: instance.instrument, reference: instance.reference,
            temperament: instance.appliedTemperament,
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

    /// Tuner order as displayed: low string first.
    var displayedTuners: [(index: Int, tuner: StringTunerViewModel)] {
        strings.tuners.enumerated().map { ($0.offset, $0.element) }
    }

    /// The reference belongs on this screen: it's what every dial is measured
    /// against, and it's adjusted in the moment. It's the *instance's*
    /// reference — this instrument stays at 442 without dragging the rest of
    /// the app there.
    private var footer: some View {
        HStack(spacing: 20) {
            // The readout itself is the reference tone's button — tap
            // A=442 to hear it, step ± while it sounds and the pitch
            // follows live. The lock freezes only the ± (isAdjustable):
            // listening changes no state, so the tone stays free on a
            // locked instrument.
            ReferencePitchStepper(
                reference: Binding(
                    get: { instance.reference },
                    set: { store.setReference(id: instance.id, $0) }),
                naming: settings.naming,
                tone: strings.tone,
                toneIdentifier: "grid.tone.reference",
                onToneToggle: {
                    Task { await strings.toggleTone(reference: instance.reference) }
                },
                isAdjustable: !instance.isLocked)
            // The temperament beside the reference — the same kind of
            // fact, worn where you look while tuning. Bowed only.
            if instance.template?.family == .bowed {
                TemperamentChip(temperament: instance.appliedTemperament) {
                    store.setTemperament(
                        id: instance.id,
                        instance.appliedTemperament == .pure ? .equal : .pure)
                }
                .disabled(instance.isLocked)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    /// Zero means Auto: the fill algorithm chooses (see `dialLayout`). The
    /// picker offers fixed counts for anyone who wants denser or looser.
    private static func defaultColumns(strings: Int) -> Int {
        0
    }
}
