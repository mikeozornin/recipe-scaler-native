import XCTest

/// Import sheet (`-OpenTab=import`).
///
/// Web parity: `importRecipe` namespace in `helpers/selectors.ts`.
struct ImportPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var sheet: XCUIElement { app.descendants(matching: .any)[UIA.importSheet] }
    var filePickButton: XCUIElement { app.buttons[UIA.importFilePickButton] }

    /// The text editor for pasting a recipe. Has no fixed accessibility id,
    /// so we find it by type within the import sheet.
    var textEditor: XCUIElement {
        sheet.textViews.firstMatch
    }

    /// The "Import" / "Импорт" submit button.
    var submitButton: XCUIElement {
        let buttons = sheet.buttons
        if buttons["Import"].waitForExistence(timeout: 1) { return buttons["Import"] }
        return buttons["Импортировать"]
    }

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(sheet, timeout: timeout, "Import sheet")
        return self
    }
}
