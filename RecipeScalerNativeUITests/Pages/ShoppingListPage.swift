import XCTest

/// Shopping list screen (`-OpenTab=shopping`).
///
/// Web parity: `shopping` namespace in `helpers/selectors.ts`.
struct ShoppingListPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var root: XCUIElement { app.descendants(matching: .any)[UIA.shoppingList] }
    var addField: XCUIElement { app.textFields[UIA.shoppingAddField] }
    var shareButton: XCUIElement { app.buttons[UIA.shoppingShareButton] }
    var copyAsTextButton: XCUIElement { app.buttons[UIA.shoppingCopyAsTextButton] }

    /// Find a row by its visible label (matches both purchased and unpurchased).
    func row(label: String) -> XCUIElement {
        app.staticTexts[label]
    }

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.firstPaint) -> Self {
        awaitRoot(root, timeout: timeout, "ShoppingList")
        return self
    }

    /// Type a free-text item and commit with Enter.
    @discardableResult
    func addManualItem(_ label: String) -> Self {
        guard addField.waitForExistence(timeout: Wait.element) else {
            XCTFail("Shopping add field missing")
            return self
        }
        addField.tap()
        addField.typeText(label + "\n")
        return self
    }
}
