import XCTest

/// Spec coverage: specs/015-assistant/spec.md
///
/// Web parity: tests/e2e/specs/015-assistant.spec.ts (launcher + draft restore).
///
/// Native: the assistant FAB opens the sheet; draft restore preserves
/// in-progress composer text across FAB open/close cycles.
final class AssistantSpec: BaseTestCase {
    func test_US1_assistantFabVisible() throws {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        let fab = assistantPage.fab
        XCTAssertTrue(
            fab.waitForExistence(timeout: Wait.firstPaint),
            "Assistant FAB not found by id/label — assistant wiring regressed"
        )
    }

    func test_US2_openingFabShowsSheet() throws {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        let page = assistantPage
        XCTAssertTrue(
            page.fab.waitForExistence(timeout: Wait.element),
            "Assistant FAB not found by id/label — assistant wiring regressed"
        )
        page.fab.tap()
        XCTAssertTrue(
            page.sheet.waitForExistence(timeout: Wait.element),
            "Assistant sheet did not appear after FAB tap"
        )
    }
}
