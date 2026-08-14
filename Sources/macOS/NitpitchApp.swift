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
    // Qualified: SwiftUI's `Settings` SCENE shares the bare name on macOS,
    // and an annotation can't lean on inference the way the old inline
    // initializer could.
    @StateObject private var settings: NitpitchKit.Settings
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
    @Environment(\.openWindow) private var openWindow

    private static let aboutWindowID = "about"

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, audio: audio, store: store, presets: presets, sync: sync)
                // Wide enough that the toolbar never collapses the back
                // button into the » overflow (observed at 420), tall enough
                // for the dial to breathe.
                .frame(minWidth: 560, minHeight: 400)
                .capturesWhileActive(audio)
                // A preset link opened from a browser is an EXTERNAL EVENT,
                // and a WindowGroup answers those by spawning a new scene —
                // so clicking a shared link with the app open produced a
                // second tuner window (donpa has the same bug). This is the
                // existing window volunteering for all of them: macOS then
                // routes the URL here, through the same `onOpenURL`, and a
                // new window appears only when none exists — which, since
                // the app quits with its last window, means at launch.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
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
            SettingsView(settings: settings, sync: sync)
                // A separate scene doesn't inherit the main window's
                // `.preferredColorScheme`, so without this the preferences
                // window stays on the system appearance while the tuner
                // honours a Light/Dark override — the setting appearing not to
                // work in the very window you set it from.
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
