import XCTest

/// Spec coverage: specs/031-error-i18n/spec.md
///
/// Web parity: tests/e2e/specs/031-error-i18n.spec.ts
///
/// Error localization. Triggering an actual server error from XCUITest
/// is brittle; this spec verifies that the app's static text labels
/// never leak the raw error-i18n key prefix to the user.
final class ErrorI18nSpec: BaseTestCase {
    func test_US1_noRawErrorKeysVisible() {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()

        // Collect all static texts visible on the Recipes tab screen.
        let texts = app.staticTexts.allElementsBoundByIndex
        for text in texts {
            let label = text.label
            if label.contains("error.") || label.contains("errors.") {
                XCTFail("Raw i18n key leaked to UI: '\(label)'")
                return
            }
        }
    }
}
