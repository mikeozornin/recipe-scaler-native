import XCTest
@testable import RecipeScalerNative

final class ProcessTableDecodeTests: XCTestCase {
    func testParsesValidV1() {
        let hash = String(repeating: "a", count: 64)
        let raw = """
        {"version":1,"sourceHash":"\(hash)","columns":[{"id":"c1","title":"Mix","kind":"cook","stepIndex":0}],"assignments":[{"ingredientId":"ing1","columnId":"c1"}]}
        """
        let table = ProcessTableV1.parse(raw: raw)
        XCTAssertEqual(table?.version, 1)
        XCTAssertEqual(table?.columns.first?.kind, .cook)
        XCTAssertEqual(table?.assignments.first?.ingredientId, "ing1")
    }

    func testInvalidJSONAndUnknownVersionReturnNil() {
        XCTAssertNil(ProcessTableV1.parse(raw: "{not json"))
        let hash = String(repeating: "b", count: 64)
        let v2 = """
        {"version":2,"sourceHash":"\(hash)","columns":[{"id":"c1","title":"Mix","kind":"cook","stepIndex":0}],"assignments":[{"ingredientId":"ing1","columnId":"c1"}]}
        """
        XCTAssertNil(ProcessTableV1.parse(raw: v2))
        XCTAssertNil(ProcessTableV1.parse(raw: nil))
    }

    func testUnknownColumnKindFails() {
        let hash = String(repeating: "c", count: 64)
        let raw = """
        {"version":1,"sourceHash":"\(hash)","columns":[{"id":"c1","title":"Mix","kind":"other","stepIndex":0}],"assignments":[{"ingredientId":"ing1","columnId":"c1"}]}
        """
        XCTAssertNil(ProcessTableV1.parse(raw: raw))
    }
}
