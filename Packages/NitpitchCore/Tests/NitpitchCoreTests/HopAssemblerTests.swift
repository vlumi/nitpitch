import XCTest

@testable import NitpitchCore

/// The window assembler's two promises: windows are hop-consecutive, and a
/// slow consumer costs the NEWEST readings' lag, never an unbounded queue —
/// with every discard announced as a gap so phase pairs never span it.
final class HopAssemblerTests: XCTestCase {
    private func ramp(from start: Int, count: Int) -> [Float] {
        (start..<(start + count)).map(Float.init)
    }

    func testWindowsAreHopConsecutiveWhateverTheChunking() {
        var assembler = HopAssembler(windowSize: 8, hopSize: 4, maxInFlight: 100)
        var out: [[Float]] = []
        var cursor = 0
        // Ragged chunks, as a tap delivers them.
        for size in [3, 9, 1, 12, 5, 6] {
            let batch = assembler.append(ramp(from: cursor, count: size))
            XCTAssertFalse(batch.gapBefore)
            out += batch.windows
            cursor += size
        }
        XCTAssertEqual(out.count, (36 - 8) / 4 + 1)
        for (i, window) in out.enumerated() {
            XCTAssertEqual(window, ramp(from: i * 4, count: 8), "window \(i) starts one hop later")
        }
    }

    func testASlowConsumerDropsTheOldestAndAnnouncesTheGap() {
        var assembler = HopAssembler(windowSize: 8, hopSize: 4, maxInFlight: 6)
        // Enough samples for eight windows at once, nothing finished yet.
        let batch = assembler.append(ramp(from: 0, count: 8 + 7 * 4))
        XCTAssertEqual(batch.windows.count, 6, "capped at the in-flight bound")
        XCTAssertEqual(
            batch.windows.count % 3, 0,
            "and rounded DOWN to whole runs — a stranded window measures nothing")
        XCTAssertTrue(batch.gapBefore, "two windows were discarded before these")
        XCTAssertEqual(batch.windows.first, ramp(from: 8, count: 8), "the newest survive")
        XCTAssertEqual(assembler.droppedWindows, 2)
        for (first, second) in zip(batch.windows, batch.windows.dropFirst()) {
            XCTAssertEqual(
                Array(first.suffix(4)), Array(second.prefix(4)),
                "what survives is CONSECUTIVE: the phase pair must not span a discard")
        }

        // Still nothing finished: everything new is dropped, nothing queued.
        let starved = assembler.append(ramp(from: 32, count: 8))
        XCTAssertEqual(starved, .empty)
        XCTAssertEqual(assembler.droppedWindows, 4, "two more windows, dropped")

        // The consumer catches up by a whole run: the next yield carries
        // the gap, and a run's worth of windows.
        assembler.finished(3)
        let resumed = assembler.append(ramp(from: 40, count: 12))
        XCTAssertEqual(resumed.windows.count, 3, "a whole run, never a stranded window")
        XCTAssertTrue(
            resumed.gapBefore, "the discard is announced on the first window after it")

        assembler.finished(3)
        let steady = assembler.append(ramp(from: 52, count: 12))
        XCTAssertFalse(steady.gapBefore, "announced once, then continuity resumes")
    }

    func testAKeepingUpConsumerNeverDrops() {
        var assembler = HopAssembler(windowSize: 8, hopSize: 4, maxInFlight: 2)
        var cursor = 0
        for _ in 0..<50 {
            let batch = assembler.append(ramp(from: cursor, count: 4))
            cursor += 4
            XCTAssertFalse(batch.gapBefore)
            assembler.finished(batch.windows.count)
        }
        XCTAssertEqual(assembler.droppedWindows, 0)
    }

    func testResetForgetsThePartialWindowAndTheBacklog() {
        var assembler = HopAssembler(windowSize: 8, hopSize: 4, maxInFlight: 1)
        _ = assembler.append(ramp(from: 0, count: 8 + 3))  // one in flight, 7 pending
        assembler.reset()
        let batch = assembler.append(ramp(from: 100, count: 8))
        XCTAssertEqual(
            batch.windows, [ramp(from: 100, count: 8)], "a clean window from the restart")
        XCTAssertFalse(batch.gapBefore, "a restart is the consumer's own reset, not a drop")
    }
}
