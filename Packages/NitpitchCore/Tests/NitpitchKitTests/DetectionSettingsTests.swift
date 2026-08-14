import NitpitchCore
import XCTest

@testable import NitpitchData
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

    /// Deliver a tone as the tap would: consecutive windows a hop apart from
    /// one continuous signal. The spectral engine measures the phase advance
    /// *between* windows, so repeating one identical window reads as garbage —
    /// a trap this helper exists to make unrepeatable.
    private func slide(
        _ hz: Double, through input: AudioInput, sampleRate: Double, hops: Int = 3
    ) async {
        let signal = tone(
            hz, sampleRate: sampleRate,
            count: Detection.windowSize + Detection.hopSize * hops)
        for hop in 0..<hops {
            let start = hop * Detection.hopSize
            await deliver(
                Array(signal[start..<(start + Detection.windowSize)]), through: input)
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
        XCTAssertEqual(detection.tuning.engine, .hybrid)
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

        await slide(440, through: input, sampleRate: controller.sampleRate)

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

    /// The signal bar's number: a sounding string publishes its level, silent
    /// neighbours stay at zero.
    func testLevelFollowsTheReading() async {
        let input = AudioInput()
        let (strings, controller) = violinTuners(input)
        strings.attachAll()
        defer { strings.detachAll() }

        await slide(440, through: input, sampleRate: controller.sampleRate)

        XCTAssertGreaterThan(strings.tuners[2].level, 0)
        for index in [0, 1, 3] {
            XCTAssertEqual(strings.tuners[index].level, 0, "silent string \(index) has level")
        }
    }

    /// The overall meter answers "is anything coming in at all" — it must
    /// move with sound even when no string registers, which is exactly the
    /// case the per-string bars can't show.
    func testInputLevelMovesEvenWhenNoStringReads() async {
        let input = AudioInput()
        let (strings, controller) = violinTuners(input)
        strings.attachAll()
        defer { strings.detachAll() }

        // A pitch between strings, far from every target: no dial reads under
        // spectral, but the meter must still show the sound.
        strings.retune(DetectionTuning(engine: .spectral))
        await slide(510, through: input, sampleRate: controller.sampleRate)

        XCTAssertGreaterThan(strings.inputLevel.value, 0)
        for (index, tuner) in strings.tuners.enumerated() {
            XCTAssertEqual(tuner.state, .waiting, "dial \(index) read a between-strings pitch")
        }
    }

    /// Switching the tuning retargets every dial — rebanding alone would
    /// leave cells measuring (and labelled) against the old notes. Caught
    /// first by a UI test; pinned here where it's cheap.
    func testConfigureRetargetsTheTuners() {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        let strings = StringTuners(
            instrument: .guitar, audio: controller, reference: .standard)
        XCTAssertEqual(strings.tuners[0].target.fullName, "E2")

        let dropD = Instrument.guitar.factoryTunings.first { $0.name == "Drop D" }!
        let retuned = Instrument(
            id: "guitar", name: "Guitar", strings: dropD.strings, family: .fretted)
        strings.configure(instrument: retuned, reference: .standard)
        XCTAssertEqual(strings.tuners[0].target.fullName, "D2")
        XCTAssertEqual(
            strings.tuners[1].target.fullName, "A2",
            "unchanged strings keep their targets")
    }

    // MARK: - The string view's coordinator

    /// The string view's defining property: bound to one string, it hears the
    /// WHOLE instrument — a pitch far outside the string's grid band still
    /// reads, measured against this string's target. This is the slipped-peg
    /// case the grid structurally can't show.
    func testSingleStringHearsTheWholeInstrument() async {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        // Aim at E5 (659 Hz) but play A4 (440 Hz) — 300¢ below E's grid band.
        let single = SingleStringTuner(
            instrument: .violin, index: 3, audio: controller, reference: .standard)
        single.attach()
        defer { single.detach() }

        await slide(440, through: input, sampleRate: controller.sampleRate)
        guard case .reading(let cents, _) = single.tuner.state else {
            return XCTFail("the string view should read a far-off pitch")
        }
        XCTAssertEqual(cents, -700, accuracy: 8, "440 Hz against E5 is ~-700¢")
    }

    /// Swiping retargets: the same sound reads against the new string.
    func testRetargetingMeasuresAgainstTheNewString() async {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        let single = SingleStringTuner(
            instrument: .violin, index: 2, audio: controller, reference: .standard)
        single.attach()
        defer { single.detach() }

        await slide(440, through: input, sampleRate: controller.sampleRate)
        guard case .reading(let atA, _) = single.tuner.state else {
            return XCTFail("A should read against A")
        }
        XCTAssertEqual(atA, 0, accuracy: 3)

        let violin = InstrumentInstance(
            id: "violin", templateID: "violin", name: "Violin",
            strings: Instrument.violin.strings, referenceHz: 440, isLocked: false,
            loadedPresetID: nil)
        single.apply(instance: violin, index: 1, tuning: .default)  // D4
        XCTAssertEqual(single.tuner.target.fullName, "D4")
        await slide(440, through: input, sampleRate: controller.sampleRate)
        guard case .reading(let atD, _) = single.tuner.state else {
            return XCTFail("A should read against D after retargeting")
        }
        XCTAssertEqual(atD, 700, accuracy: 8, "440 Hz against D4 is ~+700¢")
    }

    /// The string view's edit loop: the store changes a target, apply() aims
    /// the live tuner at it, and the same sound reads against the new note.
    func testApplyFollowsAnEditedTarget() async {
        let input = AudioInput()
        let controller = AudioSessionController(input: input)
        let defaults = UserDefaults(suiteName: "fi.misaki.nitpitch.tests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let store = InstrumentStore(defaults: defaults) { .standard }
        let violin = store.instance(id: Instrument.violin.id)!

        let single = SingleStringTuner(
            instrument: violin.instrument, index: 2, audio: controller,
            reference: violin.reference)
        single.attach()
        defer { single.detach() }
        XCTAssertEqual(single.tuner.target.fullName, "A4")

        // Nudge A4 down two semitones -> G4; the tuner follows.
        store.setString(id: violin.id, index: 2, midi: 67)
        single.apply(instance: store.instance(id: violin.id)!, index: 2, tuning: .default)
        XCTAssertEqual(single.tuner.target.fullName, "G4")

        // 440 Hz against a G4 target reads +200 cents.
        await slide(440, through: input, sampleRate: controller.sampleRate)
        guard case .reading(let cents, _) = single.tuner.state else {
            return XCTFail("should read against the edited target")
        }
        XCTAssertEqual(cents, 200, accuracy: 5)
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
        // Two frames: the first is real but unconfirmed.
        let quiet = tone(440, sampleRate: controller.sampleRate).map { $0 * 0.002 }
        await deliver(quiet, through: input)
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
        await slide(440, through: input, sampleRate: controller.sampleRate)

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

    /// The confirmation slider reaches the pipeline: at 1, the very first
    /// frame lights the dial.
    func testConfirmationOfOneReachesTheBank() async {
        let input = AudioInput()
        let (strings, controller) = violinTuners(input)
        strings.attachAll()
        defer { strings.detachAll() }
        strings.retune(DetectionTuning(confirmationFrames: 1))
        strings.setReportingRaw(true)

        await deliver(tone(440, sampleRate: controller.sampleRate), through: input)
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
