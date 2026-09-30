import XCTest

/// Assistant sheet (launcher + composer).
///
/// Web parity: `assistant` namespace in `helpers/selectors.ts` +
/// `helpers/overlays.ts` (`openAssistantViaLauncher`, `assistantPanel`).
struct AssistantPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Spec 074 — assistant opens from the tab-bar button (`tab-assistant`).
    /// Fall back to the localized tab label when SwiftUI collapses the id onto
    /// an inner container.
    var tabButton: XCUIElement {
        let byId = app.buttons[UIA.assistantTab].firstMatch
        if byId.exists { return byId }
        return app.buttons.matching(
            NSPredicate(format: "label == %@ OR label CONTAINS[c] %@", "Assistant", "Assistant")
        ).firstMatch
    }

    var sheet: XCUIElement { app.descendants(matching: .any)[UIA.assistantSheet] }
    var composerShell: XCUIElement { app.descendants(matching: .any)[UIA.assistantComposerShell] }
    var messageInput: XCUIElement { app.textViews[UIA.assistantMessageInput] }
    var sendButton: XCUIElement { app.buttons[UIA.assistantSendButton] }
    var followUps: XCUIElement { app.descendants(matching: .any)[UIA.assistantFollowUps] }
    var markdownContent: XCUIElement { app.descendants(matching: .any)[UIA.assistantMarkdownContent] }
    var newThreadButton: XCUIElement { app.buttons[UIA.assistantNewThreadButton] }
    var historyButton: XCUIElement { app.buttons[UIA.assistantHistoryButton] }

    @discardableResult
    func openViaTab() -> Self {
        guard tabButton.waitForExistence(timeout: Wait.element) else {
            XCTFail("Assistant tab button missing")
            return self
        }
        tabButton.tap()
        return self
    }

    @discardableResult
    func awaitSheet(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(sheet, timeout: timeout, "Assistant sheet")
        return self
    }

    /// PI-3 (spec 074) — dismiss the sheet with a swipe down and wait until it
    /// is gone, so a follow-up open starts from a clean presentation state.
    /// The sheet root id can survive dismissal as a zombie presentation
    /// element on iOS 26 (`exists` stays true), so completion is asserted on
    /// the concrete composer shell inside the sheet.
    func dismissViaSwipe(timeout: TimeInterval = Wait.element) {
        let target = sheet.firstMatch
        guard target.waitForExistence(timeout: Wait.element) else {
            XCTFail("Assistant sheet not present to dismiss")
            return
        }
        target.swipeDown()
        // `isHittable == false` is not enough: the dismissed sheet can linger in
        // the a11y hierarchy and swallow touches on the list underneath. Require
        // full disappearance; fall back to a tab switch (spec 074 dismiss path).
        func sheetGone() -> Bool {
            !composerShell.exists && !target.exists
        }
        let gone = NSPredicate { [composerShell, target] _, _ in
            !composerShell.exists && !target.exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        if result != .completed {
            Navigation.openTab(.recipes, in: app)
            // Re-create the expectation: XCTNSPredicateExpectation is one-shot.
            let retry = XCTNSPredicateExpectation(predicate: gone, object: nil)
            _ = XCTWaiter().wait(for: [retry], timeout: timeout)
        }
        XCTAssertTrue(
            sheetGone(),
            "Assistant sheet still in hierarchy after dismiss — it swallows list taps"
        )
    }
}
