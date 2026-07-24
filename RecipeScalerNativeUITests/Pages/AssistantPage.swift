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

    /// Prefer `assistant_fab` id. Fall back to the localized FAB label when
    /// SwiftUI collapses the overlay id onto `root_content` (observed on
    /// iOS 26 simulator: button label "Assistant", id "root_content").
    var fab: XCUIElement {
        let byId = app.descendants(matching: .any)[UIA.assistantFab].firstMatch
        if byId.exists { return byId }
        return app.descendants(matching: .any).matching(
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
    func openViaFab() -> Self {
        guard fab.waitForExistence(timeout: Wait.element) else {
            XCTFail("Assistant FAB missing")
            return self
        }
        fab.tap()
        return self
    }

    @discardableResult
    func awaitSheet(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(sheet, timeout: timeout, "Assistant sheet")
        return self
    }
}
