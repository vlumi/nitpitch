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
/// WHO a tone belongs to, typed — so "which string is playing" never
/// round-trips through string parsing.
public enum ToneTag: Equatable, Sendable {
    /// A screen's one nameless speaker (the string view's own target).
    case single
    /// The reference A.
    case reference
    /// One string's target, by index.
    case string(Int)
}

@MainActor
public final class ToneGenerator: ObservableObject {
    /// What's sounding, in hertz — nil while silent. The button's state.
    @Published public private(set) var playingHz: Double?
    /// WHO is sounding, for screens with several speakers, so each button
    /// knows whether the tone is its own.
    @Published public private(set) var playingTag: ToneTag?

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
        // `.began` only: the system has silenced the engine but may not
        // have flipped `isRunning` yet by the time this hops to main, so
        // stop it ourselves and clear the claim. `.ended` fires for the
        // same interruption later and must not clear a tone the user
        // legitimately restarted in between.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil,
                queue: .main
            ) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
                else { return }
                Task { @MainActor in self?.stopNow() }
            })
        #endif
    }

    public func start(hz: Double, tag: ToneTag = .single) {
        // Already sounding: glide to the new pitch and hand over the tag —
        // tapping another string's speaker mid-tone slides, it never
        // restarts.
        if playingHz != nil, engine.isRunning {
            box.update { $0.targetFrequency = hz }
            playingHz = hz
            playingTag = tag
            return
        }
        buildSourceIfNeeded()
        // No output device (a Mac mid-unplug): nothing to sound through,
        // and a lit button over silence would be a lie.
        guard source != nil else { return }
        box.update { synth in
            let sampleRate = synth.sampleRate
            synth = ToneSynth(sampleRate: sampleRate, frequency: hz)
            synth.targetAmplitude = ToneSynth.playingAmplitude
        }
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        playingHz = hz
        playingTag = tag
    }

    /// Follow a retarget mid-note. The synth GLIDES there — an instant
    /// frequency jump is slope-discontinuous, and its click was a field
    /// report ("pretty painful if the volume is up").
    public func retune(hz: Double) {
        guard playingHz != nil else { return }
        box.update { $0.targetFrequency = hz }
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
        playingTag = nil
    }

    /// Cut the tone NOW, no ramp — for backgrounding and interruptions,
    /// where the system is silencing the engine anyway and a 30 ms ramp
    /// would race it. Safe when silent.
    public func stopNow() {
        guard playingHz != nil else { return }
        engine.stop()
        playingHz = nil
        playingTag = nil
        discardSource()
    }

    private func engineDied() {
        guard playingHz != nil, !engine.isRunning else { return }
        playingHz = nil
        playingTag = nil
        discardSource()
    }

    /// A configuration change (headphones, a USB interface, AirPods) tears
    /// the engine's connections down and may change the output rate; the
    /// node we built is attached but no longer wired, and its format is
    /// stale. Drop it so the next start rebuilds against the current route
    /// — otherwise the engine starts fine with no live chain and the button
    /// lights over silence.
    private func discardSource() {
        guard let source else { return }
        engine.detach(source)
        self.source = nil
    }

    private func buildSourceIfNeeded() {
        guard source == nil else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        // Zero means no output device — `AVAudioFormat` would be nil and
        // the synth's arithmetic non-finite. Leave the source unbuilt;
        // `start` reads that as "nothing to sound through".
        guard sampleRate > 0,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
                interleaved: false)
        else { return }
        box.update { synth in
            synth = ToneSynth(sampleRate: sampleRate, frequency: synth.frequency)
        }
        let box = self.box
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
