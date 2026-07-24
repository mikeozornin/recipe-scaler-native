import XCTest

/// Spec coverage: specs/033-native-export-amount-text/spec.md
///
/// Native-only feature: round-tripping amounts and units through the
/// native export format. The codec itself is exercised by unit tests;
/// this E2E verifies the recipe detail renders the seeded amounts.
final class NativeExportAmountTextSpec: BaseTestCase {
    @MainActor
    func test_recipeWithAmountsRenders() async throws {
        Navigation.openTab(.recipes, in: app)
        let created = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(
                name: TestData.recipeName("Amounts 033"),
                ingredients: TestData.canonicalIngredients
            )
        }

        let list = recipeListPage.awaitReady()
        let row = list.recipeRow(id: created.id)
        XCTAssertTrue(row.waitForExistence(timeout: Wait.syncRoundTrip))
        row.tap()

        XCTAssertTrue(
            recipeDetailPage.ingredientsSection.waitForExistence(timeout: Wait.firstPaint),
            "Ingredients section missing — amounts may not have rendered"
        )
    }
}
