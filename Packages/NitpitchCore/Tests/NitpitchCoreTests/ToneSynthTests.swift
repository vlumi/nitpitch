import XCTest

@testable import NitpitchCore

/// The reference tone as arithmetic: right pitch (verified by the app's own
/// detector, since the harmonic-rich waveform defeats zero-crossing
/// counting), clickless edges (measured against the tone's own steady
/// slope), phase-continuous retuning.
final class ToneSynthTests: XCTestCase {
    private let sampleRate = 44100.0

    private func samples(_ synth: inout ToneSynth, seconds: Double) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { _ in synth.nextSample() }
    }

    private func maxJump(_ rendered: [Float]) -> Float {
        zip(rendered, rendered.dropFirst()).map { abs($1 - $0) }.max() ?? 1
    }

    /// The tone's pitch, as the tuner itself would hear it — for the
    /// fundamental AND for a bass-register note whose fundamental a phone
    /// speaker couldn't even reproduce (the harmonics carry it).
    func testTheDetectorAgreesOnThePitch() {
        for target in [440.0, 82.4] {
            var synth = ToneSynth(sampleRate: sampleRate, frequency: target)
            synth.targetAmplitude = ToneSynth.playingAmplitude
            let rendered = samples(&synth, seconds: 0.5)
            let detector = PitchDetector(sampleRate: sampleRate, band: Detection.fullBand)
            let window = Array(rendered[8192..<(8192 + Detection.windowSize)])
            guard let heard = detector.analyze(window).frequency else {
                XCTFail("the tone at \(target) must be detectable")
                continue
            }
            XCTAssertEqual(heard, target, accuracy: target * 0.002)
        }
    }

    /// The edges must not click: start and stop may not jump more than the
    /// held tone's own steepest sample-to-sample move (plus the envelope's
    /// tiny per-sample step).
    func testStartAndStopAreClickless() {
        var synth = ToneSynth(sampleRate: sampleRate, frequency: 440)
        synth.targetAmplitude = ToneSynth.playingAmplitude
        let attack = samples(&synth, seconds: 0.1)
        let steady = samples(&synth, seconds: 0.1)
        synth.targetAmplitude = 0
        let release = samples(&synth, seconds: 0.1)
        XCTAssertEqual(synth.amplitude, 0, "the release must land")
        XCTAssertFalse(synth.isAudible)
        let steadyJump = maxJump(steady)
        XCTAssertLessThanOrEqual(maxJump(attack), steadyJump * 1.05 + 0.002)
        XCTAssertLessThanOrEqual(maxJump(release), steadyJump * 1.05 + 0.002)
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
        _ = samples(&synth, seconds: 0.1)
        synth.targetFrequency = 660
        let gliding = samples(&synth, seconds: 0.02)
        XCTAssertTrue(
            (450...650).contains(synth.frequency),
            "20 ms in, the pitch is mid-glide, not teleported")
        let landing = samples(&synth, seconds: 0.2)
        XCTAssertEqual(synth.frequency, 660, accuracy: 0.05, "the glide lands")
        // The glide's own steepest move may not exceed the landed tone's —
        // the 660 Hz steady slope bounds everything.
        var steadySynth = ToneSynth(sampleRate: sampleRate, frequency: 660)
        steadySynth.targetAmplitude = ToneSynth.playingAmplitude
        _ = samples(&steadySynth, seconds: 0.1)
        let steadyJump = maxJump(samples(&steadySynth, seconds: 0.1))
        XCTAssertLessThanOrEqual(maxJump(gliding + landing), steadyJump * 1.05 + 0.002)
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
