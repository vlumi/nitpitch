import AVFoundation
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
        self.input.onDeviceChange = { [weak self] in
            Task { @MainActor in self?.deviceChanged() }
        }
    }

    private var pendingReactivation: Task<Void, Never>?
    private var isReactivating = false

    /// Device events arrive in storms: a replug fires the default-input
    /// listener and the engine's notification several times while the device
    /// initializes, and answering each with its own engine stop/start
    /// thrashed the audio stack and flapped the UI mid-click. Coalesce —
    /// every event restarts a short fuse, and the rebuild happens once, when
    /// the hardware has settled. Events raised by our own restart are
    /// dropped outright.
    private func deviceChanged() {
        guard !isReactivating else { return }
        pendingReactivation?.cancel()
        pendingReactivation = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.reactivate()
        }
    }

    /// Rebuild capture around whatever the default input is now.
    ///
    /// An unplug stops the engine's windows without any error — they just
    /// stop coming — and a replug restarts nothing by itself, so both funnel
    /// here: tear down, activate again, and let the outcome set the status
    /// honestly (`.running` on the new device, `.unavailable` without one).
    /// `.idle` is left alone — capture follows the scene, and the next
    /// foreground pass activates anyway — as is `.permissionDenied`, where
    /// restarting would answer a question nobody asked.
    private func reactivate() async {
        guard status == .running || status == .unavailable else { return }
        isReactivating = true
        defer { isReactivating = false }
        input.stop()
        await activate()
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

    /// The one reference tone, app-wide. A single engine by design: when
    /// every screen owned its own generator, starting a tone on the grid
    /// and another in a string view sounded BOTH — exclusivity has to be
    /// structural, not cooperative.
    public let tone = ToneGenerator()

    /// Sound `hz` under `tag`, take over from whatever else sounds (a
    /// glide), or stop if `tag` is already the one sounding. Screens wrap
    /// this to stand their own dials down.
    public func toggleTone(hz: Double, tag: String) async {
        if tone.playingTag == tag {
            await silenceTone()
            return
        }
        if tone.playingTag == nil {
            beginTonePlayback()
        }
        tone.start(hz: hz, tag: tag)
    }

    /// Stop whatever sounds and hand the session back to capture — safe
    /// when silent. Tuning screens call it on arrival: navigation begins
    /// in silence, whoever left a tone ringing behind.
    public func silenceTone() async {
        guard tone.playingTag != nil else { return }
        await tone.stop()
        await endTonePlayback()
    }

    /// Capture yields to the reference tone. Detection SUSPENDS while a
    /// tone sounds — the design question the roadmap left open, answered:
    /// the alternative was the detector locking onto the app's own voice.
    /// On iOS the session drops to `.ambient` for the duration: it mixes
    /// with whatever the user left playing, and it respects the silent
    /// switch — a reference tone is a courtesy, not an alarm, and an
    /// accidental ring switch should silence it.
    public func beginTonePlayback() {
        input.stop()
        status = .idle
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    /// The tone is over: capture takes the session back.
    public func endTonePlayback() async {
        await activate()
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
