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
    case instrument(Instrument)
}

/// The app's navigation. The chromatic tuner is the root; an instrument is a
/// destination rather than a setting.
public struct RootView: View {
    @ObservedObject private var settings: Settings
    private let audio: AudioSessionController
    @State private var path: [TunerRoute] = []
    /// Created here rather than passed in: it lives for the session, resets on
    /// every launch, and nothing outside the tuner hierarchy has any business
    /// reading it.
    @StateObject private var detection = DetectionSettings()

    public init(settings: Settings, audio: AudioSessionController) {
        self.settings = settings
        self.audio = audio
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ChromaticTunerView(
                settings: settings, audio: audio,
                onOpenChooser: { path.append(.chooser) },
                onChooseInstrument: { instrument in
                    settings.instrument = instrument
                    path.append(.instrument(instrument))
                }
            )
            .navigationDestination(for: TunerRoute.self) { route in
                switch route {
                case .chooser:
                    InstrumentChooser(settings: settings) { instrument in
                        settings.instrument = instrument
                        path.append(.instrument(instrument))
                    }
                case .instrument(let instrument):
                    InstrumentGridView(
                        instrument: instrument, audio: audio, settings: settings,
                        detection: detection)
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
}
