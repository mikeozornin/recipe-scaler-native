import XCTest
@testable import RecipeScalerNative

final class ResolveShoppingIllustrationIdTests: XCTestCase {
    func testStoredIllustrationIdWinsOverLabelMatch() {
        let item = ShoppingListItem(
            label: "200 g · Помидоры",
            illustrationId: "flour"
        )
        XCTAssertEqual(ResolveShoppingIllustrationId.resolve(item: item), "flour")
    }

    func testFallsBackToLabelMatcherWhenStoredIdMissing() {
        let item = ShoppingListItem(label: "250 g · Помидоры")
        XCTAssertEqual(ResolveShoppingIllustrationId.resolve(item: item), "tomato")
    }

    func testEmptyStoredIdFallsBackToLabelMatcher() {
        let item = ShoppingListItem(label: "Помидоры, шт, г", illustrationId: "   ")
        XCTAssertEqual(ResolveShoppingIllustrationId.resolve(item: item), "tomato")
    }
}
