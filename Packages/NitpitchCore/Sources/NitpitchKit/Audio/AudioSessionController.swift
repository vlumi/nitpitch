import Foundation
import NitpitchCore
import SwiftUI

/// The app's one microphone: a single engine and session, fanned out to any
/// number of listeners.
///
/// Screens subscribe for analysis windows and unsubscribe when they go away.
/// They do **not** own the capture — that's the whole point of this type.
///
/// Two problems it exists to solve:
///
/// - **One engine, one session.** `AudioInput` owns an `AVAudioEngine`, and on
///   iOS starting it activates the *process-global* `AVAudioSession`. Two live
///   instances would contend for the same input node, and whichever stopped
///   last would deactivate the session out from under the other.
/// - **`onWindow` has room for one writer.** It's a single closure, so two
///   consumers assigning it means the last one silently wins. This sets it
///   once, in `init`, and delivers to every subscriber.
///
/// Capture runs while the app is in the foreground rather than being tied to
/// which screen is showing. Stopping when the last subscriber leaves would
/// churn the session on every navigation — on iOS that's a route change and a
/// few hundred milliseconds of dead microphone — and a tuner has no foreground
/// state where it shouldn't be listening.
@MainActor
public final class AudioSessionController: ObservableObject {
    public enum Status: Equatable {
        /// Not started, or suspended while backgrounded.
        case idle
        /// The user refused microphone access.
        case permissionDenied
        /// Started, but the system reported no usable input device.
        case unavailable
        case running
    }

    @Published public private(set) var status: Status = .idle

    /// Hands back windows until it's cancelled or released.
    ///
    /// A class so that dropping the reference is enough to unsubscribe — a
    /// screen going away shouldn't have to remember to clean up.
    public final class Subscription {
        private let id: UUID
        private weak var controller: AudioSessionController?

        init(id: UUID, controller: AudioSessionController) {
            self.id = id
            self.controller = controller
        }

        public func cancel() {
            controller?.unsubscribe(id)
            controller = nil
        }

        deinit {
            controller?.unsubscribe(id)
        }
    }

    private let input: AudioInput
    /// The subscriber table, with its own lock rather than actor isolation:
    /// windows arrive on the analysis queue, and a subscription can be
    /// released from any thread.
    private nonisolated let receivers = ReceiverTable()

    /// The rate detectors should be built for — the converted rate, not the
    /// hardware's.
    public var sampleRate: Double { input.sampleRate }

    public init(input: AudioInput = AudioInput()) {
        self.input = input
        // Assigned exactly once. Every subscriber is reached from here.
        let receivers = self.receivers
        self.input.onWindow = { window in
            for receive in receivers.all() { receive(window) }
        }
    }

    /// Start capturing, asking for permission if it hasn't been granted yet.
    ///
    /// Safe to call repeatedly — `AudioInput.start()` is a no-op while running.
    public func activate() async {
        guard await AudioInput.requestPermission() else {
            status = .permissionDenied
            return
        }
        do {
            try input.start()
            status = .running
        } catch {
            status = .unavailable
        }
    }

    /// Stop capturing and release the session, for backgrounding.
    ///
    /// Subscriptions survive: returning to the foreground calls `activate()`
    /// again and windows resume flowing to whoever is still listening.
    public func suspend() {
        input.stop()
        status = .idle
    }

    /// Receive every analysis window until the subscription is released.
    ///
    /// Delivered on the analysis queue, as `AudioInput.onWindow` is — the
    /// consumer hops to main itself so the UI update is one hop, not two.
    /// Nonisolated: the receiver table has its own lock, and a subscription
    /// being released can happen on any thread. Only `status` needs the actor.
    public nonisolated func subscribe(_ receive: @escaping ([Float]) -> Void) -> Subscription {
        let id = receivers.add(receive)
        return Subscription(id: id, controller: self)
    }

    nonisolated func unsubscribe(_ id: UUID) {
        receivers.remove(id)
    }
}

extension View {
    /// Runs capture for as long as the scene is active.
    ///
    /// Lives here rather than in the app shells so the policy is stated once:
    /// capture follows the *scene*, not whichever screen happens to be
    /// showing. Tying it to a screen would release the shared session on every
    /// navigation, interrupting anyone else listening.
    public func capturesWhileActive(_ audio: AudioSessionController) -> some View {
        modifier(CapturesWhileActive(audio: audio))
    }
}

private struct CapturesWhileActive: ViewModifier {
    let audio: AudioSessionController
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await audio.activate() }
            .onChangeCompat(of: scenePhase) { phase in
                switch phase {
                case .active:
                    Task { await audio.activate() }
                case .background, .inactive:
                    // Releasing the session while backgrounded is required on
                    // iOS and harmless on the Mac, where a window that isn't
                    // frontmost stays `.active` anyway.
                    audio.suspend()
                @unknown default:
                    break
                }
            }
    }
}

/// The subscriber table, split out so its locking is one small, obvious thing.
private final class ReceiverTable: @unchecked Sendable {
    private let lock = NSLock()
    private var receivers: [UUID: ([Float]) -> Void] = [:]

    func add(_ receive: @escaping ([Float]) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        receivers[id] = receive
        lock.unlock()
        return id
    }

    func remove(_ id: UUID) {
        lock.lock()
        receivers.removeValue(forKey: id)
        lock.unlock()
    }

    /// A snapshot, so delivery never holds the lock while running consumer code.
    func all() -> [([Float]) -> Void] {
        lock.lock()
        defer { lock.unlock() }
        return Array(receivers.values)
    }
}
