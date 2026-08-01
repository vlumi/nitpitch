import NitpitchCore
import NitpitchKit
import SwiftUI

@main
struct NitpitchApp: App {
    @StateObject private var settings = Settings(defaults: LaunchStores.defaults)

    var body: some Scene {
        WindowGroup {
            NitpitchView(settings: settings)
                // The readout is a fixed-aspect instrument panel; a resizable
                // window is fine but it should open at a sane size.
                .frame(minWidth: 420, minHeight: 320)
        }
        .windowResizability(.contentMinSize)
    }
}
