import AVFoundation
import Foundation
import NitpitchCore

/// Microphone (or line-in) capture, converted to the detector's expected format
/// and delivered one analysis window at a time.
///
/// Two things this deliberately does NOT do:
/// - **Analyse on the audio thread.** The tap callback copies into a ring buffer
///   and returns; the DSP runs on `analysisQueue`. Blocking the render thread
///   causes dropouts, and the tap has a hard real-time deadline.
/// - **Assume the hardware sample rate.** The input node's rate is whatever the
///   device or interface provides (48 kHz on most Macs, 44.1 or 48 on iPhones),
///   so an `AVAudioConverter` normalizes it and the detector is constructed for
///   the *converted* rate.
public final class AudioInput {
    /// Delivered on `analysisQueue`, not the main queue — the consumer hops to
    /// main itself so the UI update is one hop, not two.
    public var onWindow: (([Float]) -> Void)?

    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(
        label: "fi.misaki.nitpitch.analysis", qos: .userInitiated)
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    /// Ring of converted samples awaiting analysis. Written on the audio
    /// thread, drained on `analysisQueue` — guarded by `bufferLock`.
    private var pending: [Float] = []
    private let bufferLock = NSLock()

    private(set) public var isRunning = false

    /// The rate the detector should be built for (not necessarily the hardware's).
    public let sampleRate: Double

    public init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
        // Mono float32 — the detector wants a plain [Float], and a tuner has no
        // use for stereo (both channels carry the same instrument).
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
            interleaved: false)!
    }

    /// Ask for microphone permission. iOS and macOS diverge here: iOS routes it
    /// through `AVAudioSession`, macOS through `AVCaptureDevice`.
    public static func requestPermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    public func start() throws {
        guard !isRunning else { return }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // .measurement disables the input processing (AGC, EQ, noise
        // suppression) that voice modes apply — all of which distort the
        // harmonic content the detector depends on.
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
        #endif

        #if os(macOS)
        // Merely ACCESSING `engine.inputNode` on a Mac with no input device
        // raises an Objective-C exception while the engine wires its input
        // unit to hardware that isn't there — unreachable by Swift error
        // handling, so the zero-rate guard below never got its chance (a
        // mic-less Mac mini crashed at launch). Ask AVCaptureDevice first:
        // it can say "none" politely.
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio, position: .unspecified)
        guard !discovered.devices.isEmpty else { throw AudioInputError.noInputDevice }
        #endif

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        // A zero sample rate means no input device is available (or none is
        // permitted yet) — installing a tap on it crashes.
        guard hardwareFormat.sampleRate > 0 else { throw AudioInputError.noInputDevice }

        converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)

        // Tap buffer size is a hint, not a promise — the callback must handle
        // whatever length it gets, which is why samples go through the ring
        // rather than being analysed per-callback.
        let tap: AVAudioNodeTapBlock = { [weak self] buffer, _ in self?.accept(buffer) }
        input.installTap(onBus: 0, bufferSize: 2048, format: hardwareFormat, block: tap)

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        bufferLock.lock()
        pending.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    /// Audio-thread callback: convert, append, and get out. No analysis here.
    private func accept(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard
            let converted = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: capacity)
        else { return }

        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            // The converter asks repeatedly; hand over the buffer once, then
            // report no-more-data or it will spin.
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0,
            let channel = converted.floatChannelData?[0]
        else { return }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))

        bufferLock.lock()
        pending.append(contentsOf: samples)
        // Drain whole hops while enough has accumulated. Cap the backlog so a
        // stalled consumer can't grow this without bound.
        var windows: [[Float]] = []
        while pending.count >= Detection.windowSize {
            windows.append(Array(pending.prefix(Detection.windowSize)))
            pending.removeFirst(Detection.hopSize)
        }
        if pending.count > Detection.windowSize * 4 {
            pending.removeFirst(pending.count - Detection.windowSize)
        }
        bufferLock.unlock()

        guard !windows.isEmpty else { return }
        analysisQueue.async { [weak self] in
            guard let self else { return }
            for window in windows { self.onWindow?(window) }
        }
    }
}

public enum AudioInputError: Error, LocalizedError {
    case noInputDevice

    public var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return String(
                localized: "No audio input device is available.",
                bundle: .module,
                comment: "Shown when the engine reports no usable input")
        }
    }
}
