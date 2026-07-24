import XCTest

/// Spec coverage: specs/026-recipe-collections/spec.md
///
/// Web parity: tests/e2e/specs/026-recipe-collections.spec.ts
///
///   - US1 — Recipes tab renders collections grid (yjs, not REST seed).
final class RecipeCollectionsSpec: BaseTestCase {
    func test_US1_recipeListRenders() {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        // "All recipes" collection tile is always present (virtual folder).
        XCTAssertTrue(
            recipeListPage.allCollectionsTile.waitForExistence(timeout: Wait.element),
            "'All recipes' virtual folder missing"
        )
    }
}
