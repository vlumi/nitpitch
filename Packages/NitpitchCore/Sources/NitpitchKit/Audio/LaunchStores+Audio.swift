import Foundation
import NitpitchCore
import NitpitchData

extension LaunchStores {
    /// The capture source the session controller should be built on — the
    /// microphone, or the demo's synthesized instrument. A dev-only fork,
    /// resolved once at app construction; a MISTYPED pose refuses loudly
    /// rather than silently drifting through a screenshot session.
    ///
    /// Lives HERE, apart from the rest of `LaunchStores` (NitpitchData):
    /// the stores port to every platform, the iOS/macOS audio layer does
    /// not, and the watch has its own capture with the same fork inside.
    public static func audioInput() -> any AudioCapturing {
        guard isDemo else { return AudioInput() }
        guard let pose = demoPose else { return DemoSignalInput(score: .drift) }
        guard let score = DemoScore.parse(pose) else {
            preconditionFailure("Unreadable -demo-pose: \(pose)")
        }
        return DemoSignalInput(score: score)
    }
}
