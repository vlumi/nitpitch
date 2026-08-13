import Foundation
import NitpitchCore

/// The `-demo` capture source: `AudioCapturing` clothes around `DemoSignal`,
/// delivering windows exactly the way `AudioInput` does — same size, same
/// hop, same cadence, same off-main queue — so nothing downstream can tell
/// the difference. No permission to ask, no device to lose.
public final class DemoSignalInput: AudioCapturing, @unchecked Sendable {
    public var onWindow: (([Float]) -> Void)?
    public var onDeviceChange: (() -> Void)?
    public let sampleRate: Double = 44100

    private let queue = DispatchQueue(
        label: "fi.misaki.nitpitch.demo-signal", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var signal: DemoSignal
    private var window: [Float] = []

    public init(score: DemoScore) {
        self.signal = DemoSignal(score: score, sampleRate: sampleRate)
    }

    public func requestPermission() async -> Bool { true }

    public func start() throws {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let hopSeconds = Double(Detection.hopSize) / sampleRate
        timer.schedule(deadline: .now(), repeating: hopSeconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.window.count < Detection.windowSize {
                self.window = self.signal.render(count: Detection.windowSize)
            } else {
                self.window.removeFirst(Detection.hopSize)
                self.window += self.signal.render(count: Detection.hopSize)
            }
            self.onWindow?(self.window)
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }
}
