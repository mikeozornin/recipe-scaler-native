import RecipeScalerCore
import XCTest

final class IngredientIllustrationNameMatcherTests: XCTestCase {
    func testMatchesEggplantFromRussianName() {
        XCTAssertEqual(
            IngredientIllustrationNameMatcher.match(rawName: "Баклажаны, шт, г"),
            "eggplant"
        )
    }

    func testMatchesTomatoFromRussianName() {
        XCTAssertEqual(
            IngredientIllustrationNameMatcher.match(rawName: "Помидоры, шт, г"),
            "tomato"
        )
    }

    /// Shopping rows resolve their illustration in `body`, so every re-render
    /// re-matches every unbound label; a miss scans the whole alias index.
    func testRepeatedLookupsOfShoppingLabelsAreCheapAfterTheFirstRender() {
        let catalog = IngredientIllustrationCatalog()
        let labels = (0..<40).map { "Zzyzx товар \($0)" } + ["Помидоры, шт, г"]
        let expected: [String?] = Array(repeating: nil, count: 40) + ["tomato"]

        XCTAssertEqual(labels.map { IngredientIllustrationNameMatcher.match(rawName: $0, catalog: catalog) }, expected)

        let started = Date()
        for _ in 0..<10 {
            XCTAssertEqual(labels.map { IngredientIllustrationNameMatcher.match(rawName: $0, catalog: catalog) }, expected)
        }
        let perRenderMs = Date().timeIntervalSince(started) * 1000 / 10
        print("illustration match: \(String(format: "%.2f", perRenderMs)) ms per render of 41 rows")
        XCTAssertLessThan(perRenderMs, 2)
    }
}
