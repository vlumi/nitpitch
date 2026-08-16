import NitpitchCore
import NitpitchData
import SwiftUI

/// The wrist tuner: chromatic, the hands-free one-string-at-a-time mode,
/// and — through the same iCloud sync the phone and Mac ride — YOUR
/// instruments, presets, favorites and locks. The watch is the second
/// device that makes sync earn its keep; the phone and Mac stay the
/// management surfaces, the wrist tunes.
@main
struct NitpitchWatchApp: App {
    @StateObject private var settings: Settings
    @StateObject private var store: InstrumentStore
    @StateObject private var presets: PresetStore
    @StateObject private var sync: SyncEngine

    init() {
        // LaunchStores is the single isolation gate, same as the phone:
        // under -uitest-clean everything swaps to a wiped ephemeral suite.
        let stores = AppStores.make()
        _settings = StateObject(wrappedValue: stores.settings)
        _store = StateObject(wrappedValue: stores.instruments)
        _presets = StateObject(wrappedValue: stores.presets)
        _sync = StateObject(wrappedValue: stores.sync)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store, presets: presets, settings: settings, sync: sync)
                .task { await sync.begin() }
        }
    }
}
