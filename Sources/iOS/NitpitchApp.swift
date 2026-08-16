import NitpitchCore
import NitpitchKit
import SwiftUI

@main
struct NitpitchApp: App {
    // LaunchStores is the single isolation gate: under -uitest-clean these
    // swap to a wiped ephemeral suite (see LaunchStores).
    @StateObject private var settings: Settings
    @StateObject private var store: InstrumentStore
    @StateObject private var presets: PresetStore
    @StateObject private var sync: SyncEngine
    /// One microphone for the whole app — see `AudioSessionController` for why
    /// screens subscribe to it rather than each starting their own engine.
    /// (Under `-demo` the source is a synthesized instrument, chosen at this
    /// one seam — see `LaunchStores.audioInput`.)
    @StateObject private var audio = AudioSessionController(input: LaunchStores.audioInput())

    init() {
        // The stores and the engine are owned HERE, one shared wiring for
        // all three shells — see AppStores.
        let stores = AppStores.make()
        _settings = StateObject(wrappedValue: stores.settings)
        _store = StateObject(wrappedValue: stores.instruments)
        _presets = StateObject(wrappedValue: stores.presets)
        _sync = StateObject(wrappedValue: stores.sync)
    }

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, audio: audio, store: store, presets: presets, sync: sync)
                .capturesWhileActive(audio)
        }
    }
}
