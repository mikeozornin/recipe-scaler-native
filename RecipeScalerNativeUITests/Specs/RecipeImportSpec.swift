import XCTest

/// Spec coverage: specs/010-recipe-import/spec.md
///
/// Web parity: tests/e2e/specs/010-recipe-import.spec.ts
///
/// Imports a free-text recipe via the LLM extraction endpoint. The assistant
/// pipeline is non-deterministic, so this spec verifies the *contract* of the
/// UI flow rather than asserting on the resulting ingredient list (which
/// would flake).
final class RecipeImportSpec: BaseTestCase {
        /// Import sheet appears with the expected elements.
    func test_US1_importSheetHasTextInput() {
        Navigation.openTab(.importTab, in: app)
        let page = importPage.awaitReady()
        XCTAssertTrue(
            page.textEditor.waitForExistence(timeout: Wait.element),
            "Import text editor missing"
        )
    }

    /// File picker button is present.
    func test_US2_importFilePickerPresent() throws {
        Navigation.openTab(.importTab, in: app)
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
