import AVFoundation
import Foundation
import NitpitchCore
import NitpitchData
import WatchKit

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
    /// Windows were discarded to stay current (analysis fell behind) —
    /// fired before the next window, same queue; the consumer resets its
    /// phase pairs there. Same contract as the phone's `AudioCapturing`.
    var onGap: (() -> Void)?
    let sampleRate: Double = 44100

    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(
        label: "fi.misaki.nitpitch.watch-analysis", qos: .userInitiated)
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    /// The phone's assembler, shared through Core: hop-consecutive windows
    /// and the backlog bound (see `HopAssembler`).
    private var assembler = HopAssembler()
    private let bufferLock = NSLock()
    var droppedWindows: Int {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return assembler.droppedWindows
    }
    private var isRunning = false
    /// Whether capture is WANTED — set by `activate`, cleared by `stop`.
    /// `activate` awaits the permission prompt, and the screen that asked
    /// can be gone by the time the answer lands (first launch: open a
    /// tuner, the prompt appears, crown back before answering, tap Allow).
    /// Without this the continuation started the engine on a screen that
    /// would never stop it — the mic indicator lit over the root list, for
    /// good. It also names what the interruption/reactivation observers
    /// restore: capture the user still wants, not capture they left.
    private var wantsCapture = false
    private var observers: [NSObjectProtocol] = []
    /// Whether watchOS granted `.measurement` (input processing off — what
    /// detection wants) or fell back to `.default`; reported on screen
    /// rather than assumed.
    private var measurementGranted = true

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

        // The wrist's three ways of losing the engine without being told:
        // an interruption (a call, Siri, a workout app), the session torn
        // down while the wrist was down or the app inactive, and a route
        // change. None posts through `start()`'s `isRunning` guard, so the
        // tuner sat deaf on "Play a note" until the user navigated out and
        // back. Each now rebuilds capture if it is still wanted.
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
            ) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                if type == .began { self?.engineLost() } else { self?.restartIfWanted() }
            })
        observers.append(
            center.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                self?.engineLost()
                self?.restartIfWanted()
            })
        observers.append(
            center.addObserver(
                forName: WKApplication.didBecomeActiveNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.restartIfWanted()
            })
    }

    /// The engine stopped under us: forget that it was running, remove the
    /// tap so a restart can install its own, and let the session go.
    private func engineLost() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        bufferLock.lock()
        assembler.reset()
        bufferLock.unlock()
    }

    /// Capture the user still wants, brought back after the system took it.
    /// A running engine is left alone; a dead one is rebuilt.
    private func restartIfWanted() {
        guard wantsCapture, !isDemo else { return }
        if isRunning, engine.isRunning { return }
        engineLost()
        _ = start()
    }

    /// Ask, start, and report — one call, because the watch screen has no
    /// room for a permission flow of its own.
    func activate() async -> Status {
        wantsCapture = true
        if isDemo {
            startDemo()
            return .running(measurement: true)
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            return .permissionDenied
        }
        // The screen that asked may have stopped us during the prompt.
        guard wantsCapture else { return .idle }
        return start()
    }

    private func start() -> Status {
        guard !isRunning else { return .running(measurement: measurementGranted) }
        let session = AVAudioSession.sharedInstance()
        guard let measurement = configureSessionMode(session) else { return .unavailable }
        measurementGranted = measurement
        do {
            try session.setActive(true)
            let input = engine.inputNode
            let hardwareFormat = input.outputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0 else { return .unavailable }
            converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)
            let tap: AVAudioNodeTapBlock = { [weak self] buffer, _ in self?.accept(buffer) }
            input.installTap(onBus: 0, bufferSize: 2048, format: hardwareFormat, block: tap)
            engine.prepare()
            do {
                try engine.start()
            } catch {
                // Leave nothing behind: a second `installTap` on a bus that
                // still has one is an uncatchable AVFAudio assertion, and
                // "No microphone" → back → tap the instrument again is the
                // natural retry. The session goes too, or it stays active
                // in `.record` with nothing recording.
                input.removeTap(onBus: 0)
                try? session.setActive(false)
                return .unavailable
            }
            isRunning = true
            return .running(measurement: measurementGranted)
        } catch {
            return .unavailable
        }
    }

    /// Try `.measurement` first — it turns the input processing off (AGC,
    /// EQ), which is what the detector wants; whether watchOS honours it on
    /// the wrist was one of the unknowns the scaffold shipped to answer.
    /// Returns whether it was granted, or nil when no mode works at all.
    private func configureSessionMode(_ session: AVAudioSession) -> Bool? {
        if (try? session.setCategory(.record, mode: .measurement)) != nil { return true }
        if (try? session.setCategory(.record, mode: .default)) != nil { return false }
        return nil
    }

    func stop() {
        wantsCapture = false
        demoTimer?.cancel()
        demoTimer = nil
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        bufferLock.lock()
        assembler.reset()
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

    // MARK: - The microphone path (AudioInput's, through the shared assembler)

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
        let batch = assembler.append(samples)
        bufferLock.unlock()

        guard !batch.windows.isEmpty else { return }
        analysisQueue.async { [weak self] in
            guard let self else { return }
            if batch.gapBefore { self.onGap?() }
            for window in batch.windows { self.onWindow?(window) }
            self.bufferLock.lock()
            self.assembler.finished(batch.windows.count)
            self.bufferLock.unlock()
        }
    }
}
