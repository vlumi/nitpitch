import NitpitchCore
import XCTest

@testable import NitpitchKit

/// The debug screen is only worth having if the knobs reach the detectors and
/// nothing reaches them without it. Both halves are tested here through
/// `StringTuners` — the coordinator the grid actually runs — plus the
/// end-to-end regression for the bug that started all of this: play one note,
/// only that note's dial may light.
@MainActor
final class DetectionSettingsTests: XCTestCase {
    /// Feed a window in as the tap would, then let the coordinator's hop back
    /// to the main actor land. The DSP runs off-main and posts results with
    /// `Task { @MainActor }`, so a synchronous read after delivering sees the
    /// previous frame.
    private func deliver(_ window: [Float], through input: AudioInput) async {
        input.onWindow?(window)
        for _ in 0..<10 { await Task.yield() }
    }

    /// A tone at `hz`, harmonically rich the way a bowed string is.
    private func tone(_ hz: Double, sampleRate: Double, count: Int = Detection.windowSize)
        -> [Float]
    {
        (0..<count).map { i in
            let t = Double(i) / sampleRate
            var sample = 0.0
            for (index, amplitude) in [0.3, 1.0, 0.8, 0.5, 0.3].enumerated() {
                sample += amplitude * sin(2 * .pi * hz * Double(index + 1) * t)
            }
            return Float(sample)
        }
    }

    private func violinTuners(_ input: AudioInput) -> (StringTuners, AudioSessionController) {
        let controller = AudioSessionController(input: input)
        let strings = StringTuners(
            instrument: .violin, audio: controller, reference: .standard)
        return (strings, controller)
    }

    func testStartsAtTheShippedDefaults() {
        let detection = DetectionSettings()
        XCTAssertEqual(detection.tuning, .default)
        XCTAssertFalse(detection.isModified)
        XCTAssertEqual(detection.tuning.engine, .mpm)
    }

    /// The badge on the grid's menu depends on this, and it's the only signal
    /// that a surprising reading isn't how the app really behaves. The engine
    /// counts: spectral is experimental, and forgetting it's on would make
    /// every observation suspect.
    func testReportsWhenModifiedAndAfterReset() {
        let detection = DetectionSettings()
        detection.tuning.engine = .spectral
        XCTAssertTrue(detection.isModified)
        detection.reset()
        XCTAssertFalse(detection.isModified)
        XCTAssertEqual(detection.tuning, .default)
    }

    /// Nothing persists it, so a session of experimenting can't leave the app
    /// quietly detuned on the next launch — the worst thing a debug screen
    /// could hand a user.
    func testTuningIsNotPersisted() {
        let detection = DetectionSettings()
        detection.tuning.clarityThreshold = 0.55
        XCTAssertEqual(DetectionSettings().tuning, .default, "a fresh session must start clean")
    }

    // MARK: - The reported bug, end to end

    /// "I feel like the 'other' meters are unnecessarily sensitive. For each
    /// found tone, shouldn't only one tuner light up with its value?" — the
    /// grid's whole pipeline, microphone tap to view model: play A, and G
    /// (whose detector genuinely finds A's subharmonic at perfect clarity)
    /// must stay waiting.
    func testPlayingAMovesOnlyTheADial() async {
        let input = AudioInput()
        let (strings, controller) = violinTuners(input)
        strings.attachAll()
        defer { strings.detachAll() }

        let window = tone(440, sampleRate: controller.sampleRate)
        for _ in 0..<3 { await deliver(window, through: input) }

        for (index, tuner) in strings.tuners.enumerated() {
            if index == 2 {
                guard case .reading(let cents, _) = tuner.state else {
                    return XCTFail("the A dial should be reading")
                }
                XCTAssertEqual(cents, 0, accuracy: 2)
            } else {
                XCTAssertEqual(
                    tuner.state, .waiting,
                    "dial \(index) lit while only A was sounding")
            }
        }
    }

    // MARK: - Reaching the detectors

    /// Retuning live dials has to change what they report, or the sliders are
    /// decoration.
    func testRetuningChangesWhatLiveDialsReport() async {
        let input = AudioInput()
        let (strings, controller) = violinTuners(input)
        strings.attachAll()
        defer { strings.detachAll() }
        strings.setReportingRaw(true)

        // Quiet enough to fall under a raised silence gate but not the default.
        let quiet = tone(440, sampleRate: controller.sampleRate).map { $0 * 0.002 }
        await deliver(quiet, through: input)
        XCTAssertNotNil(
            strings.tuners[2].lastResult.frequency, "should be found at the default gate")

        strings.retune(DetectionTuning(silenceRMS: 0.05))
        await deliver(quiet, through: input)
        XCTAssertNil(
            strings.tuners[2].lastResult.frequency, "a raised gate should reject it")
    }

    /// Flipping the engine mid-session must keep the dials working — it's a
    /// segmented control on the debug screen.
    func testEngineSwitchKeepsDialsWorking() async {
        let input = AudioInput()
        let (strings, controller) = violinTuners(input)
        strings.attachAll()
        defer { strings.detachAll() }

        strings.retune(DetectionTuning(engine: .spectral))
        // Consecutive windows a hop apart, as the tap delivers them — the
        // spectral engine measures the phase advance *between* windows, so
        // repeating one identical window would measure nothing.
        let signal = tone(
            440, sampleRate: controller.sampleRate,
            count: Detection.windowSize + Detection.hopSize * 3)
        for hop in 0..<3 {
            let start = hop * Detection.hopSize
            await deliver(
                Array(signal[start..<(start + Detection.windowSize)]), through: input)
        }

        guard case .reading(let cents, _) = strings.tuners[2].state else {
            return XCTFail("the A dial should be reading under the spectral engine")
        }
        XCTAssertEqual(cents, 0, accuracy: 2)
        XCTAssertEqual(strings.tuners[0].state, .waiting, "G must stay dark under spectral too")
    }

    /// Raw results cost a publish per string per frame, ~21×/second, so they're
    /// off unless the diagnostics screen is actually up.
    func testRawResultsArePublishedOnlyWhileReporting() async {
        let input = AudioInput()
        let (strings, controller) = violinTuners(input)
        strings.attachAll()
        defer { strings.detachAll() }

        let window = tone(440, sampleRate: controller.sampleRate)
        await deliver(window, through: input)
        XCTAssertEqual(
            strings.tuners[2].lastResult, .silent, "should not publish while not reporting")

        strings.setReportingRaw(true)
        await deliver(window, through: input)
        XCTAssertNotNil(strings.tuners[2].lastResult.frequency)
    }

    /// The band knob only means anything if a narrower band actually refuses
    /// pitches the wider one accepted.
    func testNarrowingTheBandExcludesDistantPitches() {
        let wide = Instrument.violin.stringBands(maxSemitones: 4)
        let narrow = Instrument.violin.stringBands(maxSemitones: 1)
        // Two semitones above the A string: inside the default band, outside ±1.
        let hz = 440 * pow(2, 2.0 / 12)
        XCTAssertTrue(wide[2].contains(hz))
        XCTAssertFalse(narrow[2].contains(hz))
    }

    /// A grid built at the default must be identical to one built with no
    /// tuning at all — the debug path can't change the shipped app.
    func testDefaultTuningLeavesTheGridUnchanged() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        let plain = StringTuners(
            instrument: .violin, audio: controller, reference: .standard)
        let tuned = StringTuners(
            instrument: .violin, audio: controller, reference: .standard, tuning: .default)
        XCTAssertEqual(plain.tuners.map(\.band), tuned.tuners.map(\.band))
    }
}
