import XCTest

@testable import NitpitchCore

/// The focus rules, as scripted sequences — the interaction contract for
/// hands-free one-string-at-a-time tuning, pinned before any screen renders
/// it. A violin's four strings throughout: focus starts on G (index 0).
final class StringFocusTests: XCTestCase {
    /// Frames where only `index` sounds; nil = silence.
    private func frame(_ focus: inout StringFocus, sounding index: Int?, inTune: Bool = false)
        -> StringFocus.Event
    {
        var sounding = [false, false, false, false]
        if let index { sounding[index] = true }
        let focused = index == focus.focusIndex ? inTune : nil
        return focus.ingest(sounding: sounding, focusedInTune: focused)
    }

    /// A hand crossing the strings brushes a neighbour for a few frames —
    /// the screen must not move.
    func testABrushDoesNotSteal() {
        var focus = StringFocus(stringCount: 4)

        for _ in 0..<10 { _ = frame(&focus, sounding: 0) }
        for _ in 0..<(StringFocus.switchFrames - 1) {
            XCTAssertEqual(frame(&focus, sounding: 1), .none)
        }
        _ = frame(&focus, sounding: 0)
        XCTAssertEqual(focus.focusIndex, 0, "a brush, however repeated, is not a move")
    }

    /// A string plucked to be tuned RINGS: sustained sounding takes focus.
    func testDeliberatePlayTakesFocus() {
        var focus = StringFocus(stringCount: 4)

        var events: [StringFocus.Event] = []
        for _ in 0..<StringFocus.switchFrames {
            events.append(frame(&focus, sounding: 2))
        }
        XCTAssertEqual(events.last, .focused(2))
        XCTAssertEqual(focus.focusIndex, 2)
    }

    /// The focused string sounding resets every rival: a brush ALONGSIDE
    /// the note being worked on never accumulates.
    func testWorkingResetsRivals() {
        var focus = StringFocus(stringCount: 4)

        for _ in 0..<(StringFocus.switchFrames - 1) { _ = frame(&focus, sounding: 1) }
        _ = frame(&focus, sounding: 0)  // the focused string speaks
        for _ in 0..<(StringFocus.switchFrames - 1) {
            XCTAssertEqual(frame(&focus, sounding: 1), .none)
        }
        XCTAssertEqual(focus.focusIndex, 0, "the counter restarted from zero")
    }

    /// Holding in tune settles the string — the done mark, and the haptic.
    func testHoldingInTuneSettles() {
        var focus = StringFocus(stringCount: 4)

        var events: [StringFocus.Event] = []
        for _ in 0..<StringFocus.settledFrames {
            events.append(frame(&focus, sounding: 0, inTune: true))
        }
        XCTAssertEqual(events.last, .settled)
        XCTAssertTrue(focus.isSettled)
        XCTAssertEqual(
            events.filter { $0 == .settled }.count, 1,
            "settling announces once, not every frame")
    }

    /// After settling, the threshold drops: the next string to speak takes
    /// the screen almost immediately — moving on is the expected act.
    func testSettledAdvancesFast() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<StringFocus.settledFrames { _ = frame(&focus, sounding: 0, inTune: true) }

        var events: [StringFocus.Event] = []
        for _ in 0..<StringFocus.switchFramesSettled {
            events.append(frame(&focus, sounding: 1))
        }
        XCTAssertEqual(events.last, .focused(1))
        XCTAssertFalse(focus.isSettled, "the new string is fresh work")
    }

    /// Backing the peg off un-settles: "done" tracks the string, not history.
    func testGoingOutOfTuneUnsettles() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<StringFocus.settledFrames { _ = frame(&focus, sounding: 0, inTune: true) }
        XCTAssertTrue(focus.isSettled)

        _ = frame(&focus, sounding: 0, inTune: false)

        XCTAssertFalse(focus.isSettled)
        // And rivals face the working threshold again.
        for _ in 0..<(StringFocus.switchFrames - 1) {
            XCTAssertEqual(frame(&focus, sounding: 3), .none)
        }
    }

    /// The crown: instant, no argument — and reports nothing, because the
    /// user's own act needs no echo.
    func testExplicitSelectIsInstant() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<StringFocus.settledFrames { _ = frame(&focus, sounding: 0, inTune: true) }

        focus.select(3)

        XCTAssertEqual(focus.focusIndex, 3)
        XCTAssertFalse(focus.isSettled)
        focus.select(9)
        XCTAssertEqual(focus.focusIndex, 3, "out of range is refused, not clamped")
    }

    /// A double stop that INCLUDES the focused string is still work on it.
    func testDoubleStopWithFocusStays() {
        var focus = StringFocus(stringCount: 4)

        for _ in 0..<(StringFocus.switchFrames * 2) {
            var sounding = [false, false, false, false]
            sounding[0] = true
            sounding[1] = true
            XCTAssertEqual(focus.ingest(sounding: sounding, focusedInTune: false), .none)
        }
        XCTAssertEqual(focus.focusIndex, 0)
    }

    /// Silence moves nothing — and a settled mark survives the quiet after
    /// the note dies, so the fast advance is still armed when the player
    /// reaches for the next string.
    func testSilenceHoldsEverything() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<StringFocus.settledFrames { _ = frame(&focus, sounding: 0, inTune: true) }

        for _ in 0..<50 {
            XCTAssertEqual(frame(&focus, sounding: nil), .none)
        }
        XCTAssertEqual(focus.focusIndex, 0)
        XCTAssertTrue(focus.isSettled, "quiet is not un-tuning")

        for _ in 0..<StringFocus.switchFramesSettled { _ = frame(&focus, sounding: 2) }
        XCTAssertEqual(focus.focusIndex, 2, "the fast advance survived the pause")
    }
}
