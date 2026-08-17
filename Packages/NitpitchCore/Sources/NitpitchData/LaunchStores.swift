import Foundation
import NitpitchCore

/// The single isolation gate for UI tests.
///
/// Under `-uitest-clean` every store swaps to a wiped, ephemeral defaults suite,
/// so a UI test run can't see or corrupt the developer's real settings and each
/// run starts identical. Everything that persists MUST go through
/// `LaunchStores.defaults` rather than `UserDefaults.standard` — that's what
/// makes the gate total rather than partial.
public enum LaunchStores {
    /// True when launched by a UI test asking for a clean slate.
    public static let isClean = ProcessInfo.processInfo.arguments.contains("-uitest-clean")

    /// Replace the microphone with a synthesized instrument.
    ///
    /// The iOS simulator reports an input device and delivers silence, so the
    /// `.reading` state — the whole populated layout — is otherwise
    /// unreachable there. Under `-demo` the capture source is swapped for
    /// `DemoSignalInput` at the one seam below `AudioSessionController`: the
    /// signal is synthetic, and EVERYTHING else — DSP, smoothing, gating,
    /// beats, the strobe — is the real pipeline hearing it. No view model
    /// contains a line of demo code.
    public static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    /// What the demo plays: `-demo-pose "62,69@-1.8"` holds specific pitches
    /// (see `DemoScore.parse` for the syntax) — for screenshots, where a
    /// staged screen needs exact readings. Without it, the default score
    /// loops through everything the screens can show.
    public static let demoPose: String? = isDemo ? launchArgument("-demo-pose") : nil

    /// The value following a launch flag — the one firstIndex-and-bounds
    /// dance, written once for every flag that carries one.
    private static func launchArgument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    // The audio-side fork (`audioInput()`, choosing microphone vs the
    // demo's synthesized instrument) lives in NitpitchKit — the audio layer
    // is iOS/macOS, while this gate must ride wherever the stores do.

    /// Under `-demo`, start on an instrument's grid instead of the chromatic
    /// root: `-demo -demo-open violin`. Demo mode exists for judging layout
    /// without an instrument in hand; this puts the screen being judged on
    /// screen at launch, without scripting clicks to get there.
    public static let demoRoute: String? = isDemo ? launchArgument("-demo-open") : nil

    /// Show the detector diagnostics screen.
    ///
    /// A launch argument rather than `#if DEBUG` on purpose: the numbers only
    /// mean something against a real instrument in a real room, which means a
    /// device, and often a TestFlight build rather than one run from Xcode.
    /// Gating it out of release builds would put it exactly where it can't be
    /// used. Nothing reaches it without the flag, so a shipped build is
    /// unchanged.
    public static let isDebug = ProcessInfo.processInfo.arguments.contains("-debug")

    /// The key-value store syncing rides. Under UI tests it's a local
    /// stand-in: a test run must never touch the developer's real iCloud
    /// account, and the isolation gate is only total if it covers this
    /// door too.
    public static func syncStore() -> KeyValueSyncStore {
        isClean ? EphemeralSyncStore() : UbiquitousSyncStore()
    }

    public static let defaults: UserDefaults = {
        guard isClean else { return .standard }
        let suite = "fi.misaki.nitpitch.uitest"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()
}

/// The four stores an app shell owns, constructed together — one definition
/// of the wiring the three platform shells used to paste verbatim.
///
/// Built in the one order the seams require: Settings first (a new
/// instrument's reference seeds from the chromatic screen's — "from
/// wherever you came from"), then the stores, then the engine — which
/// touches iCloud only from `begin()`, so constructing it here is cheap.
/// Owned by the SHELL on every platform (the watch taught the pattern):
/// the Settings screen carries the sync switch, and on the Mac that screen
/// is a sibling scene the tuner hierarchy can't reach into.
public struct AppStores {
    public let settings: Settings
    public let instruments: InstrumentStore
    public let presets: PresetStore
    public let sync: SyncEngine

    @MainActor
    public static func make() -> AppStores {
        let settings = Settings(defaults: LaunchStores.defaults)
        let instruments = InstrumentStore(defaults: LaunchStores.defaults) {
            settings.reference
        }
        let presets = PresetStore(defaults: LaunchStores.defaults)
        let sync = SyncEngine(
            store: LaunchStores.syncStore(),
            instruments: instruments, presets: presets, settings: settings,
            defaults: LaunchStores.defaults)
        return AppStores(
            settings: settings, instruments: instruments, presets: presets, sync: sync)
    }
}
