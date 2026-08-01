import AppKit
import NitpitchCore
import NitpitchKit
import SwiftUI

/// Quits when the last window closes.
///
/// A single-window utility with no documents has nothing to do with no window
/// open, so leaving it running in the Dock is just a stale icon. SwiftUI has no
/// scene modifier for this, so it needs the AppKit delegate hook.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct NitpitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = Settings(defaults: LaunchStores.defaults)
    @Environment(\.openWindow) private var openWindow

    private static let aboutWindowID = "about"

    var body: some Scene {
        WindowGroup {
            NitpitchView(settings: settings)
                // The readout is a fixed-aspect instrument panel; a resizable
                // window is fine but it should open at a sane size.
                .frame(minWidth: 420, minHeight: 320)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Replaces the standard About panel, which shows only the icon,
            // name and version. The app's own is the same shape with the
            // tagline, commit SHA and links added — a slightly enriched panel
            // rather than a different kind of screen.
            CommandGroup(replacing: .appInfo) {
                Button {
                    openWindow(id: Self.aboutWindowID)
                } label: {
                    // Not localized through the Kit catalog: this string lives
                    // in the app target, which has no catalog of its own.
                    Text(verbatim: "About Nitpitch")
                }
            }
        }

        // A window rather than a sheet, so it closes the way every other Mac
        // window does — red button or ⌘W — and needs no Done button inside it.
        // An About panel is read-and-close; there's nothing to confirm.
        Window("About Nitpitch", id: Self.aboutWindowID) {
            AboutView()
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // A `Settings` scene puts Preferences in the app menu with its ⌘,
        // shortcut for free, which is what a Mac user reaches for. The tuner
        // window's gear button is hidden on macOS in favour of this.
        //
        // No About here: the app menu's "About Nitpitch" already opens the
        // system panel, which reads the name, version and icon straight from
        // the bundle. A second About inside preferences would be a different
        // screen showing the same facts.
        Settings {
            SettingsView(settings: settings)
                // A separate scene doesn't inherit the main window's
                // `.preferredColorScheme`, so without this the preferences
                // window stays on the system appearance while the tuner
                // honours a Light/Dark override — the setting appearing not to
                // work in the very window you set it from.
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
