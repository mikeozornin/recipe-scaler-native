import XCTest

/// Recipe detail screen.
///
/// Web parity: `recipeDetail` namespace in `helpers/selectors.ts`.
struct RecipeDetailPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var menuButton: XCUIElement { app.buttons[UIA.recipeDetailMenu] }
    var editButton: XCUIElement { app.buttons[UIA.recipeDetailEdit] }
    var ingredientsSection: XCUIElement { app.descendants(matching: .any)[UIA.ingredientsSection] }
    var stepsSection: XCUIElement { app.descendants(matching: .any)[UIA.stepsSection] }
    var newIngredientRow: XCUIElement { app.descendants(matching: .any)[UIA.recipeEditNewIngredientRow] }
    var newIngredientSubmit: XCUIElement { app.buttons[UIA.recipeEditNewIngredientSubmit] }
    var servingsRow: XCUIElement { app.descendants(matching: .any)[UIA.recipeEditServingsRow] }
    var scaleMinus: XCUIElement { app.buttons[UIA.scaleMinusButton] }
    var scalePlus: XCUIElement { app.buttons[UIA.scalePlusButton] }
    var imageUpload: XCUIElement { app.buttons[UIA.recipeImageUpload] }

    /// Edit mode toggle. Uses stable accessibility-id (preferred) — the legacy
    /// EN/RU label-matrix fallback handles older builds that haven't wired the
    /// id yet. See review finding Standards #17.
    var editNavButton: XCUIElement {
        let byId = app.buttons[UIA.recipeDetailEdit]
        if byId.waitForExistence(timeout: 1) { return byId }
        let edit = app.navigationBars.buttons["Edit"]
        if edit.waitForExistence(timeout: 1) { return edit }
        return app.navigationBars.buttons["Изменить"]
    }

    var doneNavButton: XCUIElement {
        let byId = app.buttons[UIA.recipeDetailDone]
        if byId.waitForExistence(timeout: 1) { return byId }
        let done = app.navigationBars.buttons["Done"]
        if done.waitForExistence(timeout: 1) { return done }
        return app.navigationBars.buttons["Готово"]
    }

    @discardableResult
    func tapEdit() -> Self {
        editNavButton.tap()
        return self
    }

    @discardableResult
    func tapDone() -> Self {
        doneNavButton.tap()
        return self
    }

    @discardableResult
    func tapMenu() -> Self {
        menuButton.tap()
        return self
    }
}
