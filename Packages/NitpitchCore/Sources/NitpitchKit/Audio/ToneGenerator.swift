import AVFoundation
import Foundation
import NitpitchCore

/// The reference tone: a sine at a string's tempered target, played to tune
/// against by ear — and the fallback in a room too noisy to detect in.
///
/// Owns its own small output engine; the capture engine stays
/// `AudioInput`'s. Who yields to whom is `AudioSessionController`'s
/// business (`beginTonePlayback`): detection suspends while the tone
/// sounds — the alternative was the detector locking onto the app's own
/// voice — and on iOS the session drops to `.ambient` for the duration,
/// which both MIXES with whatever the user left playing and RESPECTS the
/// silent switch. A reference tone is a courtesy, not an alarm.
@MainActor
public final class ToneGenerator: ObservableObject {
    /// What's sounding, in hertz — nil while silent. The button's state.
    @Published public private(set) var playingHz: Double?

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    /// The synth, shared with the render thread — same locking story as
    /// `AudioInput`'s ring buffer.
    private let box = SynthBox()
    private var observers: [NSObjectProtocol] = []

    public init() {
        // The system stops ambient engines on backgrounding and yanks the
        // route on interruptions; either way the tone is over and the
        // button must not claim otherwise.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.engineDied() }
            })
        #if os(iOS)
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.engineDied() }
            })
        #endif
    }

    public func start(hz: Double) {
        buildSourceIfNeeded()
        box.update { synth in
            synth.frequency = hz
            synth.targetAmplitude = ToneSynth.playingAmplitude
        }
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        playingHz = hz
    }

    /// Follow a retarget mid-note — phase-continuous, so the swipe to the
    /// next string glides instead of clicking.
    public func retune(hz: Double) {
        guard playingHz != nil else { return }
        box.update { $0.frequency = hz }
        playingHz = hz
    }

    /// Ramp out, then stop the engine — the ramp is what makes the stop
    /// clickless, and it's ~30 ms long.
    public func stop() async {
        guard playingHz != nil else { return }
        box.update { $0.targetAmplitude = 0 }
        try? await Task.sleep(nanoseconds: 60_000_000)
        engine.stop()
        playingHz = nil
    }

    private func engineDied() {
        guard playingHz != nil, !engine.isRunning else { return }
        playingHz = nil
    }

    private func buildSourceIfNeeded() {
        guard source == nil else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        box.update { synth in
            synth = ToneSynth(sampleRate: sampleRate, frequency: synth.frequency)
        }
        let box = self.box
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
            interleaved: false)!
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            box.render(frames: Int(frameCount), into: buffers)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
    }
}

/// The synth behind a lock, for the render thread — the same pattern as
/// `AudioInput.bufferLock`.
private final class SynthBox: @unchecked Sendable {
    private let lock = NSLock()
    private var synth = ToneSynth(sampleRate: 44100, frequency: 440)

    func update(_ change: (inout ToneSynth) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&synth)
    }

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        lock.lock()
        defer { lock.unlock() }
        for frame in 0..<frames {
            let sample = synth.nextSample()
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
    }
}
