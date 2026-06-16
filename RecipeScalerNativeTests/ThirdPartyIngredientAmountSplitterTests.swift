import XCTest
import RecipeScalerCore

final class ThirdPartyIngredientAmountSplitterTests: XCTestCase {
    func testSplitsAmountAndUnit() {
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split("225 g"), ("225", "g"))
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split("2 tbsp"), ("2", "tbsp"))
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split("200G"), ("200", "G"))
    }

    func testNumericOnlyReturnsEmptyUnit() {
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split("3"), ("3", ""))
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split("1.5"), ("1.5", ""))
    }

    func testUnknownSuffixStaysCombined() {
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split("1 head"), ("1 head", ""))
    }

    func testEmptyInput() {
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split(""), ("", ""))
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split("   "), ("", ""))
    }

    func testFractions() {
        XCTAssertEqual(ThirdPartyIngredientAmountSplitter.split("1/2 cup"), ("1/2", "cup"))
    }
}
