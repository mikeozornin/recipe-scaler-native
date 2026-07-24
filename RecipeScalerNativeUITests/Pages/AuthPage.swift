import XCTest

/// Auth screen (shown when `-DisableDebugAutoLogin=1`).
struct AuthPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var root: XCUIElement { app.descendants(matching: .any)[UIA.authRoot] }
    var newUserButton: XCUIElement { app.buttons[UIA.authNewUserButton] }
    var existingUserButton: XCUIElement { app.buttons[UIA.authExistingUserButton] }
    var seedTextEditor: XCUIElement { app.textViews[UIA.authSeedTextEditor] }
    var loginButton: XCUIElement { app.buttons[UIA.authLoginButton] }
    var backButton: XCUIElement { app.buttons[UIA.authBackButton] }
    var qrCodeButton: XCUIElement { app.buttons[UIA.authQRCodeButton] }

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(root, timeout: timeout, "Auth")
        return self
    }
}
