import NitpitchCore
import NitpitchKit
import SwiftUI

@main
struct NitpitchApp: App {
    // LaunchStores is the single isolation gate: under -uitest-clean these
    // swap to a wiped ephemeral suite (see LaunchStores).
    @StateObject private var settings = Settings(defaults: LaunchStores.defaults)
    /// One microphone for the whole app — see `AudioSessionController` for why
    /// screens subscribe to it rather than each starting their own engine.
    /// (Under `-demo` the source is a synthesized instrument, chosen at this
    /// one seam — see `LaunchStores.audioInput`.)
    @StateObject private var audio = AudioSessionController(input: LaunchStores.audioInput())

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, audio: audio)
                .capturesWhileActive(audio)
        }
    }
}
