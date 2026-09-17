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
        var assembler = HopAssembler(windowSize: 8, hopSize: 4, maxInFlight: 2)
        // Enough samples for five windows at once, nothing finished yet.
        let batch = assembler.append(ramp(from: 0, count: 8 + 4 * 4))
        XCTAssertEqual(batch.windows.count, 2, "capped at the in-flight bound")
        XCTAssertTrue(batch.gapBefore, "three windows were discarded before these")
        XCTAssertEqual(batch.windows.first, ramp(from: 12, count: 8), "the newest survive")
        XCTAssertEqual(assembler.droppedWindows, 3)

        // Still nothing finished: everything new is dropped, nothing queued.
        let starved = assembler.append(ramp(from: 24, count: 8))
        XCTAssertEqual(starved, .empty)
        XCTAssertEqual(assembler.droppedWindows, 5, "one more window, dropped")

        // The consumer catches up: the next yield still carries the gap.
        assembler.finished(2)
        let resumed = assembler.append(ramp(from: 32, count: 4))
        XCTAssertEqual(resumed.windows.count, 1)
        XCTAssertTrue(
            resumed.gapBefore, "the discard is announced on the first window after it")

        assembler.finished(1)
        let steady = assembler.append(ramp(from: 36, count: 4))
        XCTAssertEqual(steady.windows.count, 1)
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
