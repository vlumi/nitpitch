import XCTest

@testable import NitpitchCore

final class TuningDisplayTests: XCTestCase {
    // MARK: - Arc

    /// The filled arc *is* the error, so in tune it has to be nothing at all —
    /// not a small residue the eye has to judge against a mark.
    func testArcIsEmptyWhenPerfectlyInTune() {
        let arc = TuningDisplay.arc(forCents: 0)
        XCTAssertEqual(arc.sweepDegrees, 0, accuracy: 0.001)
        XCTAssertEqual(arc.thickness, 0, accuracy: 0.001)
    }

    func testArcSweepsOppositeWaysForSharpAndFlat() {
        let sharp = TuningDisplay.arc(forCents: 20)
        let flat = TuningDisplay.arc(forCents: -20)
        XCTAssertGreaterThan(sharp.sweepDegrees, 0)
        XCTAssertLessThan(flat.sweepDegrees, 0)
        // Equal error either way should read as equally wrong.
        XCTAssertEqual(sharp.sweepDegrees, -flat.sweepDegrees, accuracy: 0.001)
        XCTAssertEqual(sharp.thickness, flat.thickness, accuracy: 0.001)
    }

    func testArcSweepGrowsWithError() {
        let small = abs(TuningDisplay.arc(forCents: 8).sweepDegrees)
        let medium = abs(TuningDisplay.arc(forCents: 20).sweepDegrees)
        let large = abs(TuningDisplay.arc(forCents: 45).sweepDegrees)
        XCTAssertLessThan(small, medium)
        XCTAssertLessThan(medium, large)
    }

    /// Sweep tracks the error directly, so the filled length is proportional
    /// to how far off the note is.
    func testSweepIsLogarithmicLikeTheDots() {
        // The in-tune boundary gets real travel — linear sweep gave the
        // last two cents of a peg turn 3.6°, invisible exactly where
        // tuning happens.
        let boundary = abs(TuningDisplay.arc(forCents: 2).sweepDegrees)
        XCTAssertGreaterThan(boundary, 15)
        // Equal RATIOS of error get equal angular steps: each doubling
        // 2→4→8→16→32 adds exactly the same swing — the dots' geometry.
        let steps = [2.0, 4, 8, 16, 32].map {
            abs(TuningDisplay.arc(forCents: $0).sweepDegrees)
        }
        let deltas = zip(steps, steps.dropFirst()).map { $1 - $0 }
        for delta in deltas {
            XCTAssertEqual(delta, deltas[0], accuracy: 0.001)
        }
        // And the ticks agree with the readings about where 8¢ lives.
        let tick = TuningDisplay.ticks.first { $0.cents == 8 }!
        XCTAssertEqual(
            tick.degrees, TuningDisplay.arc(forCents: 8).sweepDegrees, accuracy: 0.001)
    }

    /// Thickness holds at zero through the in-tune band, so small wobbles
    /// around zero don't make the band pulse.
    func testArcStaysThinThroughTheInTuneBand() {
        for cents in [0.0, 2, -2, 5, -5] {
            XCTAssertEqual(
                TuningDisplay.arc(forCents: cents).thickness, 0, accuracy: 0.001,
                "\(cents)¢ is in tune and must not thicken the band")
        }
        XCTAssertGreaterThan(TuningDisplay.arc(forCents: 6).thickness, 0)
    }

    /// The arc and the lights read the same signal, so they must not disagree
    /// about which side of centre the note sits on.
    func testArcAndLightsAgreeOnDirection() {
        for cents in stride(from: -45.0, through: 45.0, by: 1.5) {
            let sweep = TuningDisplay.arc(forCents: cents).sweepDegrees
            let light = TuningDisplay.litLightIndex(forCents: cents)
            if light > TuningDisplay.centerLightIndex {
                XCTAssertGreaterThan(sweep, 0, "lights say sharp at \(cents)¢")
            } else if light < TuningDisplay.centerLightIndex {
                XCTAssertLessThan(sweep, 0, "lights say flat at \(cents)¢")
            }
        }
    }

    func testArcSaturatesBeyondFullScale() {
        let atFullScale = TuningDisplay.arc(forCents: TuningDisplay.fullScaleCents)
        let wayPast = TuningDisplay.arc(forCents: 400)
        XCTAssertEqual(atFullScale.sweepDegrees, TuningDisplay.fullScaleDegrees, accuracy: 0.001)
        XCTAssertEqual(wayPast.sweepDegrees, TuningDisplay.fullScaleDegrees, accuracy: 0.001)
        XCTAssertEqual(wayPast.thickness, 1, accuracy: 0.001)
    }

    /// The band must never wrap past the horizontal, where it would start to
    /// read as pointing the other way.
    func testArcNeverExceedsAQuarterTurn() {
        for cents in stride(from: -500.0, through: 500.0, by: 7.3) {
            XCTAssertLessThanOrEqual(
                abs(TuningDisplay.arc(forCents: cents).sweepDegrees), 90.0,
                "sweep escaped at \(cents)¢")
        }
    }

    func testArcHandlesNonFiniteInput() {
        XCTAssertEqual(TuningDisplay.arc(forCents: .nan).sweepDegrees, 0)
        XCTAssertEqual(TuningDisplay.arc(forCents: .infinity).sweepDegrees, 0)
    }

    // MARK: - Scale ticks

    /// Two scales on one screen that disagreed about where 8¢ sits would be
    /// worse than no scale at all, so the ticks reuse the lights' thresholds.
    func testTicksUseTheSameScaleAsTheLights() {
        let tickMagnitudes = Set(TuningDisplay.ticks.map { abs($0.cents) })
        for threshold in TuningDisplay.lightThresholds {
            XCTAssertTrue(tickMagnitudes.contains(threshold), "no tick at \(threshold)¢")
        }
    }

    func testTicksAreSymmetricAboutCentre() {
        let sharp = TuningDisplay.ticks.filter { $0.cents > 0 }.map(\.cents).sorted()
        let flat = TuningDisplay.ticks.filter { $0.cents < 0 }.map { -$0.cents }.sorted()
        XCTAssertEqual(sharp, flat)
        XCTAssertFalse(sharp.isEmpty)
    }

    /// Zero is the needle's job — a tick there would just thicken it.
    func testNoTickSitsAtZero() {
        XCTAssertFalse(TuningDisplay.ticks.contains { $0.cents == 0 })
    }

    /// A tick's angle has to be where the arc actually reaches at that offset,
    /// or the scale lies about the reading.
    func testTickAnglesMatchTheArcSweep() {
        for tick in TuningDisplay.ticks {
            XCTAssertEqual(
                tick.degrees, TuningDisplay.arc(forCents: tick.cents).sweepDegrees,
                accuracy: 0.001, "tick at \(tick.cents)¢ is not where the arc points")
        }
    }

    func testTicksStayWithinTheDial() {
        for tick in TuningDisplay.ticks {
            XCTAssertLessThanOrEqual(abs(tick.degrees), TuningDisplay.fullScaleDegrees)
        }
    }

    func testFullScaleIsMarkedAsMajor() {
        let extremes = TuningDisplay.ticks.filter { abs($0.cents) == TuningDisplay.fullScaleCents }
        XCTAssertEqual(extremes.count, 2)
        XCTAssertTrue(extremes.allSatisfy(\.isMajor))
    }

    // MARK: - Lights

    func testStripHasAnUnambiguousCentre() {
        // Odd count, so "in tune" is a single light rather than a gap between
        // two — the thing the player is aiming for has to be aimable at.
        XCTAssertEqual(TuningDisplay.lightCount % 2, 1)
        XCTAssertEqual(TuningDisplay.lightCount, 11)
        XCTAssertEqual(TuningDisplay.centerLightIndex, 5)
    }

    func testCentreLightCoversTheInnermostThreshold() {
        for cents in [0.0, 0.5, -0.5, 1.9, -1.9] {
            XCTAssertEqual(
                TuningDisplay.litLightIndex(forCents: cents), TuningDisplay.centerLightIndex,
                "\(cents)¢ should light the centre")
        }
    }

    func testSharpLightsRightAndFlatLightsLeft() {
        XCTAssertGreaterThan(
            TuningDisplay.litLightIndex(forCents: 10), TuningDisplay.centerLightIndex)
        XCTAssertLessThan(
            TuningDisplay.litLightIndex(forCents: -10), TuningDisplay.centerLightIndex)
    }

    func testLightsStepOutwardAtEachThreshold() {
        // Just past each threshold should be one light further out.
        var expected = TuningDisplay.centerLightIndex
        for threshold in TuningDisplay.lightThresholds {
            expected += 1
            XCTAssertEqual(
                TuningDisplay.litLightIndex(forCents: threshold + 0.1), expected,
                "just past \(threshold)¢")
        }
    }

    func testExtremeOffsetsClampToTheEndLights() {
        XCTAssertEqual(TuningDisplay.litLightIndex(forCents: 400), TuningDisplay.lightCount - 1)
        XCTAssertEqual(TuningDisplay.litLightIndex(forCents: -400), 0)
    }

    func testEveryLightIsReachable() {
        // A light that no offset can illuminate is a bug in the thresholds.
        var reached = Set<Int>()
        for tenths in -1000...1000 {
            reached.insert(TuningDisplay.litLightIndex(forCents: Double(tenths) / 10))
        }
        XCTAssertEqual(reached.count, TuningDisplay.lightCount)
    }

    func testLitLightIsFullStrengthAndNeighboursGlow() {
        let lit = TuningDisplay.litLightIndex(forCents: 10)
        XCTAssertEqual(TuningDisplay.lightIntensity(index: lit, cents: 10), 1, accuracy: 0.001)
        XCTAssertGreaterThan(TuningDisplay.lightIntensity(index: lit - 1, cents: 10), 0)
        XCTAssertEqual(TuningDisplay.lightIntensity(index: lit + 2, cents: 10), 0, accuracy: 0.001)
    }

    func testLightIndexIsAlwaysInBounds() {
        for cents in stride(from: -500.0, through: 500.0, by: 3.7) {
            let index = TuningDisplay.litLightIndex(forCents: cents)
            XCTAssertTrue(
                (0..<TuningDisplay.lightCount).contains(index), "out of bounds at \(cents)")
        }
        XCTAssertEqual(TuningDisplay.litLightIndex(forCents: .nan), TuningDisplay.centerLightIndex)
    }

    // MARK: - In-tune band

    func testInTuneBandMatchesTheReadout() {
        XCTAssertTrue(TuningDisplay.isInTune(cents: 0))
        XCTAssertTrue(TuningDisplay.isInTune(cents: 5))
        XCTAssertTrue(TuningDisplay.isInTune(cents: -5))
        XCTAssertFalse(TuningDisplay.isInTune(cents: 5.1))
        XCTAssertFalse(TuningDisplay.isInTune(cents: .nan))
    }
}
