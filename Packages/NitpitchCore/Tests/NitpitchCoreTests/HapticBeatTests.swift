import XCTest

@testable import NitpitchCore

/// The haptic vocabulary's promises: in tune is silence, flat taps up,
/// sharp taps down, and the cadence is the string's PHYSICAL beat rate
/// against its target — the wrist renders what the ear hears.
final class HapticBeatTests: XCTestCase {
    func testInTuneIsSilence() {
        XCTAssertNil(HapticBeat.cue(cents: 0, targetHz: 440))
        XCTAssertNil(HapticBeat.cue(cents: TuningDisplay.inTuneCents, targetHz: 440))
        XCTAssertNil(HapticBeat.cue(cents: -TuningDisplay.inTuneCents, targetHz: 440))
    }

    func testTheBandEdgeIsWhereTheTapsStart() {
        let flat = HapticBeat.cue(cents: -(TuningDisplay.inTuneCents + 0.1), targetHz: 440)
        let sharp = HapticBeat.cue(cents: TuningDisplay.inTuneCents + 0.1, targetHz: 440)
        XCTAssertEqual(flat?.pattern, .up, "flat says come UP")
        XCTAssertEqual(sharp?.pattern, .down, "sharp says come DOWN")
    }

    /// The design's own vector: A4 ten cents flat beats ~2.5 times a second.
    func testTheCadenceIsThePhysicalBeatRate() {
        let cue = HapticBeat.cue(cents: -10, targetHz: 440)
        XCTAssertEqual(cue?.ratePerSecond ?? 0, 440 * (1 - pow(2, -10.0 / 1200)), accuracy: 1e-9)
        XCTAssertEqual(cue?.ratePerSecond ?? 0, 2.53, accuracy: 0.01)
    }

    /// Past ~8/s the skin feels roughness, not pulses: a whole tone off
    /// (54 Hz of beat at A4) still taps at the cap.
    func testTheCadenceCapsWhereTheSkinStopsCounting() {
        let cue = HapticBeat.cue(cents: 200, targetHz: 440)
        XCTAssertEqual(cue?.ratePerSecond, HapticBeat.maxRatePerSecond)
    }

    /// Low strings beat slowly — the rate scales with the target, exactly
    /// as the physics does, not with cents alone.
    func testTheSameCentsBeatSlowerOnALowerString() {
        let violin = HapticBeat.cue(cents: -20, targetHz: 440)!
        let bass = HapticBeat.cue(cents: -20, targetHz: 41.2)!
        XCTAssertEqual(violin.ratePerSecond / bass.ratePerSecond, 440 / 41.2, accuracy: 0.001)
    }

    func testNonsenseIsSilence() {
        XCTAssertNil(HapticBeat.cue(cents: .nan, targetHz: 440))
        XCTAssertNil(HapticBeat.cue(cents: 20, targetHz: 0))
    }

    /// A sounding fifth clicks at the pair's true beat rate — the same
    /// |3·f_L − 2·f_U| the interval chip displays.
    func testAPairClicksAtItsTrueBeatRate() {
        let low = 293.66
        let high = 440.0
        let pair = IntervalBeat.resolve(frequencies: [low, high], midis: [62, 69])!
        let cue = HapticBeat.cue(pair: pair)
        XCTAssertEqual(cue?.pattern, .beat)
        XCTAssertEqual(cue?.ratePerSecond ?? 0, abs(3 * low - 2 * high), accuracy: 1e-9)
    }

    func testAPairsCadenceCapsToo() {
        let low = 293.66
        let pair = IntervalBeat.resolve(frequencies: [low, 436.0], midis: [62, 69])!
        XCTAssertEqual(HapticBeat.cue(pair: pair)?.ratePerSecond, HapticBeat.maxRatePerSecond)
    }

    /// A pure fifth is beatless — the clicks stop exactly as the audible
    /// beats do.
    func testABeatlessPairIsSilence() {
        let low = 293.66
        let pair = IntervalBeat.resolve(frequencies: [low, low * 1.5], midis: [62, 69])!
        XCTAssertNil(HapticBeat.cue(pair: pair))
    }
}
