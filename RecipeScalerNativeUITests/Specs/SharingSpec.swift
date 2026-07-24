import XCTest

/// Spec coverage: specs/012-sharing/spec.md
///
/// Web parity: tests/e2e/specs/012-sharing.spec.ts
///
/// Share modes and public URL. The actual share-sheet cannot be dismissed
/// reliably in XCUITest, so this spec only verifies that opening a recipe
/// detail does not crash the share entry point.
final class SharingSpec: BaseTestCase {
    @MainActor
    func test_US1_recipeDetailOpensForSharedRecipe() async throws {
        Navigation.openTab(.recipes, in: app)
        let created = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(name: TestData.recipeName("Share 012"))
        }
        let list = recipeListPage.awaitReady()
        let row = list.recipeRow(id: created.id)
        XCTAssertTrue(row.waitForExistence(timeout: Wait.syncRoundTrip))
        row.tap()
        XCTAssertTrue(
            recipeDetailPage.ingredientsSection.waitForExistence(timeout: Wait.firstPaint)
                || recipeDetailPage.menuButton.exists,
            "Recipe detail did not render — share target may be broken"
        )
    }
}
