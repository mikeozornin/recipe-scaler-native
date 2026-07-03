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
}