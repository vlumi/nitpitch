import SwiftUI

/// The wrist tuner: chromatic, plus the hands-free one-string-at-a-time
/// mode over the catalog instruments (`StringFocus` decides when the pin
/// moves; the crown overrides). Favorites, presets and the beat-rate haptic
/// vocabulary come later, riding the shipped iCloud sync rather than a
/// bespoke protocol (see ROADMAP § Watch app).
@main
struct NitpitchWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
