import XCTest

/// Spec coverage: specs/015-assistant/spec.md, specs/074-assistant-tab-entry/spec.md
///
/// Web parity: tests/e2e/specs/015-assistant.spec.ts (launcher + draft restore).
///
/// Native (spec 074): the assistant opens from the tab-bar button (fake tab);
/// the sheet presents over the current tab and the tab selection never changes.
final class AssistantSpec: BaseTestCase {
    func test_US1_assistantTabVisible() throws {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        let tabButton = assistantPage.tabButton
        XCTAssertTrue(
            tabButton.waitForExistence(timeout: Wait.firstPaint),
            "Assistant tab button not found by id/label — assistant wiring regressed"
        )
    }

    func test_US2_openingAssistantTabShowsSheet() throws {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        let page = assistantPage
        XCTAssertTrue(
            page.tabButton.waitForExistence(timeout: Wait.element),
            "Assistant tab button not found by id/label — assistant wiring regressed"
        )
        page.tabButton.tap()
        XCTAssertTrue(
            page.sheet.waitForExistence(timeout: Wait.element),
            "Assistant sheet did not appear after assistant tab tap"
        )
    }

    /// Spec 074 PI-3 — after dismissing the sheet (swipe down), tapping the
    /// assistant tab again must re-open it (the tab-open flag resets on
    /// consumption, so a stale presentation state must not block re-entry).
    func test_US3_reopeningAssistantAfterDismissShowsSheetAgain() throws {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        let page = assistantPage

        page.openViaTab().awaitSheet()
        page.dismissViaSwipe()

        XCTAssertTrue(
            page.tabButton.waitForExistence(timeout: Wait.element),
            "Assistant tab button missing after sheet dismiss"
        )
        page.openViaTab().awaitSheet()
    }
}
