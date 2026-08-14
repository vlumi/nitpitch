import XCTest

@testable import NitpitchData
@testable import NitpitchKit

/// The grid's visual arrangement, as the pure function it had to become:
/// building bottom-up rows and reversing the flat list read fine at 2×2 and
/// garbled everything whose count didn't divide the columns (a violin in
/// three columns showed E G D / A — neither convention).
final class GridRowsTests: XCTestCase {
    /// The field-reported shapes: violin and bass in three columns garbled;
    /// guitar in three divided evenly and looked fine.
    func testPartialRowsSitAtTheBottom() {
        // Violin (4) in 3 columns: G alone at bottom-left, D A E above —
        // the top-right corner is the highest string.
        XCTAssertEqual(
            InstrumentGridView.gridRows(count: 4, columns: 3, lowOnTop: false),
            [[1, 2, 3], [0]])
        // Guitar (6) in 3: two full rows, high half on top.
        XCTAssertEqual(
            InstrumentGridView.gridRows(count: 6, columns: 3, lowOnTop: false),
            [[3, 4, 5], [0, 1, 2]])
        // 5-string bass in 2: the odd string is the lowest, at the bottom.
        XCTAssertEqual(
            InstrumentGridView.gridRows(count: 5, columns: 2, lowOnTop: false),
            [[3, 4], [1, 2], [0]])
    }

    /// One column IS the strips: lowest at the bottom. One row is a piano:
    /// lowest at the left.
    func testDegenerateShapesMatchTheirMetaphors() {
        XCTAssertEqual(
            InstrumentGridView.gridRows(count: 4, columns: 1, lowOnTop: false),
            [[3], [2], [1], [0]])
        XCTAssertEqual(
            InstrumentGridView.gridRows(count: 4, columns: 4, lowOnTop: false),
            [[0, 1, 2, 3]])
    }

    /// The Settings flip: low on top reads like a plain list, partial row
    /// last — the pre-flip world, intact.
    func testLowOnTopReadsRowMajor() {
        XCTAssertEqual(
            InstrumentGridView.gridRows(count: 4, columns: 3, lowOnTop: true),
            [[0, 1, 2], [3]])
        XCTAssertEqual(
            InstrumentGridView.gridRows(count: 4, columns: 1, lowOnTop: true),
            [[0], [1], [2], [3]])
    }

    /// Every cell appears exactly once, whatever the shape — the invariant
    /// the flattened sequence hands to the grid.
    func testEveryStringAppearsExactlyOnce() {
        for count in 1...9 {
            for columns in 1...4 {
                for lowOnTop in [false, true] {
                    let rows = InstrumentGridView.gridRows(
                        count: count, columns: columns, lowOnTop: lowOnTop)
                    XCTAssertEqual(
                        rows.flatMap { $0 }.sorted(), Array(0..<count),
                        "count \(count), columns \(columns), lowOnTop \(lowOnTop)")
                    // In both modes the partial row is the bottom one — the
                    // last row rendered — so every row above it is full.
                    XCTAssertTrue(
                        rows.dropLast().allSatisfy { $0.count == max(1, columns) },
                        "only the bottom row may be partial: count \(count), columns \(columns)")
                }
            }
        }
    }

    func testEmptyAndZeroColumnInputsAreSafe() {
        XCTAssertEqual(InstrumentGridView.gridRows(count: 0, columns: 3, lowOnTop: false), [])
        XCTAssertEqual(
            InstrumentGridView.gridRows(count: 3, columns: 0, lowOnTop: false),
            [[2], [1], [0]],
            "zero columns clamps to one")
    }
}
