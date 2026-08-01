import XCTest

@testable import TunerCore

final class ReadingSmootherTests: XCTestCase {
    func testConvergesToASteadyValue() {
        var smoother = ReadingSmoother()
        var last = 0.0
        for _ in 0..<40 { last = smoother.update(cents: 10) }
        XCTAssertEqual(last, 10, accuracy: 0.01)
    }

    func testRejectsAnIsolatedOutlier() {
        // One frame that landed on a harmonic must not visibly move the needle.
        var smoother = ReadingSmoother()
        for _ in 0..<10 { _ = smoother.update(cents: 5) }
        let before = smoother.current!
        let after = smoother.update(cents: 90)
        XCTAssertEqual(after, before, accuracy: 1.0, "a single bad frame moved the display")
    }

    func testSustainedChangeIsFollowed() {
        // A real peg turn (not an outlier) must actually track.
        var smoother = ReadingSmoother()
        for _ in 0..<10 { _ = smoother.update(cents: 5) }
        var last = 0.0
        for _ in 0..<20 { last = smoother.update(cents: 25) }
        XCTAssertEqual(last, 25, accuracy: 0.5)
    }

    func testNewNoteResetsRatherThanSliding() {
        // Jumping to a different string should snap, not sweep the needle
        // through every value in between.
        var smoother = ReadingSmoother()
        for _ in 0..<10 { _ = smoother.update(cents: 5) }
        let after = smoother.update(cents: 400)
        XCTAssertEqual(after, 400, accuracy: 0.01)
    }

    func testResetClearsState() {
        var smoother = ReadingSmoother()
        for _ in 0..<10 { _ = smoother.update(cents: 30) }
        smoother.reset()
        XCTAssertNil(smoother.current)
        XCTAssertEqual(smoother.update(cents: 8), 8, accuracy: 0.01)
    }

    func testFirstReadingIsShownImmediately() {
        var smoother = ReadingSmoother()
        XCTAssertEqual(smoother.update(cents: 17), 17, accuracy: 0.01)
    }
}
