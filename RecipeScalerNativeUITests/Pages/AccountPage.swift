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

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(root, timeout: timeout, "Account")
        return self
    }
}
