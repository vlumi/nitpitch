import Foundation

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

    /// Feed the display a synthetic reading instead of the microphone.
    ///
    /// The iOS simulator reports an input device and delivers silence, so the
    /// `.reading` state — the whole populated layout — is otherwise
    /// unreachable there. Under `-demo` the view model drifts a note through
    /// the cent range, which exercises the arc sweep, the colour ramp and the
    /// light strip without an instrument in hand.
    public static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    public static let defaults: UserDefaults = {
        guard isClean else { return .standard }
        let suite = "fi.misaki.nitpitch.uitest"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()
}
