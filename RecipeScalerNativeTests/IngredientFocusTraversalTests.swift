import XCTest
@testable import RecipeScalerNative

final class IngredientFocusTraversalTests: XCTestCase {
    func test_focus_traversal_keeps_three_decimal_amount() {
        let stored = IngredientData(
            id: "i1",
            name: "Flour",
            amount: "33.333",
            originalAmount: "33.333",
            unit: "г",
            order: 1
        )
        let draft = IngredientDraft(ingredient: stored)
        XCTAssertEqual(draft.amount, "33.333")
        XCTAssertTrue(
            IngredientData.focusTraversalIsUnchanged(
                name: draft.name,
                amount: draft.amount,
                base: stored
            )
        )
        let parsed = IngredientData.parsedQuantity(draft.amount)
        XCTAssertEqual(parsed.originalAmount, "33.333")
        XCTAssertNotEqual(parsed.originalAmount, "33.33")
    }
}
