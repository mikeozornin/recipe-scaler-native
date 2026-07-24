import XCTest

/// Spec coverage: specs/022-i18n-new-views/spec.md
///
/// Web parity: tests/e2e/specs/022-i18n-new-views.spec.ts
///
/// EN↔RU persistence. Native reads the system locale and persists user
/// overrides via `appLng`. Full language-switch is exercised manually;
/// this E2E verifies the app renders with the device locale without
/// showing fallback keys.
final class I18nNewViewsSpec: BaseTestCase {
    func test_US1_appRendersLocalizedText() {
        Navigation.openTab(.recipes, in: app)
        // Tab buttons should have non-empty labels (i.e. the i18n keys
        // resolved to actual strings rather than printing the raw key).
        let recipesTab = app.buttons[UIA.tabRecipes]
        XCTAssertTrue(recipesTab.waitForExistence(timeout: Wait.firstPaint))
        let label = recipesTab.label
        XCTAssertFalse(
            label.isEmpty || label.contains("tab."),
            "Tab label looks like an unresolved i18n key: '\(label)'"
        )
    }
}
