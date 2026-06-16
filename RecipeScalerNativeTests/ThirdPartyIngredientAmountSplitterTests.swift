import XCTest
import RecipeScalerCore

final class ThirdPartyIngredientAmountSplitterTests: XCTestCase {
    func testSplitsAmountAndUnit() {
        let a = ThirdPartyIngredientAmountSplitter.split("225 g")
        XCTAssertEqual(a.amount, "225")
        XCTAssertEqual(a.unit, "g")
        let b = ThirdPartyIngredientAmountSplitter.split("2 tbsp")
        XCTAssertEqual(b.amount, "2")
        XCTAssertEqual(b.unit, "tbsp")
        let c = ThirdPartyIngredientAmountSplitter.split("200G")
        XCTAssertEqual(c.amount, "200")
        XCTAssertEqual(c.unit, "G")
    }

    func testNumericOnlyReturnsEmptyUnit() {
        let a = ThirdPartyIngredientAmountSplitter.split("3")
        XCTAssertEqual(a.amount, "3")
        XCTAssertEqual(a.unit, "")
        let b = ThirdPartyIngredientAmountSplitter.split("1.5")
        XCTAssertEqual(b.amount, "1.5")
        XCTAssertEqual(b.unit, "")
    }

    func testUnknownSuffixStaysCombined() {
        let result = ThirdPartyIngredientAmountSplitter.split("1 head")
        XCTAssertEqual(result.amount, "1 head")
        XCTAssertEqual(result.unit, "")
    }

    func testEmptyInput() {
        let empty = ThirdPartyIngredientAmountSplitter.split("")
        XCTAssertEqual(empty.amount, "")
        XCTAssertEqual(empty.unit, "")
        let spaces = ThirdPartyIngredientAmountSplitter.split("   ")
        XCTAssertEqual(spaces.amount, "")
        XCTAssertEqual(spaces.unit, "")
    }

    func testFractions() {
        let result = ThirdPartyIngredientAmountSplitter.split("1/2 cup")
        XCTAssertEqual(result.amount, "1/2")
        XCTAssertEqual(result.unit, "cup")
    }
}
