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
        // The stores and the engine are owned HERE (the watch taught the
        // pattern): the Settings screen carries the sync switch on every
        // platform, and on the Mac that screen is a sibling SCENE the tuner
        // hierarchy can't reach into.
        let settings = Settings(defaults: LaunchStores.defaults)
        // A new instrument's reference seeds from the chromatic screen's —
        // "from wherever you came from".
        let store = InstrumentStore(defaults: LaunchStores.defaults) {
            settings.reference
        }
        let presets = PresetStore(defaults: LaunchStores.defaults)
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        _presets = StateObject(wrappedValue: presets)
        // Constructed cheaply — the engine touches iCloud only from
        // `begin()`, which RootView schedules in a task.
        _sync = StateObject(
            wrappedValue: SyncEngine(
                store: LaunchStores.syncStore(),
                instruments: store, presets: presets, settings: settings,
                defaults: LaunchStores.defaults))
    }

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, audio: audio, store: store, presets: presets, sync: sync)
                .capturesWhileActive(audio)
        }
    }
}
