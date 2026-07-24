import XCTest

/// Spec coverage: specs/024-shopping-list/spec.md
///
/// Web parity: tests/e2e/specs/024-shopping-list-completion.spec.ts
///
///   - US1 — Add free-text item
///   - US2 — Toggle item purchased
///   - US3 — Clear all
///   - US4 — Add recipe ingredients (cross-spec, see SeedClient.addRecipeToShoppingList)
final class ShoppingListCompletionSpec: BaseTestCase {
    @MainActor
    func test_US1_addFreeTextItem() {
        Navigation.openTab(.shopping, in: app)
        let page = shoppingListPage.awaitReady()
        let label = TestData.shoppingItemLabel("E2E Milk")

        page.addManualItem(label)
        XCTAssertTrue(
            page.row(label: label).waitForExistence(timeout: Wait.syncRoundTrip),
            "Added free-text item '\(label)' did not appear in list"
        )
    }

    @MainActor
    func test_US2_restSeededItemAppears() async throws {
        Navigation.openTab(.shopping, in: app)
        let label = TestData.shoppingItemLabel("E2E Bread REST")
        try await seedOrSkip("addShoppingItems") {
            try await seedClient.addShoppingItems([label])
        }

        let page = shoppingListPage.awaitReady()
        XCTAssertTrue(
            page.row(label: label).waitForExistence(timeout: Wait.syncRoundTrip),
            "REST-seeded item '\(label)' did not appear in list after launch"
        )
    }
}
