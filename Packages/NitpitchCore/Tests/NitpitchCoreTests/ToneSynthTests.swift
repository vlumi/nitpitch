import XCTest

@testable import NitpitchCore

/// The reference tone as arithmetic: right pitch, clickless edges,
/// phase-continuous retuning.
final class ToneSynthTests: XCTestCase {
    private let sampleRate = 44100.0

    private func samples(_ synth: inout ToneSynth, seconds: Double) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { _ in synth.nextSample() }
    }

    func testAnAFourFortyIsAnAFourForty() {
        var synth = ToneSynth(sampleRate: sampleRate, frequency: 440)
        synth.targetAmplitude = ToneSynth.playingAmplitude
        let rendered = samples(&synth, seconds: 1)
        // Count upward zero crossings after the attack has settled — one
        // per cycle.
        let settled = Array(rendered.dropFirst(4410))
        var crossings = 0
        for index in 1..<settled.count
        where settled[index - 1] <= 0 && settled[index] > 0 {
            crossings += 1
        }
        let seconds = Double(settled.count) / sampleRate
        XCTAssertEqual(Double(crossings) / seconds, 440, accuracy: 1.5)
    }

    /// The edges must not click: with a ramped envelope, no two adjacent
    /// samples may jump more than the waveform's own slope allows.
    func testStartAndStopAreClickless() {
        var synth = ToneSynth(sampleRate: sampleRate, frequency: 440)
        synth.targetAmplitude = ToneSynth.playingAmplitude
        var rendered = samples(&synth, seconds: 0.1)
        synth.targetAmplitude = 0
        rendered += samples(&synth, seconds: 0.1)
        XCTAssertEqual(synth.amplitude, 0, "the release must land")
        XCTAssertFalse(synth.isAudible)
        let maxJump = zip(rendered, rendered.dropFirst()).map { abs($1 - $0) }.max() ?? 1
        // A 440 Hz sine at 0.3 moves at most 2π·440/44100·0.3 ≈ 0.019 per
        // sample; the envelope adds its own slope on top. 0.025 is the
        // budget; a hard start or stop would jump by 0.3.
        XCTAssertLessThan(maxJump, 0.025)
    }

    func testTheAttackLandsPromptly() {
        var synth = ToneSynth(sampleRate: sampleRate, frequency: 440)
        synth.targetAmplitude = ToneSynth.playingAmplitude
        _ = samples(&synth, seconds: 0.05)
        XCTAssertEqual(
            synth.amplitude, ToneSynth.playingAmplitude, accuracy: 0.001,
            "50 ms is more than the ramp needs")
    }

    /// Retuning mid-note — the swipe to the next string — must GLIDE: an
    /// instantaneous frequency jump is phase-continuous but not
    /// slope-continuous, and that kink was audible as a cutting noise in
    /// the field. The pitch must move through the middle and land.
    func testRetuningGlides() {
        var synth = ToneSynth(sampleRate: sampleRate, frequency: 440)
        synth.targetAmplitude = ToneSynth.playingAmplitude
        var rendered = samples(&synth, seconds: 0.1)
        synth.targetFrequency = 660
        rendered += samples(&synth, seconds: 0.02)
        XCTAssertTrue(
            (450...650).contains(synth.frequency),
            "20 ms in, the pitch is mid-glide, not teleported")
        rendered += samples(&synth, seconds: 0.2)
        XCTAssertEqual(synth.frequency, 660, accuracy: 0.05, "the glide lands")
        let maxJump = zip(rendered, rendered.dropFirst()).map { abs($1 - $0) }.max() ?? 1
        // The 660 Hz slope bound: 2π·660/44100·0.3 ≈ 0.028.
        XCTAssertLessThan(maxJump, 0.035)
    }

    /// Gliding down works symmetrically — E back to A.
    func testGlidingDownLands() {
        var synth = ToneSynth(sampleRate: sampleRate, frequency: 660)
        synth.targetAmplitude = ToneSynth.playingAmplitude
        _ = samples(&synth, seconds: 0.05)
        synth.targetFrequency = 440
        _ = samples(&synth, seconds: 0.25)
        XCTAssertEqual(synth.frequency, 440, accuracy: 0.05)
    }

    /// The second field report: a ±1 Hz reference step is ~4¢, which a
    /// rate-limited glide crossed in 0.4 ms — the same kink as no glide at
    /// all. The exponential must SPREAD a small step, not sprint it.
    func testASmallStepIsSpreadNotSprinted() {
        var synth = ToneSynth(sampleRate: sampleRate, frequency: 442)
        synth.targetAmplitude = ToneSynth.playingAmplitude
        _ = samples(&synth, seconds: 0.05)
        synth.targetFrequency = 443
        _ = samples(&synth, seconds: 0.005)
        XCTAssertLessThan(
            synth.frequency, 442.5,
            "5 ms in, a 1 Hz step must still be underway")
        _ = samples(&synth, seconds: 0.2)
        XCTAssertEqual(synth.frequency, 443, accuracy: 0.05, "and it lands")
    }
}
