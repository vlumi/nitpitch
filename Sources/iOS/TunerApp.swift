import SwiftUI
import TunerCore
import TunerKit

@main
struct TunerApp: App {
    // LaunchStores is the single isolation gate: under -uitest-clean these
    // swap to a wiped ephemeral suite (see LaunchStores).
    @StateObject private var settings = Settings(defaults: LaunchStores.defaults)

    var body: some Scene {
        WindowGroup {
            TunerView(settings: settings)
        }
    }
}
