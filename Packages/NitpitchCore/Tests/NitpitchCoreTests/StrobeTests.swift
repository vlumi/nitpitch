import XCTest

@testable import NitpitchCore

/// The strobe's arithmetic, pinned: a cent of error at A440 crawls a
/// quarter revolution per second, direction follows sign, and the phase
/// wraps clean.
final class StrobeTests: XCTestCase {
    func testOneCentAtAFourFortyIsAQuarterRevolutionPerSecond() {
        XCTAssertEqual(
            StrobeIntegrator.hzError(cents: 1, targetHz: 440), 0.2546, accuracy: 0.0005)
        // Slightly smaller in magnitude than the sharp side: cents are a
        // ratio, and the exponential isn't symmetric about zero.
        XCTAssertEqual(
            StrobeIntegrator.hzError(cents: -1, targetHz: 440), -0.2541, accuracy: 0.0005)
    }

    func testIntegrationAccumulatesTheError() {
        var strobe = StrobeIntegrator()
        // One second of +1¢ at 440, in hop-sized steps.
        let dt = Double(Detection.hopSize) / 44100
        let steps = Int((1.0 / dt).rounded())
        for _ in 0..<steps {
            strobe.advance(cents: 1, targetHz: 440, dt: dt)
        }
        XCTAssertEqual(strobe.phase, 0.2546 * Double(steps) * dt, accuracy: 0.002)
    }

    /// Flat errors crawl the other way — and the wrap keeps phase in
    /// 0..<1 from either direction.
    func testFlatWrapsBackward() {
        var strobe = StrobeIntegrator()
        strobe.advance(cents: -10, targetHz: 440, dt: 0.2)
        XCTAssertGreaterThan(strobe.phase, 0.4, "backward past zero wraps high")
        XCTAssertLessThan(strobe.phase, 1)
    }

    func testInTuneIsStationary() {
        var strobe = StrobeIntegrator()
        for _ in 0..<100 {
            strobe.advance(cents: 0, targetHz: 440, dt: 0.05)
        }
        XCTAssertEqual(strobe.phase, 0, accuracy: 0.0001)
    }

    func testResetForgets() {
        var strobe = StrobeIntegrator()
        strobe.advance(cents: 5, targetHz: 440, dt: 0.5)
        strobe.reset()
        XCTAssertEqual(strobe.phase, 0)
    }
}
