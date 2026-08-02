import NitpitchCore
import XCTest

@testable import NitpitchKit

/// The debug screen is only worth having if the knobs reach the detector and
/// nothing reaches it without them. Both halves are tested here: the sliders
/// take effect on live dials, and a shipped build behaves exactly as before.
@MainActor
final class DetectionSettingsTests: XCTestCase {
    /// Feed a window in as the tap would, then let the model's hop back to the
    /// main actor land. The DSP runs off-main and posts its result with
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

    func testStartsAtTheShippedDefaults() {
        let detection = DetectionSettings()
        XCTAssertEqual(detection.tuning, .default)
        XCTAssertFalse(detection.isModified)
    }

    /// The badge on the grid's menu depends on this, and it's the only signal
    /// that a surprising reading isn't how the app really behaves.
    func testReportsWhenModifiedAndAfterReset() {
        let detection = DetectionSettings()
        detection.tuning.clarityThreshold = 0.6
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

    // MARK: - Reaching the detectors

    /// Retuning a live dial has to change what it reports, or the sliders are
    /// decoration.
    func testRetuningChangesWhatALiveDialReports() async {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        let bands = Instrument.violin.stringBands()
        let tuner = StringTunerViewModel(
            audio: controller, target: Instrument.violin.notes[2], band: bands[2])
        tuner.attach()
        defer { tuner.detach() }

        // Quiet enough to fall under a raised silence gate but not the default.
        let quiet = tone(440, sampleRate: controller.sampleRate).map { $0 * 0.002 }
        tuner.isReportingRaw = true

        await deliver(quiet, through: input)
        XCTAssertNotNil(tuner.lastResult.frequency, "should be found at the default gate")

        tuner.retune(DetectionTuning(silenceRMS: 0.05))
        await deliver(quiet, through: input)
        XCTAssertNil(tuner.lastResult.frequency, "a raised gate should reject it")
    }

    /// Raw results cost a publish per string per frame, ~21×/second, so they're
    /// off unless the diagnostics screen is actually up.
    func testRawResultsArePublishedOnlyWhileReporting() async {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        let bands = Instrument.violin.stringBands()
        let tuner = StringTunerViewModel(
            audio: controller, target: Instrument.violin.notes[2], band: bands[2])
        tuner.attach()
        defer { tuner.detach() }

        await deliver(tone(440, sampleRate: controller.sampleRate), through: input)
        XCTAssertEqual(tuner.lastResult, .silent, "should not publish while not reporting")

        tuner.isReportingRaw = true
        await deliver(tone(440, sampleRate: controller.sampleRate), through: input)
        XCTAssertNotNil(tuner.lastResult.frequency)
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
