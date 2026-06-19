import XCTest
import RecipeScalerCore

final class ThirdPartyIngredientAmountSplitterTests: XCTestCase {
    /// MIK-145 [review #62]: the splitter no longer recognizes a fixed set of
    /// units. It only validates that the input is numeric; any non-numeric
    /// suffix causes the whole input to be returned as `amount` with empty
    /// `unit`. There is intentionally no canonicalization (`g` vs `G`, `cup`
    /// vs `cups`) — units are preserved verbatim by the caller.
    func testNumericOnlyReturnsItselfWithEmptyUnit() {
        let a = ThirdPartyIngredientAmountSplitter.split("225")
        XCTAssertEqual(a.amount, "225")
        XCTAssertEqual(a.unit, "")
        let b = ThirdPartyIngredientAmountSplitter.split("1.5")
        XCTAssertEqual(b.amount, "1.5")
        XCTAssertEqual(b.unit, "")
        let c = ThirdPartyIngredientAmountSplitter.split("1/2")
        XCTAssertEqual(c.amount, "1/2")
        XCTAssertEqual(c.unit, "")
    }

    func testNumericSuffixStaysCombinedWithEmptyUnit() {
        // Input with a unit suffix is returned verbatim — no extraction.
        let g = ThirdPartyIngredientAmountSplitter.split("225 g")
        XCTAssertEqual(g.amount, "225 g")
        XCTAssertEqual(g.unit, "")
        let cups = ThirdPartyIngredientAmountSplitter.split("3 cups")
        XCTAssertEqual(cups.amount, "3 cups")
        XCTAssertEqual(cups.unit, "")
        let upper = ThirdPartyIngredientAmountSplitter.split("200G")
        XCTAssertEqual(upper.amount, "200G")
        XCTAssertEqual(upper.unit, "")
        let ru = ThirdPartyIngredientAmountSplitter.split("2 шт")
        XCTAssertEqual(ru.amount, "2 шт")
        XCTAssertEqual(ru.unit, "")
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
}
