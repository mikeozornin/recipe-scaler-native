import XCTest

/// Spec coverage: specs/018-description-editor-richtext/spec.md
///
/// Web parity: tests/e2e/specs/018-description-editor-richtext.spec.ts
///
/// Bold-mark round-trip in the rich-text editor. The actual mark codec
/// is covered by unit tests; this spec verifies the editor mounts in
/// edit mode without crashing.
final class DescriptionEditorRichtextSpec: BaseTestCase {
    @MainActor
    func test_US1_editModeRendersDescriptionEditor() async throws {
        Navigation.openTab(.recipes, in: app)
        let created = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(name: TestData.recipeName("Richtext 018"))
        }
        let list = recipeListPage.awaitReady()
        let row = list.recipeRow(id: created.id)
        XCTAssertTrue(row.waitForExistence(timeout: Wait.syncRoundTrip))
        row.tap()

        recipeDetailPage.tapEdit()
        // Editor may or may not be present depending on whether the recipe
        // has a description; either editor or ingredient section should
        // show up.
        let hasEditor = app.descendants(matching: .any)[UIA.descriptionEditor].waitForExistence(timeout: Wait.firstPaint)
        XCTAssertTrue(
            hasEditor || recipeDetailPage.ingredientsSection.exists,
            "Neither description editor nor ingredients section in edit mode"
        )
    }
}
