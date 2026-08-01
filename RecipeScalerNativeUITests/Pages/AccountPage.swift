import XCTest

/// Account / settings screen (`-OpenTab=profile`).
///
/// Web parity: `account` namespace in `helpers/selectors.ts`.
struct AccountPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var root: XCUIElement { app.descendants(matching: .any)[UIA.accountRoot] }
    /// First scroll view inside account — used to reveal below-the-fold content.
    var scrollView: XCUIElement { app.scrollViews.firstMatch }
    var telegramConnect: XCUIElement { app.buttons[UIA.accountTelegramConnect] }
    var telegramDisconnect: XCUIElement { app.buttons[UIA.accountTelegramDisconnect] }
    var telegramCode: XCUIElement { app.staticTexts[UIA.accountTelegramCode] }
    var telegramCopy: XCUIElement { app.buttons[UIA.accountTelegramCopy] }
    var telegramRefresh: XCUIElement { app.buttons[UIA.accountTelegramRefresh] }
    var timerNotificationsToggle: XCUIElement { app.buttons[UIA.accountTimerNotificationsToggle] }
    var exportLogsMissing: XCUIElement { app.staticTexts[UIA.accountExportLogsMissing] }
    var deleteAccountButton: XCUIElement { app.buttons[UIA.deleteAccountButton] }
    /// TextEditor under sheet.
    var deleteAccountSeedInput: XCUIElement {
        app.textViews[UIA.deleteAccountSeedInput]
    }
    var deleteAccountConfirmButton: XCUIElement {
        app.buttons[UIA.deleteAccountConfirmButton]
    }
    var deleteAccountCancelButton: XCUIElement {
        app.buttons[UIA.deleteAccountCancelButton]
    }
    var deleteAccountError: XCUIElement {
        app.staticTexts[UIA.deleteAccountError]
    }

    /// Scroll until the danger-zone delete button is visible (it's below the fold).
    /// SwiftUI `List` surfaces as collectionView/table in XCTest, not always scrollView.
    @discardableResult
    func revealDeleteAccount() -> XCUIElement {
        let button = deleteAccountButton
        if button.waitForExistence(timeout: Wait.element) {
            return button
        }
        for _ in 0..<4 where !button.exists {
            if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else if app.collectionViews.firstMatch.exists {
                app.collectionViews.firstMatch.swipeUp()
            } else if app.tables.firstMatch.exists {
                app.tables.firstMatch.swipeUp()
            } else {
                break
            }
        }
        return button
    }

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(root, timeout: timeout, "Account")
        return self
    }
}
