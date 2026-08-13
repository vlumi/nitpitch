import SwiftUI

/// The wrist tuner: chromatic only, deliberately — favorites, presets and
/// the haptic vocabulary come later, riding the shipped iCloud sync rather
/// than a bespoke protocol (see ROADMAP § Watch app). This scaffold exists
/// to answer the field unknowns: the real microphone response, and which
/// session modes watchOS actually grants.
@main
struct NitpitchWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTunerView()
        }
    }
}
