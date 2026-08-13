import Foundation

/// What `AudioSessionController` needs from a capture source — the one seam
/// where the microphone can be swapped for something else.
///
/// Exactly two conformers, on purpose: `AudioInput` (the real microphone) and
/// `DemoSignalInput` (a synthesized instrument, under `-demo`). The seam sits
/// HERE, below the controller, so everything downstream — session policy,
/// subscriptions, the detectors, every view model — runs identically on both.
/// That's what makes the demo honest: it isn't a synthetic display state, it's
/// the real pipeline hearing a synthetic signal.
public protocol AudioCapturing: AnyObject {
    /// Delivered off the main queue, one analysis window at a time; the
    /// consumer hops to main itself.
    var onWindow: (([Float]) -> Void)? { get set }
    /// Input hardware changed underneath the source. A source with no
    /// hardware never fires it.
    var onDeviceChange: (() -> Void)? { get set }
    /// The rate detectors should be built for.
    var sampleRate: Double { get }
    /// Ask for whatever consent this source needs. The microphone prompts;
    /// a synthesized signal has nothing to ask.
    func requestPermission() async -> Bool
    func start() throws
    func stop()
}

extension AudioInput: AudioCapturing {
    public func requestPermission() async -> Bool {
        await Self.requestPermission()
    }
}
