import XCTest

@testable import NitpitchCore

/// The focus rules, as scripted sequences — the interaction contract for
/// hands-free one-string-at-a-time tuning, pinned before any screen renders
/// it. A violin's four strings throughout: focus starts on G (index 0).
final class StringFocusTests: XCTestCase {
    /// Frames where only `index` sounds (at full strength); nil = silence.
    /// `inTune` nil while the focused string sounds = no verdict this frame
    /// (a gate flutter, an intonation frame vouching for the string).
    private func frame(_ focus: inout StringFocus, sounding index: Int?, inTune: Bool? = false)
        -> StringFocus.Event
    {
        var levels: [Double?] = [nil, nil, nil, nil]
        if let index { levels[index] = 1.0 }
        let focused = index == focus.focusIndex ? inTune : nil
        return focus.ingest(levels: levels, focusedInTune: focused)
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

    /// Backing the peg off un-settles: "done" tracks the string, not
    /// history. But it takes SUSTAINED out-of-tune reading — a wobble frame
    /// is not a detune (see testAWobbleAfterSettlingKeepsTheVerdict).
    func testGoingOutOfTuneUnsettles() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<StringFocus.settledFrames { _ = frame(&focus, sounding: 0, inTune: true) }
        XCTAssertTrue(focus.isSettled)

        for _ in 0..<StringFocus.unsettleFrames { _ = frame(&focus, sounding: 0, inTune: false) }

        XCTAssertFalse(focus.isSettled)
        // And rivals face the working threshold again.
        for _ in 0..<(StringFocus.switchFrames - 1) {
            XCTAssertEqual(frame(&focus, sounding: 3), .none)
        }
    }

    /// The frame after the settle haptic is often a decay wobble — an
    /// out-of-tune reading, or a frame with no verdict at all. The green
    /// must outlive its own announcement (field-found on a bass: the wrist
    /// buzzed success and the name never turned).
    func testAWobbleAfterSettlingKeepsTheVerdict() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<StringFocus.settledFrames { _ = frame(&focus, sounding: 0, inTune: true) }
        XCTAssertTrue(focus.isSettled)

        _ = frame(&focus, sounding: 0, inTune: false)
        XCTAssertTrue(focus.isSettled, "one wobble reading is not a detune")
        for _ in 0..<10 { _ = frame(&focus, sounding: 0, inTune: nil) }
        XCTAssertTrue(focus.isSettled, "no verdict is no evidence")
        _ = frame(&focus, sounding: 0, inTune: true)
        XCTAssertTrue(focus.isSettled)
    }

    /// A bass on a small microphone reads intermittently: in-tune frames
    /// arrive with gaps between them. Gaps decay the settle streak instead
    /// of erasing it — the same mercy the rival streaks needed — so the
    /// string still earns its green, just a little later.
    func testAnIntermittentInTuneReadingStillSettles() {
        var focus = StringFocus(stringCount: 4)

        var events: [StringFocus.Event] = []
        for count in 0..<(StringFocus.settledFrames * 3) {
            let dropped = count % 3 == 2
            events.append(
                frame(&focus, sounding: dropped ? nil : 0, inTune: !dropped))
        }
        XCTAssertTrue(events.contains(.settled))
        XCTAssertTrue(focus.isSettled)
        XCTAssertEqual(
            events.filter { $0 == .settled }.count, 1,
            "hovering around the threshold must not re-announce")
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
            let levels: [Double?] = [1.0, 1.0, nil, nil]
            XCTAssertEqual(focus.ingest(levels: levels, focusedInTune: false), .none)
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

    /// A sympathetic ring cannot steal the screen: plucking E on a bass
    /// with the other strings unmuted rings D — a genuine, sustained
    /// reading that OUTLIVES the pluck, but at a fraction of its strength
    /// (field-found on an old-strung bass). Duration alone would switch;
    /// the level bar says no.
    func testASympatheticRingCannotStealFocus() {
        var focus = StringFocus(stringCount: 4)

        // The pluck: E (focused) loud, briefly.
        for _ in 0..<5 {
            _ = focus.ingest(levels: [1.0, nil, nil, nil], focusedInTune: false)
        }
        // E decays below the gates; D rings on, weak, for ~3 seconds.
        for _ in 0..<64 {
            XCTAssertEqual(
                focus.ingest(levels: [nil, nil, 0.4, nil], focusedInTune: nil), .none)
        }
        XCTAssertEqual(focus.focusIndex, 0, "the ring never qualified")
    }

    /// A deliberately played rival at comparable strength still switches at
    /// the same pace as ever — the level bar is invisible to real play.
    func testAComparablyLoudRivalSwitchesAtFullPace() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<5 {
            _ = focus.ingest(levels: [1.0, nil, nil, nil], focusedInTune: false)
        }
        var switched: StringFocus.Event = .none
        var frames = 0
        while switched == .none, frames < StringFocus.switchFrames + 1 {
            switched = focus.ingest(levels: [nil, nil, 0.9, nil], focusedInTune: nil)
            frames += 1
        }
        XCTAssertEqual(switched, .focused(2))
        XCTAssertEqual(frames, StringFocus.switchFrames)
    }

    /// A marginal string reads INTERMITTENTLY — a bass A through a wrist
    /// microphone drops every few frames — and a single miss must not zero
    /// an almost-complete streak: the misses drain, the reads accumulate,
    /// and deliberate play still takes the screen (field-found: A could
    /// never be switched to).
    func testAnIntermittentDeliberateRivalStillSwitches() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<5 {
            _ = focus.ingest(levels: [1.0, nil, nil, nil], focusedInTune: false)
        }
        var switched = false
        for i in 0..<80 where !switched {
            let level: Double? = (i % 3 == 2) ? nil : 0.9
            if case .focused = focus.ingest(
                levels: [nil, level, nil, nil], focusedInTune: nil)
            {
                switched = true
            }
        }
        XCTAssertTrue(switched, "two reads in three frames is deliberate play")
        XCTAssertEqual(focus.focusIndex, 1)
    }

    /// A quiet but PERSISTENT player is never locked out: the remembered
    /// peak fades, so a string played softly for a few seconds eventually
    /// clears the bar and takes the screen.
    func testAQuietPersistentPlayerEventuallySwitches() {
        var focus = StringFocus(stringCount: 4)
        for _ in 0..<5 {
            _ = focus.ingest(levels: [1.0, nil, nil, nil], focusedInTune: false)
        }
        var switched = false
        for _ in 0..<200 where !switched {
            if case .focused = focus.ingest(levels: [nil, nil, 0.5, nil], focusedInTune: nil) {
                switched = true
            }
        }
        XCTAssertTrue(switched, "persistence at honest strength wins in the end")
        XCTAssertEqual(focus.focusIndex, 2)
    }
}
