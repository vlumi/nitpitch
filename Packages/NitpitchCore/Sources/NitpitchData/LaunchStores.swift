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
    public static let demoPose: String? = {
        guard isDemo else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demo-pose"),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }()

    // The audio-side fork (`audioInput()`, choosing microphone vs the
    // demo's synthesized instrument) lives in NitpitchKit — the audio layer
    // is iOS/macOS, while this gate must ride wherever the stores do.

    /// Under `-demo`, start on an instrument's grid instead of the chromatic
    /// root: `-demo -demo-open violin`. Demo mode exists for judging layout
    /// without an instrument in hand; this puts the screen being judged on
    /// screen at launch, without scripting clicks to get there.
    public static let demoRoute: String? = {
        guard isDemo else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demo-open"),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }()

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
