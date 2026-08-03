import NitpitchCore
import SwiftUI

/// Where the app can navigate to.
///
/// The enlarged single-string view (ROADMAP § 1) joins later, which is why
/// this is a typed path rather than a `NavigationPath` — popping to a known
/// point stays a one-liner.
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
    /// The instruments you own. Created here: it lives exactly as long as the
    /// navigation that hands its instances out.
    @StateObject private var store: InstrumentStore
    @State private var path: [TunerRoute] = []
    /// Created here rather than passed in: it lives for the session, resets on
    /// every launch, and nothing outside the tuner hierarchy has any business
    /// reading it.
    @StateObject private var detection = DetectionSettings()

    public init(settings: Settings, audio: AudioSessionController) {
        self.settings = settings
        self.audio = audio
        // A new instrument's reference seeds from the chromatic screen's —
        // "from wherever you came from" (ROADMAP § 1).
        _store = StateObject(
            wrappedValue: InstrumentStore(defaults: LaunchStores.defaults) {
                settings.reference
            })
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ChromaticTunerView(
                settings: settings, audio: audio, store: store,
                onOpenChooser: { path.append(.chooser) },
                onChooseInstance: { id in path.append(.instrument(id)) }
            )
            .navigationDestination(for: TunerRoute.self) { route in
                switch route {
                case .chooser:
                    InstrumentChooser(settings: settings, store: store) { id in
                        path.append(.instrument(id))
                    }
                case .instrument(let id):
                    if let instance = resolve(id) {
                        InstrumentGridView(
                            instance: instance, store: store, audio: audio,
                            settings: settings, detection: detection)
                    }
                case .string(let id, let index):
                    if let instance = resolve(id) {
                        StringView(
                            instance: instance, index: index, store: store,
                            audio: audio, settings: settings, detection: detection)
                    }
                }
            }
            // The root has its own header; a system bar above it would be a
            // second, empty row of chrome. Destinations keep theirs, which is
            // where the back button lives.
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        // Forced onto the whole hierarchy, destinations included; nil follows
        // the system.
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    /// An instance by id, materializing the default one when the id names a
    /// template — which is how a favourite chip works before its instrument
    /// has ever been opened.
    private func resolve(_ id: String) -> InstrumentInstance? {
        if let existing = store.instance(id: id) { return existing }
        if let template = Instrument.named(id) {
            return store.defaultInstance(for: template)
        }
        return nil
    }
}
