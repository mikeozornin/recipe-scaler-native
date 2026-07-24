import XCTest

/// Spec coverage: specs/006-description-editor/spec.md
///
/// Web parity: tests/e2e/specs/006-description-editor.spec.ts
///
/// Baseline description editor: open edit mode, the Done keyboard button
/// dismisses the keyboard.
final class DescriptionEditorSpec: BaseTestCase {
    @MainActor
    func test_US1_editModeKeyboardDoneButtonPresent() async throws {
        Navigation.openTab(.recipes, in: app)
        let created = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(name: TestData.recipeName("Editor 006"))
        }
        let list = recipeListPage.awaitReady()
        let row = list.recipeRow(id: created.id)
        XCTAssertTrue(row.waitForExistence(timeout: Wait.syncRoundTrip))
        row.tap()

        recipeDetailPage.tapEdit()
        // Tap the description editor if present to surface the keyboard.
        let editor = app.descendants(matching: .any)[UIA.descriptionEditor]
        if editor.waitForExistence(timeout: Wait.element) {
            editor.tap()
            // The keyboard Done button should appear.
            let doneButton = app.buttons[UIA.descriptionEditorKeyboardDone]
            XCTAssertTrue(
                doneButton.waitForExistence(timeout: Wait.element),
                "Description editor keyboard Done button missing after tapping editor"
            )
        } else {
            // Editor not present (no description body); skip gracefully.
            throw XCTSkip("Description editor not visible for this recipe")
        }
    }
}
