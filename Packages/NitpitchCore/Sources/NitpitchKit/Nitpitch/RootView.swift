import NitpitchCore
import SwiftUI

/// Where the app can navigate to.
///
/// A typed path rather than a `NavigationPath`: popping to a known point
/// stays a one-liner.
public enum TunerRoute: Hashable {
    /// The instrument list. Pushed, not presented: back from a grid lands
    /// here, on the list you chose from, the way the mental model expects.
    case chooser
    /// An instrument *instance* by id — "Strat", not "guitar". The default
    /// instance of a template shares the template's id, so a route made from
    /// a template reaches the right place before the instance even exists.
    case instrument(String)
    /// One string of an instance, full screen — the coarse-tuning home.
    case string(String, Int)
}

/// The app's navigation. The chromatic tuner is the root; an instrument is a
/// destination rather than a setting.
public struct RootView: View {
    @ObservedObject private var settings: Settings
    private let audio: AudioSessionController
    /// The stores and the engine live in the APP SHELLS now (the watch
    /// taught the pattern): the Mac's Settings scene is a sibling of the
    /// tuner window, and the sync switch that lives there needs the same
    /// engine this hierarchy syncs through.
    @ObservedObject private var store: InstrumentStore
    @ObservedObject private var presets: PresetStore
    @ObservedObject private var sync: SyncEngine
    @State private var path: [TunerRoute] = []
    /// Created here rather than passed in: it lives for the session, resets on
    /// every launch, and nothing outside the tuner hierarchy has any business
    /// reading it.
    @StateObject private var detection = DetectionSettings()
    /// Tuning vs the intonation check, shared by the grid and the string
    /// view — one workflow, two screens (see `IntonationMode`).
    @StateObject private var intonationMode = IntonationMode()
    /// A shared preset that just arrived, driving the import sheet.
    @State private var arrival: PresetArrival?
    /// An instrument shape to create — an orphaned preset's way back.
    @State private var pendingInstrumentShape: InstrumentShape?

    public init(
        settings: Settings, audio: AudioSessionController,
        store: InstrumentStore, presets: PresetStore, sync: SyncEngine
    ) {
        self.settings = settings
        self.audio = audio
        self.store = store
        self.presets = presets
        self.sync = sync
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ChromaticTunerView(
                settings: settings, audio: audio, store: store, presets: presets, sync: sync,
                onOpenChooser: { path.append(.chooser) },
                onChooseInstance: { id in path.append(.instrument(id)) },
                onChoosePin: { id, presetID in openPin(instrument: id, preset: presetID) },
                onCreateInstrument: { shape in
                    pendingInstrumentShape = shape
                    path = [.chooser]
                }
            )
            .navigationDestination(for: TunerRoute.self) { route in
                switch route {
                case .chooser:
                    InstrumentChooser(
                        settings: settings, store: store, presets: presets,
                        // Set when an orphaned preset asked for an
                        // instrument that fits it; the chooser opens its
                        // creation sheet already shaped, then clears this.
                        pendingShape: $pendingInstrumentShape
                    ) { id in
                        path.append(.instrument(id))
                    }
                case .instrument(let id):
                    if let instance = resolve(id) {
                        InstrumentGridView(
                            instance: instance, store: store, presets: presets,
                            audio: audio, settings: settings, detection: detection,
                            intonationMode: intonationMode,
                            onOpenCreated: { created in
                                // REPLACE rather than push: the instrument
                                // that was just made from this one takes
                                // this screen's place, so Back still leads
                                // to the list instead of stacking the old
                                // instrument behind the new one.
                                path = [.chooser, .instrument(created)]
                            }
                        )
                        // Identity per INSTRUMENT, not per route slot.
                        // Replacing the top of the stack with another
                        // `.instrument` reuses this view — and its
                        // StateObject tuners, one per string of the OLD
                        // instrument — so a five-string instrument
                        // arrived at a four-string screen. `.id` forces
                        // a fresh view, which builds the right tuners.
                        .id(instance.id)
                    }
                case .string(let id, let index):
                    if let instance = resolve(id) {
                        StringView(
                            instance: instance, index: index, store: store,
                            audio: audio, settings: settings, detection: detection,
                            intonationMode: intonationMode)
                    }
                }
            }
            // The root's header IS the system bar now — the meter rides its
            // principal slot and the gear is a real toolbar item (see
            // `ChromaticTunerView`), so hiding it would hide the header.
        }
        // Escape goes up a level, the Mac's answer to the phone's edge
        // swipe — which macOS has no equivalent of, leaving the toolbar's
        // back button as the only way out of a pushed screen.
        //
        // A KEY EQUIVALENT (hidden button), deliberately not `onKeyPress`:
        // key presses only reach the focused view hierarchy, and the grid
        // and chooser focus nothing — the string view's arrow keys need
        // `.focusable()` + focus-on-appear to work for exactly that reason.
        // A key equivalent dispatches through the window regardless of
        // focus, and a modal sheet intercepts it first, so sheet Cancel
        // (`.cancelAction`) keeps winning while one is up. Disabled at the
        // root rather than a no-op: a disabled equivalent frees the key.
        #if os(macOS)
        .background {
            Button {
                path.removeLast()
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(path.isEmpty)
            .opacity(0)
            .accessibilityHidden(true)
        }
        #endif
        .onOpenURL { receive($0) }
        // Universal links (https://nitpitch.app/t#…). iOS hands them to
        // `onOpenURL`; macOS delivers them as a browsing-web user activity,
        // so both are wired to the same receiver — the codec accepts both
        // spellings and refuses everything else.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                receive(url)
            }
        }
        .sheet(item: $arrival) { arrival in
            presetArrivalSheet(arrival)
        }
        // Syncing starts here rather than in `init`: reaching the iCloud
        // daemon is a variable-latency call, and doing it during view
        // construction put that latency in front of the first frame.
        .task { await sync.begin() }
        // The demo route (`-demo-open violin`): straight onto the screen
        // whose layout is being judged. Pushed a beat after launch — seeding
        // the path any earlier (init, even `onAppear`) reliably left the
        // macOS window unmade.
        .task {
            guard let route = LaunchStores.demoRoute, path.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            path = [.instrument(route)]
        }
        // Forced onto the whole hierarchy, destinations included; nil follows
        // the system.
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    /// A shared preset arriving from outside (`nitpitch://preset#…`).
    ///
    /// The link names a template, not an instrument, so this picks the
    /// receiver's instrument to apply it to: the most recently used one of
    /// that template whose string count fits — "my guitar" rather than an
    /// arbitrary one — and refuses when they own none, since a preset that
    /// fits nothing has nowhere to go.
    private func receive(_ url: URL) {
        guard let link = PresetLinkCodec.link(from: url) else {
            arrival = .unreadable
            return
        }
        let candidates =
            store.instances
            .filter { $0.templateID == link.templateID && $0.strings.count == link.strings.count }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
        guard let target = candidates.first else {
            arrival = .noInstrument(link)
            return
        }
        arrival = .offer(
            link: link, instrumentID: target.id,
            resolution: PresetImport.resolve(
                link: link, existing: presets.existingNames(templateID: link.templateID)))
    }

    /// A pin's tap: load the preset — an explicit pick, exactly as if
    /// chosen from the tuning menu — then open the instrument. A locked
    /// instrument only opens: the navigation half of a pin is not a
    /// change, and the toolbar padlock explains on arrival.
    private func openPin(instrument id: String, preset presetID: String) {
        if let instance = resolve(id), !instance.isLocked {
            if let name = CatalogPinID.tuningName(
                in: presetID, templateID: instance.templateID),
                let tuning = instance.template?.knownTunings
                    .first(where: { $0.name == name })
            {
                // A catalog pin applies the tuning — pitches only, exactly
                // the tuning menu's semantics.
                store.setTuning(id: instance.id, strings: tuning.strings)
            } else if let preset = presets.presets.first(where: { $0.id == presetID }) {
                presets.load(preset, onto: instance, in: store)
            }
        }
        path.append(.instrument(id))
    }

    @ViewBuilder
    private func presetArrivalSheet(_ arrival: PresetArrival) -> some View {
        switch arrival {
        case .offer(let link, let instrumentID, let resolution):
            if let instance = resolve(instrumentID) {
                PresetImportView(
                    link: link,
                    instrumentName: instance.name,
                    summary: PresetPayloadSummary.text(
                        strings: link.strings, referenceHz: link.referenceHz,
                        temperament: link.temperament),
                    resolution: resolution,
                    onLoadOnce: {
                        // Trying a friend's tuning is not a commitment to
                        // store it: the values land on the instrument and
                        // nothing joins the collection.
                        store.setTuning(id: instance.id, strings: link.strings)
                        if let hz = link.referenceHz {
                            store.setReference(id: instance.id, ReferencePitch(hz: hz))
                        }
                        if let temperament = link.temperament {
                            store.setTemperament(id: instance.id, temperament)
                        }
                        path = [.instrument(instance.id)]
                    },
                    onSave: { chosen in
                        if let saved = presets.importing(link, as: chosen) {
                            presets.load(saved, onto: instance, in: store)
                        }
                        path = [.instrument(instance.id)]
                    })
            }
        case .noInstrument(let link):
            PresetArrivalProblemView(
                message: Text(
                    "This preset is for an instrument you don't have yet. Add one, then open the link again.",
                    bundle: .module),
                detail: PresetPayloadSummary.text(
                    strings: link.strings, referenceHz: link.referenceHz,
                    temperament: link.temperament))
        case .unreadable:
            PresetArrivalProblemView(
                message: Text("This link isn't readable.", bundle: .module),
                detail: nil)
        }
    }

    /// An instance by id — and nothing else: instruments exist only by
    /// seeding or deliberate creation, so navigation never materializes
    /// anything. A route to a deleted instrument simply resolves to nil.
    private func resolve(_ id: String) -> InstrumentInstance? {
        store.instance(id: id)
    }
}
