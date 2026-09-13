import XCTest
@testable import RecipeScalerNative

final class ProcessTableMergeTests: XCTestCase {
    func testMergesConsecutiveFilledRows() {
        let spans = ProcessTableMerge.consecutiveFilledRows([false, true, true, true, false])
        XCTAssertEqual(spans, [ProcessTableSpan(startRow: 1, rowSpan: 3)])
    }

    func testSplitsFilledRunOnCellTitle() {
        let titles = [
            ProcessTableV1.CellTitle(ingredientId: "c", columnId: "col", title: "Second")
        ]
        let spans = ProcessTableMerge.mergeFilledRowsWithCellTitles(
            filled: [true, true, true],
            rowIds: ["a", "b", "c"],
            columnId: "col",
            cellTitles: titles
        )
        XCTAssertEqual(spans, [
            ProcessTableSpan(startRow: 0, rowSpan: 2),
            ProcessTableSpan(startRow: 2, rowSpan: 1),
        ])
    }

    func testEmptyCellsAreNotFilled() {
        XCTAssertEqual(ProcessTableMerge.consecutiveFilledRows([false, false]), [])
    }
}
