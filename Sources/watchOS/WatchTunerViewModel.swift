import Foundation
import NitpitchCore

/// The wrist's chromatic reading — `NitpitchViewModel`'s consume path,
/// carried over whole: absolute-cents smoothing so the line is continuous
/// across note boundaries, re-resolution so the name agrees with the needle,
/// and the quiet-frames dropout so the screen clears instead of freezing.
@MainActor
final class WatchTunerViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case reading(note: Note, cents: Double)
        case denied
        case unavailable
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var level: Double = 0
    /// Whether watchOS granted `.measurement` mode — a roadmap unknown,
    /// shown in the footer so a wrist test answers it at a glance.
    @Published private(set) var measurementMode = true

    private let audio = WatchAudioInput()
    private let detector: PitchDetector
    private var smoother = ReadingSmoother()
    private let reference = ReferencePitch.standard
    private var quietFrames = 0
    private static let quietFramesBeforeIdle = 8

    init() {
        detector = PitchDetector(sampleRate: audio.sampleRate)
        audio.onWindow = { [weak self, detector] window in
            // Analysis queue; only the result hops to main.
            let result = detector.analyze(window)
            Task { @MainActor [weak self] in self?.consume(result) }
        }
    }

    func begin() async {
        state = .listening
        switch await audio.activate() {
        case .permissionDenied:
            state = .denied
        case .unavailable:
            state = .unavailable
        case .running(let measurement):
            measurementMode = measurement
        case .idle:
            break
        }
    }

    func end() {
        audio.stop()
        smoother.reset()
        state = .idle
        level = 0
    }

    private func consume(_ result: DetectionResult) {
        level = result.displayLevel
        guard let hz = result.frequency else {
            quietFrames += 1
            if quietFrames >= Self.quietFramesBeforeIdle, case .reading = state {
                smoother.reset()
                state = .listening
            }
            return
        }
        quietFrames = 0

        let raw = PitchReading(frequency: hz, reference: reference)
        let absolute = Double(raw.note.midi) * 100 + raw.cents
        let smoothedAbsolute = smoother.update(cents: absolute)
        let smoothedMidi = Int((smoothedAbsolute / 100).rounded())
        let displayCents = smoothedAbsolute - Double(smoothedMidi) * 100
        state = .reading(note: Note(midi: smoothedMidi), cents: displayCents)
    }
}
