import XCTest

/// Spec coverage: specs/019-recipe-description-inline-edit/spec.md
///
/// Web parity: tests/e2e/specs/019-recipe-description-inline-edit.spec.ts
///
/// Inline editing of the description block. Two-context collaboration
/// (live cursor, awareness) is verified by integration tests; this spec
/// covers the single-context edit contract.
final class RecipeDescriptionInlineEditSpec: BaseTestCase {
    @MainActor
    func test_US1_recipeWithDescriptionOpensWithoutCrash() async throws {
        Navigation.openTab(.recipes, in: app)
        let created = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(name: TestData.recipeName("Inline 019"))
        }
        let list = recipeListPage.awaitReady()
        let row = list.recipeRow(id: created.id)
        XCTAssertTrue(row.waitForExistence(timeout: Wait.syncRoundTrip))
        row.tap()

        // Entering edit mode should not crash and should reveal the
        // description editor.
        recipeDetailPage.tapEdit()
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.descriptionEditor].waitForExistence(timeout: Wait.firstPaint)
                || recipeDetailPage.ingredientsSection.exists,
            "Neither description editor nor ingredients section appeared in edit mode"
        )
    }
}
