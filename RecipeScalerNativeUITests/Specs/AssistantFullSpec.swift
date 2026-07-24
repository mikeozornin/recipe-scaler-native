import XCTest

/// Spec coverage: specs/021-assistant-full/spec.md
///
/// Web parity: tests/e2e/specs/021-assistant-full.spec.ts (NDJSON stream).
///
/// Full streaming scenarios are flaky on native without a stub-server.
/// This spec verifies the sheet opens and exposes a text input + send control.
final class AssistantFullSpec: BaseTestCase {
    func test_US1_composerShellVisibleAfterOpen() throws {
        Navigation.openTab(.recipes, in: app)
        let page = assistantPage.openViaFab()
        XCTAssertTrue(
            page.sheet.waitForExistence(timeout: Wait.element),
            "Assistant sheet did not appear after FAB tap"
        )
        // Composer shell a11y id may be nested under sheet chrome on iOS 26,
        // but its absence means the assistant flow regressed — fail rather
        // than skip. See review finding Critical #5.
        let shell = page.composerShell
        XCTAssertTrue(
            shell.waitForExistence(timeout: Wait.element),
            "assistant_composer_shell not exposed after sheet opened"
        )
    }

    func test_US2_messageInputAcceptsText() throws {
        Navigation.openTab(.recipes, in: app)
        let page = assistantPage.openViaFab()
        XCTAssertTrue(page.sheet.waitForExistence(timeout: Wait.element), "Sheet missing")

        // Prefer dedicated a11y id; fall back to any text view in the sheet.
        var input = page.messageInput
        if !input.waitForExistence(timeout: Wait.element) {
            input = page.sheet.textViews.firstMatch
        }
        XCTAssertTrue(
            input.waitForExistence(timeout: Wait.element),
            "Assistant message input not found in sheet hierarchy"
        )
        input.tap()
        input.typeText("hello e2e")

        let send = page.sendButton
        XCTAssertTrue(
            send.waitForExistence(timeout: Wait.element),
            "Send button missing after typing — layout regressed"
        )
        XCTAssertTrue(send.exists)
    }
}
