import XCTest

/// Spec coverage: specs/010-recipe-import/spec.md
///
/// Web parity: tests/e2e/specs/010-recipe-import.spec.ts
///
/// Imports a free-text recipe via the LLM extraction endpoint. The assistant
/// pipeline is non-deterministic, so this spec verifies the *contract* of the
/// UI flow rather than asserting on the resulting ingredient list (which
/// would flake).
///
/// Spec 074: Import left the tab bar; the spec presents the sheet via the
/// `-OpenTab=import` launch argument, and via the production "+" menu path
/// (spec 074 review: the menu entry had no UI-test coverage).
final class RecipeImportSpec: BaseTestCase {
    override func extraLaunchArguments() -> [String] {
        super.extraLaunchArguments() + ["-OpenTab", "import"]
    }

    /// Import sheet appears with the expected elements.
    func test_US1_importSheetHasTextInput() {
        Navigation.awaitImportSheet(in: app)
        let page = importPage.awaitReady()
        XCTAssertTrue(
            page.textEditor.waitForExistence(timeout: Wait.element),
            "Import text editor missing"
        )
    }

    /// File picker button is present.
    func test_US2_importFilePickerPresent() throws {
        Navigation.awaitImportSheet(in: app)
        let page = importPage.awaitReady()
        let picker = page.filePickButton
        // File picker is a stable CTA in the import sheet — its absence is a
        // real regression, not an env issue. Fail rather than skip. See
        // review finding Critical #5.
        XCTAssertTrue(
            picker.waitForExistence(timeout: Wait.element),
            "Import file picker not present — import sheet regressed"
        )
    }
}

/// Spec 074 review — production entry: Recipes tab → "+" menu → Import recipe.
/// No launch argument; navigation goes through the real UI.
final class RecipeImportMenuEntrySpec: BaseTestCase {
    func test_importSheetOpensFromPlusMenu() {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()

        recipeListPage.tapImportRecipe()

        Navigation.awaitImportSheet(in: app)
    }
}
