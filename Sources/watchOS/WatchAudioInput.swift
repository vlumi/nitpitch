import AVFoundation
import Foundation
import NitpitchCore
import NitpitchData

/// The watch's one microphone — `AudioInput` slimmed to what watchOS has:
/// no `AVCaptureDevice` discovery, no CoreAudio listeners, one built-in mic
/// that can't be unplugged. Same contract downstream: analysis windows of
/// `Detection.windowSize`, hopped by `Detection.hopSize`, delivered off the
/// main queue.
///
/// Under `-demo` the engine is replaced by the same synthesized instrument
/// the phone demo plays (`DemoSignal`, from NitpitchCore) — the watch
/// simulator's microphone is as silent as the iPhone's.
final class WatchAudioInput: @unchecked Sendable {
    enum Status: Equatable {
        case idle
        case permissionDenied
        case unavailable
        /// Running, and honestly reporting which session mode watchOS
        /// granted — `.measurement` (input processing off, what detection
        /// wants) or the `.default` fallback. A roadmap unknown, surfaced
        /// on screen rather than assumed.
        case running(measurement: Bool)
    }

    var onWindow: (([Float]) -> Void)?
    let sampleRate: Double = 44100

    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(
        label: "fi.misaki.nitpitch.watch-analysis", qos: .userInitiated)
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var pending: [Float] = []
    private let bufferLock = NSLock()
    private var isRunning = false

    private let isDemo = LaunchStores.isDemo
    private var demoTimer: DispatchSourceTimer?
    private var demoSignal: DemoSignal
    private var demoWindow: [Float] = []

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
            interleaved: false)!
        let pose = LaunchStores.demoPose.flatMap(DemoScore.parse)
        demoSignal = DemoSignal(score: pose ?? .drift, sampleRate: sampleRate)
    }

    /// Ask, start, and report — one call, because the watch screen has no
    /// room for a permission flow of its own.
    func activate() async -> Status {
        if isDemo {
            startDemo()
            return .running(measurement: true)
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            return .permissionDenied
        }
        return start()
    }

    private func start() -> Status {
        guard !isRunning else { return .running(measurement: measurementGranted) }
        let session = AVAudioSession.sharedInstance()
        // `.measurement` turns the input processing off (AGC, EQ), which is
        // what the detector wants — whether watchOS honours it on the wrist
        // is one of the unknowns this scaffold ships to answer.
        measurementGranted = true
        do {
            try session.setCategory(.record, mode: .measurement)
        } catch {
            measurementGranted = false
            do {
                try session.setCategory(.record, mode: .default)
            } catch {
                return .unavailable
            }
        }
        do {
            try session.setActive(true)
            let input = engine.inputNode
            let hardwareFormat = input.outputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0 else { return .unavailable }
            converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)
            let tap: AVAudioNodeTapBlock = { [weak self] buffer, _ in self?.accept(buffer) }
            input.installTap(onBus: 0, bufferSize: 2048, format: hardwareFormat, block: tap)
            engine.prepare()
            try engine.start()
            isRunning = true
            return .running(measurement: measurementGranted)
        } catch {
            return .unavailable
        }
    }

    private var measurementGranted = true

    func stop() {
        demoTimer?.cancel()
        demoTimer = nil
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        bufferLock.lock()
        pending.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - The demo instrument

    private func startDemo() {
        guard demoTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: analysisQueue)
        timer.schedule(deadline: .now(), repeating: Double(Detection.hopSize) / sampleRate)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.demoWindow.count < Detection.windowSize {
                self.demoWindow = self.demoSignal.render(count: Detection.windowSize)
            } else {
                self.demoWindow.removeFirst(Detection.hopSize)
                self.demoWindow += self.demoSignal.render(count: Detection.hopSize)
            }
            self.onWindow?(self.demoWindow)
        }
        timer.resume()
        demoTimer = timer
    }

    // MARK: - The microphone path (AudioInput's ring, unchanged in spirit)

    private func accept(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard
            let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else { return }

        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
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
        let samples = Array(
            UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))

        bufferLock.lock()
        pending.append(contentsOf: samples)
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
