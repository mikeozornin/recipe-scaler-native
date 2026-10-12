import XCTest

/// Spec coverage: specs/024-shopping-list/spec.md
///
/// Web parity: tests/e2e/specs/024-shopping-list-completion.spec.ts
///
///   - US1 — Add free-text item
///
/// The shopping list has no REST write API (a Yjs document), so items are added in the
/// app; the former REST-seeded US2 case could not seed and was removed.
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
}
